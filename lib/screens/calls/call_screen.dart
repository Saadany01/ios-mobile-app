import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../models/call_model.dart';
import '../../services/asl_service.dart';
import '../../services/auth_service.dart';
import '../../services/server_config.dart';
import '../../services/calls_service.dart';
import '../../services/turn_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    required this.callId,
    required this.isCaller,
    required this.mediaType,
    super.key,
  });

  final String callId;
  final bool isCaller;
  final String mediaType;

  bool get isVideoCall => mediaType == 'video';

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const int _ringingTimeoutSeconds = 25;

  late final CallsService _callsService;
  late final AuthService _authService;

  ActiveCallSession? _session;
  StreamSubscription<ActiveCallSession?>? _sessionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _candidateSubscription;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  final Set<String> _seenCandidateIds = <String>{};

  bool _remoteDescriptionApplied = false;
  bool _isClosing = false;
  bool _isAccepting = false;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _localMediaReady = false;
  bool _ringingTimeoutHandled = false;

  // ASL recognition
  AslService _aslService = AslService();
  bool _aslEnabled = false;
  bool _aslBusy = false;

  // current frame result
  String? _aslLetter;
  double _aslConfidence = 0;

  // continuous text accumulation
  String _aslText = '';
  String? _aslLastConfirmed;
  bool _aslLetterJustAdded = false;
  int _aslSameCount = 0;
  int _aslNoHandCount = 0;

  // word model — buffer only clean hand frames, run after 30 consecutive
  final List<List<List<double>>> _landmarkBuffer = [];
  int _landmarkMissCount = 0;   // frames without landmarks (hand left)
  String? _aslWord;
  bool _wordBusy = false;

  // data channel — sends local ASL text to remote peer
  RTCDataChannel? _aslDataChannel;
  String _remoteAslText = '';   // text received FROM the remote signer
  String? _remoteAslWord;

  Timer? _aslTimer;

  String _statusText = 'Connecting...';
  int _ringingSecondsLeft = _ringingTimeoutSeconds;
  Timer? _ringingCountdownTimer;
  DateTime? _localRingingDeadline;
  final Stopwatch _connectedStopwatch = Stopwatch();
  DateTime? _localCallStartedAt;
  bool _localCallEndPersisted = false;
  Timer? _connectedCallTimer;
  int _connectedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _callsService = context.read<CallsService>();
    _authService = context.read<AuthService>();
    _initRenderers();
    _bootstrap();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final url = await ServerConfig.getUrl();
    if (mounted) setState(() => _aslService = AslService(serverUrl: url));
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _candidateSubscription?.cancel();
    _ringingCountdownTimer?.cancel();
    _connectedCallTimer?.cancel();
    _aslTimer?.cancel();
    _aslDataChannel?.close();
    _connectedStopwatch.stop();

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        track.stop();
      }
      localStream.dispose();
    }

    final peerConnection = _peerConnection;
    _peerConnection = null;
    peerConnection?.close();

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    super.dispose();
  }

  Future<void> _bootstrap() async {
    _sessionSubscription = _callsService
        .watchCallSession(widget.callId)
        .listen(_onSessionUpdate);

    final session = await _callsService.getCallSession(widget.callId);
    if (!mounted) return;

    if (session == null) {
      _showMessage('Call session was not found.');
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _session = session;
      _statusText = _resolveStatusText(session);
    });
    _syncRingingCountdown(session);
    _syncConnectedCallTimer(session);

    if (widget.isCaller) {
      try {
        await _ensurePeerConnection(asCaller: true);
        await _createAndSendOffer();
      } catch (error) {
        if (!mounted) return;
        _showMessage(_resolveCallInitErrorMessage(error));
        await _finishAndClose();
      }
    }
  }

  String _resolveCallInitErrorMessage(Object error) {
    final errorText = error.toString().toLowerCase();
    if (errorText.contains('notallowederror')) {
      return widget.isVideoCall
          ? 'Camera and microphone permissions are required for video calls.'
          : 'Microphone permission is required for audio calls.';
    }
    return 'Failed to initialize call.';
  }

  void _onSessionUpdate(ActiveCallSession? session) {
    if (!mounted || _isClosing) return;

    if (session == null) {
      _finishAndClose();
      return;
    }

    setState(() {
      _session = session;
      _statusText = _resolveStatusText(session);
    });
    _syncRingingCountdown(session);
    _syncConnectedCallTimer(session);

    if (session.isTerminal) {
      _finishAndClose();
      return;
    }

    if (widget.isCaller &&
        session.answer != null &&
        !_remoteDescriptionApplied &&
        _peerConnection != null) {
      _applyAnswer(session.answer!);
    }

    if (!widget.isCaller &&
        session.status == CallSessionStatus.accepted &&
        session.offer != null &&
        _peerConnection != null &&
        !_remoteDescriptionApplied) {
      _applyOfferAndAnswer(session.offer!);
    }
  }

  Future<void> _ensurePeerConnection({required bool asCaller}) async {
    if (_peerConnection != null) return;

    final turnService = context.read<TurnService>();

    // Default STUN-only config; TURN is added below if available.
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];

    final turnResult = await turnService.fetchIceServers();
    if (turnResult != null) {
      final servers = turnResult['iceServers'];
      if (servers is List) {
        for (final server in servers) {
          if (server is Map<String, dynamic>) {
            iceServers.add(server);
          }
        }
      }
    }

    final configuration = <String, dynamic>{'iceServers': iceServers};

    final peerConnection = await createPeerConnection(configuration);

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': widget.isVideoCall
          ? {
              'width': {'ideal': 1280, 'min': 640},
              'height': {'ideal': 720, 'min': 480},
              'frameRate': {'ideal': 30},
              'facingMode': 'user',
            }
          : false,
    };

    final localStream = await navigator.mediaDevices.getUserMedia(
      mediaConstraints,
    );

    for (final track in localStream.getAudioTracks()) {
      await peerConnection.addTrack(track, localStream);
    }

    if (widget.isVideoCall) {
      for (final track in localStream.getVideoTracks()) {
        await peerConnection.addTrack(track, localStream);
      }

      _localRenderer.srcObject = localStream;
    }

    peerConnection.onConnectionState = (state) {
      if (!mounted) return;

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          setState(() {
            _statusText = 'Connected';
          });
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          setState(() {
            _statusText = 'Connection failed';
          });
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          setState(() {
            _statusText = 'Reconnecting...';
          });
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          setState(() {
            _statusText = 'Call ended';
          });
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          break;
      }
    };

    peerConnection.onTrack = (RTCTrackEvent event) {
      if (!mounted) return;

      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams.first;
      }
    };

    peerConnection.onRemoveTrack =
        (MediaStream stream, MediaStreamTrack track) {
          if (!mounted) return;
          if (track.kind == 'video') {
            _remoteRenderer.srcObject = null;
          }
        };

    // ── ASL data channel ─────────────────────────────────────────────
    if (asCaller) {
      // Caller creates the channel; callee receives it via onDataChannel
      final ch = await peerConnection.createDataChannel(
        'asl',
        RTCDataChannelInit()..ordered = true,
      );
      _bindDataChannel(ch);
    }
    peerConnection.onDataChannel = (ch) {
      if (ch.label == 'asl') _bindDataChannel(ch);
    };

    peerConnection.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null || candidateValue.isEmpty) return;

      _callsService.addIceCandidate(
        callId: widget.callId,
        fromCaller: asCaller,
        candidate: {
          'candidate': candidateValue,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _peerConnection = peerConnection;
    _localStream = localStream;
    _localMediaReady = true;

    _listenRemoteCandidates(forCaller: asCaller);

    if (!mounted) return;
    setState(() {});
  }

  void _listenRemoteCandidates({required bool forCaller}) {
    _candidateSubscription?.cancel();

    _candidateSubscription = _callsService
        .watchRemoteCandidates(callId: widget.callId, forCaller: forCaller)
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) {
              continue;
            }

            final doc = change.doc;
            if (_seenCandidateIds.contains(doc.id)) {
              continue;
            }
            _seenCandidateIds.add(doc.id);

            final data = doc.data();
            if (data == null || _peerConnection == null) {
              continue;
            }

            final candidate = (data['candidate'] ?? '').toString();
            if (candidate.isEmpty) {
              continue;
            }

            final remoteCandidate = RTCIceCandidate(
              candidate,
              _nullableString(data['sdpMid']),
              (data['sdpMLineIndex'] as num?)?.toInt(),
            );

            try {
              await _peerConnection!.addCandidate(remoteCandidate);
            } catch (_) {}
          }
        });
  }

  Future<void> _createAndSendOffer() async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) return;

    final offer = await peerConnection.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.isVideoCall ? 1 : 0,
    });
    await peerConnection.setLocalDescription(offer);

    await _callsService.saveOffer(
      callId: widget.callId,
      description: {'type': offer.type, 'sdp': offer.sdp},
    );
  }

  Future<void> _applyAnswer(Map<String, dynamic> answer) async {
    if (_remoteDescriptionApplied) return;

    final peerConnection = _peerConnection;
    if (peerConnection == null) return;

    final sdp = (answer['sdp'] ?? '').toString();
    final type = (answer['type'] ?? 'answer').toString();
    if (sdp.isEmpty) return;

    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionApplied = true;
  }

  Future<void> _applyOfferAndAnswer(Map<String, dynamic> offer) async {
    if (_remoteDescriptionApplied) return;

    final peerConnection = _peerConnection;
    if (peerConnection == null) return;

    final sdp = (offer['sdp'] ?? '').toString();
    final type = (offer['type'] ?? 'offer').toString();
    if (sdp.isEmpty) return;

    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionApplied = true;

    final answer = await peerConnection.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.isVideoCall ? 1 : 0,
    });
    await peerConnection.setLocalDescription(answer);

    await _callsService.saveAnswer(
      callId: widget.callId,
      description: {'type': answer.type, 'sdp': answer.sdp},
    );
  }

  Future<void> _acceptIncomingCall() async {
    if (_isAccepting) return;

    setState(() {
      _isAccepting = true;
    });

    try {
      await _callsService.acceptIncomingCall(callId: widget.callId);
      await _ensurePeerConnection(asCaller: false);

      final offer = _session?.offer;
      if (offer != null) {
        await _applyOfferAndAnswer(offer);
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(_resolveCallInitErrorMessage(error));
      await _finishAndClose();
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  Future<void> _declineOrHangup() async {
    final user = _authService.currentUser;
    final session = _session;

    if (user == null || session == null) {
      await _finishAndClose();
      return;
    }

    await _persistLocalCallEndIfNeeded();

    try {
      if (session.status == CallSessionStatus.ringing) {
        if (widget.isCaller) {
          await _callsService.cancelOutgoingCall(
            callId: widget.callId,
            canceledBy: user.uid,
          );
        } else {
          await _callsService.declineIncomingCall(
            callId: widget.callId,
            declinedBy: user.uid,
          );
        }
      } else {
        await _callsService.endActiveCall(
          callId: widget.callId,
          endedBy: user.uid,
        );
      }
    } catch (_) {
      // Ignore — the other party may have already ended the call
    }

    await _finishAndClose();
  }

  void _syncRingingCountdown(ActiveCallSession session) {
    _ringingCountdownTimer?.cancel();

    if (session.status != CallSessionStatus.ringing) {
      _ringingTimeoutHandled = false;
      _localRingingDeadline = null;
      if (_ringingSecondsLeft != _ringingTimeoutSeconds && mounted) {
        setState(() {
          _ringingSecondsLeft = _ringingTimeoutSeconds;
        });
      }
      return;
    }

    if (!widget.isCaller) {
      _localRingingDeadline = null;
      if (_ringingSecondsLeft != _ringingTimeoutSeconds && mounted) {
        setState(() {
          _ringingSecondsLeft = _ringingTimeoutSeconds;
        });
      }
      return;
    }

    _localRingingDeadline ??= DateTime.now().add(
      const Duration(seconds: _ringingTimeoutSeconds),
    );

    void tick() {
      if (!mounted || _isClosing) return;

      final deadline = _localRingingDeadline;
      if (deadline == null) return;

      final remaining = deadline
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, _ringingTimeoutSeconds)
          .toInt();

      if (_ringingSecondsLeft != remaining) {
        setState(() {
          _ringingSecondsLeft = remaining;
        });
      }

      if (remaining == 0) {
        _ringingCountdownTimer?.cancel();
        unawaited(_handleRingingTimeout());
      }
    }

    tick();
    if (_ringingSecondsLeft > 0) {
      _ringingCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        tick();
      });
    }
  }

  Future<void> _handleRingingTimeout() async {
    if (_ringingTimeoutHandled || _isClosing) return;
    if (!widget.isCaller) return;

    final session = _session;
    final user = _authService.currentUser;
    if (session == null || session.status != CallSessionStatus.ringing) return;

    _ringingTimeoutHandled = true;
    try {
      if (user != null) {
        if (widget.isCaller) {
          await _callsService.cancelOutgoingCall(
            callId: widget.callId,
            canceledBy: user.uid,
          );
        } else {
          await _callsService.declineIncomingCall(
            callId: widget.callId,
            declinedBy: user.uid,
          );
        }
      }
    } catch (_) {}

    if (!mounted) return;
    await _finishAndClose();
  }

  void _syncConnectedCallTimer(ActiveCallSession session) {
    if (session.status != CallSessionStatus.accepted) {
      _connectedStopwatch.stop();
      _connectedCallTimer?.cancel();
      _connectedCallTimer = null;
      if (_connectedSeconds != 0 && mounted) {
        setState(() {
          _connectedSeconds = 0;
        });
      }
      return;
    }

    if (_localCallStartedAt == null) {
      _localCallStartedAt = DateTime.now();
      unawaited(
        _callsService.saveLocalCallTiming(
          callId: widget.callId,
          localStartedAt: _localCallStartedAt,
        ),
      );
    }

    if (!_connectedStopwatch.isRunning) {
      if (_connectedStopwatch.elapsed == Duration.zero) {
        _connectedStopwatch.reset();
      }
      _connectedStopwatch.start();
    }

    void tick() {
      if (!mounted || _isClosing) return;
      final safeElapsed = _connectedStopwatch.elapsed.inSeconds;
      if (_connectedSeconds == safeElapsed) return;
      setState(() {
        _connectedSeconds = safeElapsed;
      });
    }

    tick();

    _connectedCallTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      tick();
    });
  }

  Future<void> _persistLocalCallEndIfNeeded() async {
    if (_localCallEndPersisted) return;

    final localStartedAt = _localCallStartedAt;
    if (localStartedAt == null) return;

    _localCallEndPersisted = true;
    try {
      await _callsService.saveLocalCallTiming(
        callId: widget.callId,
        localStartedAt: localStartedAt,
        localEndedAt: DateTime.now(),
      );
    } catch (_) {
      _localCallEndPersisted = false;
    }
  }

  Future<void> _toggleMute() async {
    final localStream = _localStream;
    if (localStream == null) return;

    final nextMuted = !_isMicMuted;
    for (final track in localStream.getAudioTracks()) {
      track.enabled = !nextMuted;
    }

    if (!mounted) return;
    setState(() {
      _isMicMuted = nextMuted;
    });
  }

  Future<void> _toggleCamera() async {
    final localStream = _localStream;
    if (localStream == null || !widget.isVideoCall) return;

    final nextOff = !_isCameraOff;
    for (final track in localStream.getVideoTracks()) {
      track.enabled = !nextOff;
    }

    if (!mounted) return;
    setState(() {
      _isCameraOff = nextOff;
    });
  }

  Future<void> _toggleSpeaker() async {
    final nextOn = !_isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(nextOn);
      if (!mounted) return;
      setState(() {
        _isSpeakerOn = nextOn;
      });
    } catch (_) {}
  }

  Future<void> _finishAndClose() async {
    if (_isClosing) return;
    _isClosing = true;
    _ringingCountdownTimer?.cancel();
    _connectedStopwatch.stop();
    _connectedCallTimer?.cancel();

    await _persistLocalCallEndIfNeeded();

    await _sessionSubscription?.cancel();
    await _candidateSubscription?.cancel();

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        track.stop();
      }
      await localStream.dispose();
    }

    final peerConnection = _peerConnection;
    _peerConnection = null;
    if (peerConnection != null) {
      await peerConnection.close();
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _resolveStatusText(ActiveCallSession session) {
    final label = widget.isVideoCall ? 'video' : 'audio';
    switch (session.status) {
      case CallSessionStatus.ringing:
        return widget.isCaller ? 'Ringing...' : 'Incoming $label call';
      case CallSessionStatus.accepted:
        return _localMediaReady ? 'Connected' : 'Connecting...';
      case CallSessionStatus.declined:
        return 'Call declined';
      case CallSessionStatus.canceled:
        return 'Call canceled';
      case CallSessionStatus.ended:
        return 'Call ended';
    }
  }

  String _peerName() {
    final session = _session;
    if (session == null) return 'Call';
    return widget.isCaller ? session.calleeName : session.callerName;
  }

  String? _peerPhotoUrl() {
    final session = _session;
    if (session == null) return null;

    final raw = widget.isCaller
        ? session.calleePhotoUrl
        : session.callerPhotoUrl;
    final normalized = (raw ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _peerInitials() {
    final safe = _peerName().trim();
    if (safe.isEmpty) return 'U';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }

  String _ringingTimerLabel() {
    final seconds = _ringingSecondsLeft.clamp(0, _ringingTimeoutSeconds);
    return '00:${seconds.toString().padLeft(2, '0')}';
  }

  String _connectedTimerLabel() {
    final total = _connectedSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String? _nullableString(dynamic value) {
    final resolved = (value ?? '').toString();
    return resolved.isEmpty ? null : resolved;
  }

  void _bindDataChannel(RTCDataChannel ch) {
    _aslDataChannel = ch;
    ch.onMessage = (msg) {
      if (!mounted) return;
      try {
        // messages are JSON: {"t":"HELLO ","w":"hello"}
        final data = json.decode(msg.text) as Map<String, dynamic>;
        setState(() {
          _remoteAslText = (data['t'] as String?) ?? '';
          _remoteAslWord = data['w'] as String?;
        });
      } catch (_) {
        setState(() => _remoteAslText = msg.text);
      }
    };
  }

  void _sendAslUpdate() {
    final ch = _aslDataChannel;
    if (ch == null) return;
    final payload = '{"t":${_encodeJson(_aslText)},"w":${_encodeJson(_aslWord)}}';
    try { ch.send(RTCDataChannelMessage(payload)); } catch (_) {}
  }

  String _encodeJson(String? s) => s == null ? 'null' : '"${s.replaceAll('"', '\\"')}"';

  void _toggleAsl() {
    if (_aslEnabled) {
      _aslTimer?.cancel();
      _aslTimer = null;
      setState(() {
        _aslEnabled = false;
        _aslLetter = null;
      });
    } else {
      setState(() {
        _aslEnabled = true;
        _aslText = '';
        _aslWord = null;
        _aslLastConfirmed = null;
        _aslLetterJustAdded = false;
        _aslSameCount = 0;
        _aslNoHandCount = 0;
      });
      _landmarkBuffer.clear();
      _landmarkMissCount = 0;
      _aslTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
        _runAslCapture();
      });
      _runAslCapture();
    }
  }

  void _aslClearText() {
    setState(() {
      _aslText = '';
      _aslWord = null;
    });
    _sendAslUpdate();
  }

  Future<void> _runAslCapture() async {
    if (_aslBusy || !_aslEnabled || _isClosing) return;
    final localStream = _localStream;
    if (localStream == null) return;
    final tracks = localStream.getVideoTracks();
    if (tracks.isEmpty) return;

    _aslBusy = true;
    try {
      final frameBuffer = await tracks.first.captureFrame();
      final prediction = await _aslService.predictFromBytes(
        frameBuffer.asUint8List(),
      );
      if (!mounted || !_aslEnabled) return;

      // ── No hand in frame ─────────────────────────────────────────────
      if (!prediction.handDetected) {
        _aslNoHandCount++;
        _aslSameCount = 0;
        _aslLetterJustAdded = false;
        // After 3 missed frames (~5s) add a space between words
        if (_aslNoHandCount == 3 &&
            _aslText.isNotEmpty &&
            !_aslText.endsWith(' ')) {
          setState(() {
            _aslText += ' ';
            _aslLetter = null;
          });
        } else {
          setState(() => _aslLetter = null);
        }
        return;
      }

      _aslNoHandCount = 0;

      final letter = prediction.predictedClass;
      final conf = prediction.confidence;

      // ── Buffer landmarks for word model ───────────────────────────────
      // Only buffer when landmarks are clean; reset on hand disappearance
      final lm = prediction.normLandmarks;
      if (lm != null) {
        _landmarkMissCount = 0;
        _landmarkBuffer.add(lm);
        if (_landmarkBuffer.length >= 30 && !_wordBusy) {
          final seq = List<List<List<double>>>.from(_landmarkBuffer);
          _landmarkBuffer.clear();
          _runWordPrediction(seq);
        }
      } else {
        _landmarkMissCount++;
        if (_landmarkMissCount >= 2) {
          // Hand left frame — if we had a partial sequence, try predicting it
          if (_landmarkBuffer.length >= 15 && !_wordBusy) {
            // Pad short sequence by repeating last frame
            final padded = List<List<List<double>>>.from(_landmarkBuffer);
            while (padded.length < 30) padded.add(padded.last);
            _landmarkBuffer.clear();
            _runWordPrediction(padded);
          } else {
            _landmarkBuffer.clear();
          }
          _landmarkMissCount = 0;
        }
      }

      // ── Update displayed letter ───────────────────────────────────────
      setState(() {
        _aslLetter = letter;
        _aslConfidence = conf;
      });

      // Only accumulate letters with good confidence
      if (conf < 0.72 || letter == 'nothing' || letter == 'del') return;

      // ── Letter accumulation logic ─────────────────────────────────────
      if (letter == _aslLastConfirmed) {
        if (!_aslLetterJustAdded) {
          _aslSameCount++;
          if (_aslSameCount >= 2) {
            // confirmed — add to text and send to remote
            setState(() => _aslText += letter.toUpperCase());
            _aslLetterJustAdded = true;
            _sendAslUpdate();
          }
        }
      } else {
        // new letter — reset
        _aslLastConfirmed = letter;
        _aslSameCount = 1;
        _aslLetterJustAdded = false;
      }
    } catch (e) {
      if (mounted) _showMessage('ASL error: $e');
    } finally {
      _aslBusy = false;
    }
  }

  Future<void> _runWordPrediction(List<List<List<double>>> seq) async {
    _wordBusy = true;
    try {
      final result = await _aslService.predictWord(seq);
      if (!mounted || !_aslEnabled || result == null) return;
      if (result.confidence > 0.6) {
        setState(() {
          _aslWord = result.predictedClass;
        });
        _sendAslUpdate();
      }
    } finally {
      _wordBusy = false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── UI ───────────────────────────────────────────────────────────────

  bool get _showVideoUI =>
      widget.isVideoCall &&
      _session?.status == CallSessionStatus.accepted &&
      _localMediaReady;

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final isIncomingRinging =
        !widget.isCaller && session?.status == CallSessionStatus.ringing;
    final isRinging = session?.status == CallSessionStatus.ringing;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_showVideoUI)
            _buildVideoBackground()
          else ...[
            _buildAudioBackground(),
            _buildAudioProfileSection(isRinging, session),
          ],
          _buildStatusOverlay(isIncomingRinging, isRinging, session),
          _buildControls(isIncomingRinging),
        ],
      ),
    );
  }

  // ── Video background (connected video call) ─────────────────────────

  Widget _buildVideoBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
        Positioned(top: 40, right: 16, child: _buildPipView()),
        // Local signer: letter bubble when detected, scanning indicator when active but no hand yet
        if (_aslEnabled)
          Positioned(
            top: 44,
            left: 16,
            child: _aslLetter != null
                ? _buildAslLetterBubble()
                : _buildAslScanningBubble(),
          ),
        // Remote ASL: text sent FROM the other person — shown prominently
        if (_remoteAslText.trim().isNotEmpty || _remoteAslWord != null)
          Positioned(
            bottom: 130,
            left: 12,
            right: 12,
            child: _buildRemoteAslBar(),
          ),
        // Local signer: their own accumulating text (small, bottom-right)
        if (_aslEnabled && _aslText.trim().isNotEmpty)
          Positioned(
            bottom: 130,
            right: 12,
            child: _buildLocalSigningIndicator(),
          ),
      ],
    );
  }

  // Small letter bubble — shown to the LOCAL signer (top-left, subtle)
  Widget _buildAslLetterBubble() {
    final pct = (_aslConfidence * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF25D366), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _aslLetter!.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF25D366),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text('$pct%', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  // Subtle indicator shown when ASL is active but no hand is in frame yet
  Widget _buildAslScanningBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF25D366),
            ),
          ),
          SizedBox(width: 6),
          Text(
            'Scanning…',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Prominent bar shown to the RECIPIENT — their partner is signing this
  Widget _buildRemoteAslBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF25D366), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_remoteAslWord != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF25D366), size: 13),
                  const SizedBox(width: 4),
                  Text(
                    _remoteAslWord!,
                    style: const TextStyle(
                      color: Color(0xFF25D366),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            _remoteAslText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Small indicator for the LOCAL signer — their own typed text (bottom-right)
  Widget _buildLocalSigningIndicator() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.50),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _aslText,
              style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _aslClearText,
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.backspace_outlined, color: Colors.white38, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipView() {
    return GestureDetector(
      onTap: _toggleCamera,
      child: Container(
        width: 120,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: _isCameraOff
            ? Container(
                color: Colors.black54,
                child: const Center(
                  child: Icon(Icons.videocam_off, color: Colors.white54),
                ),
              )
            : RTCVideoView(
                _localRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: true,
              ),
      ),
    );
  }

  // ── Audio-only background ───────────────────────────────────────────

  Widget _buildAudioBackground() {
    final peerPhotoUrl = _peerPhotoUrl();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (peerPhotoUrl != null)
          Image.network(
            peerPhotoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(color: Colors.black.withOpacity(0.45)),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0xB2000000)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioProfileSection(bool isRinging, ActiveCallSession? session) {
    final peerPhotoUrl = _peerPhotoUrl();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 58,
              backgroundColor: Colors.white24,
              backgroundImage: peerPhotoUrl == null
                  ? null
                  : NetworkImage(peerPhotoUrl),
              child: peerPhotoUrl == null
                  ? Text(
                      _peerInitials(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 18),
            Text(
              _peerName(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            if (isRinging) ...[
              const SizedBox(height: 6),
              Text(
                _ringingTimerLabel(),
                style: const TextStyle(
                  color: Color(0xFF25D366),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ] else if (session?.status == CallSessionStatus.accepted) ...[
              const SizedBox(height: 6),
              Text(
                _connectedTimerLabel(),
                style: const TextStyle(
                  color: Color(0xFF25D366),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
            if (!_localMediaReady &&
                (session?.status == CallSessionStatus.accepted)) ...[
              const SizedBox(height: 14),
              const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  // ── Status overlay (timer, name on video) ───────────────────────────

  Widget _buildStatusOverlay(
    bool isIncomingRinging,
    bool isRinging,
    ActiveCallSession? session,
  ) {
    if (!_showVideoUI) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
        child: Column(
          children: [
            Text(
              _peerName(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
            const SizedBox(height: 4),
            if (session?.status == CallSessionStatus.accepted)
              Text(
                _connectedTimerLabel(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Call controls ───────────────────────────────────────────────────

  Widget _buildControls(bool isIncomingRinging) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
          child: isIncomingRinging
              ? _buildIncomingControls()
              : _buildActiveControls(),
        ),
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _fab(
          heroTag: 'decline_call',
          color: Colors.red,
          icon: Icons.call_end,
          onPressed: _declineOrHangup,
        ),
        _fab(
          heroTag: 'accept_call',
          color: Colors.green,
          icon: Icons.call,
          onPressed: _isAccepting ? null : _acceptIncomingCall,
          child: _isAccepting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildActiveControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _fab(
          heroTag: 'mute_call',
          color: _isMicMuted ? Colors.white38 : Colors.white24,
          icon: _isMicMuted ? Icons.mic_off : Icons.mic,
          onPressed: _toggleMute,
        ),
        if (widget.isVideoCall)
          _fab(
            heroTag: 'camera_toggle',
            color: _isCameraOff ? Colors.white38 : Colors.white24,
            icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
            onPressed: _toggleCamera,
          ),
        if (widget.isVideoCall)
          _fab(
            heroTag: 'asl_toggle',
            color: _aslEnabled ? const Color(0xFF25D366) : Colors.white24,
            icon: Icons.pan_tool,
            onPressed: _toggleAsl,
          ),
        _fab(
          heroTag: 'speaker_toggle',
          color: _isSpeakerOn ? Colors.white24 : Colors.white38,
          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
          onPressed: _toggleSpeaker,
        ),
        _fab(
          heroTag: 'hangup_call',
          color: Colors.red,
          icon: Icons.call_end,
          onPressed: _declineOrHangup,
        ),
      ],
    );
  }

  Widget _fab({
    required String heroTag,
    required Color color,
    required IconData icon,
    VoidCallback? onPressed,
    Widget? child,
  }) {
    return FloatingActionButton(
      heroTag: heroTag,
      backgroundColor: color,
      onPressed: onPressed,
      child: child ?? Icon(icon),
    );
  }
}
