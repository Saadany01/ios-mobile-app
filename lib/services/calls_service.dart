import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/call_model.dart';

class CallsService {
  CallsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _userCallsCollection(
    String userId,
  ) {
    return _firestore.collection('users').doc(userId).collection('calls');
  }

  CollectionReference<Map<String, dynamic>> _activeCallsCollection() {
    return _firestore.collection('active_calls');
  }

  DocumentReference<Map<String, dynamic>> _activeCallDoc(String callId) {
    return _activeCallsCollection().doc(callId);
  }

  CollectionReference<Map<String, dynamic>> _callerCandidatesCollection(
    String callId,
  ) {
    return _activeCallDoc(callId).collection('callerCandidates');
  }

  CollectionReference<Map<String, dynamic>> _calleeCandidatesCollection(
    String callId,
  ) {
    return _activeCallDoc(callId).collection('calleeCandidates');
  }

  Stream<List<CallRecord>> watchCalls(String userId) {
    return _userCallsCollection(
      userId,
    ).orderBy('timestamp', descending: true).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => CallRecord.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  Stream<ActiveCallSession?> watchCallSession(String callId) {
    return _activeCallDoc(callId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;
      return ActiveCallSession.fromFirestore(data, snapshot.id);
    });
  }

  Future<ActiveCallSession?> getCallSession(String callId) async {
    final snapshot = await _activeCallDoc(callId).get();
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    if (data == null) return null;
    return ActiveCallSession.fromFirestore(data, snapshot.id);
  }

  Stream<ActiveCallSession?> watchIncomingCall(String userId) {
    return _activeCallsCollection()
        .where('calleeId', isEqualTo: userId)
        .where('status', isEqualTo: CallSessionStatus.ringing.value)
        .snapshots()
        .map((snapshot) {
          return _selectLatestIncomingRingingCall(
            snapshot.docs,
            userId: userId,
          );
        });
  }

  Future<ActiveCallSession?> getLatestIncomingRingingCall(String userId) async {
    final snapshot = await _activeCallsCollection()
        .where('calleeId', isEqualTo: userId)
        .where('status', isEqualTo: CallSessionStatus.ringing.value)
        .get();

    return _selectLatestIncomingRingingCall(snapshot.docs, userId: userId);
  }

  Future<ActiveCallSession> startCall({
    required String callerId,
    required String callerName,
    String? callerPhotoUrl,
    required String calleeId,
    required String calleeName,
    String? calleePhotoUrl,
    String mediaType = 'audio',
  }) async {
    final normalizedMediaType = mediaType == 'video' ? 'video' : 'audio';
    final now = DateTime.now();
    final docRef = _activeCallsCollection().doc();

    await docRef.set({
      'callerId': callerId,
      'callerName': callerName,
      'callerPhotoUrl': (callerPhotoUrl ?? '').trim(),
      'calleeId': calleeId,
      'calleeName': calleeName,
      'calleePhotoUrl': (calleePhotoUrl ?? '').trim(),
      'status': CallSessionStatus.ringing.value,
      'mediaType': normalizedMediaType,
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.fromDate(now),
      'startedAt': null,
      'endedAt': null,
      'endedBy': null,
      'offer': null,
      'answer': null,
      'historyWritten': false,
    });

    return ActiveCallSession(
      id: docRef.id,
      callerId: callerId,
      callerName: callerName,
      callerPhotoUrl: callerPhotoUrl,
      calleeId: calleeId,
      calleeName: calleeName,
      calleePhotoUrl: calleePhotoUrl,
      status: CallSessionStatus.ringing,
      mediaType: normalizedMediaType,
      createdAt: now,
      historyWritten: false,
    );
  }

  Future<void> saveOffer({
    required String callId,
    required Map<String, dynamic> description,
  }) {
    return _activeCallDoc(callId).update({
      'offer': {
        'type': (description['type'] ?? '').toString(),
        'sdp': (description['sdp'] ?? '').toString(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveAnswer({
    required String callId,
    required Map<String, dynamic> description,
  }) {
    return _activeCallDoc(callId).update({
      'answer': {
        'type': (description['type'] ?? '').toString(),
        'sdp': (description['sdp'] ?? '').toString(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addIceCandidate({
    required String callId,
    required bool fromCaller,
    required Map<String, dynamic> candidate,
  }) {
    final collection = fromCaller
        ? _callerCandidatesCollection(callId)
        : _calleeCandidatesCollection(callId);

    return collection.add({
      'candidate': candidate['candidate'],
      'sdpMid': candidate['sdpMid'],
      'sdpMLineIndex': candidate['sdpMLineIndex'],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRemoteCandidates({
    required String callId,
    required bool forCaller,
  }) {
    final collection = forCaller
        ? _calleeCandidatesCollection(callId)
        : _callerCandidatesCollection(callId);

    return collection.orderBy('createdAt').snapshots();
  }

  Future<void> acceptIncomingCall({required String callId}) {
    return _activeCallDoc(callId).update({
      'status': CallSessionStatus.accepted.value,
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveLocalCallTiming({
    required String callId,
    DateTime? localStartedAt,
    DateTime? localEndedAt,
  }) {
    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (localStartedAt != null) {
      payload['clientStartedAt'] = Timestamp.fromDate(localStartedAt);
    }
    if (localEndedAt != null) {
      payload['clientEndedAt'] = Timestamp.fromDate(localEndedAt);
    }

    if (payload.length == 1) {
      return Future<void>.value();
    }

    return _activeCallDoc(callId).set(payload, SetOptions(merge: true));
  }

  Future<void> declineIncomingCall({
    required String callId,
    required String declinedBy,
  }) async {
    await _activeCallDoc(callId).update({
      'status': CallSessionStatus.declined.value,
      'endedBy': declinedBy,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writeHistoryIfNeeded(callId);
  }

  Future<void> cancelOutgoingCall({
    required String callId,
    required String canceledBy,
  }) async {
    await _activeCallDoc(callId).update({
      'status': CallSessionStatus.canceled.value,
      'endedBy': canceledBy,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writeHistoryIfNeeded(callId);
  }

  Future<void> endActiveCall({
    required String callId,
    required String endedBy,
  }) async {
    await _activeCallDoc(callId).update({
      'status': CallSessionStatus.ended.value,
      'endedBy': endedBy,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writeHistoryIfNeeded(callId);
  }

  Future<void> _writeHistoryIfNeeded(String callId) async {
    final callDoc = _activeCallDoc(callId);

    await _firestore.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(callDoc);
      if (!activeSnapshot.exists) return;

      final data = activeSnapshot.data();
      if (data == null) return;

      final session = ActiveCallSession.fromFirestore(data, activeSnapshot.id);
      if (!session.isTerminal || session.historyWritten) return;

      final localStartedAt = _readTimestamp(data['clientStartedAt']);
      final localEndedAt = _readTimestamp(data['clientEndedAt']);

      final eventTime = localEndedAt ?? session.endedAt ?? DateTime.now();
      final duration = _durationSeconds(
        session,
        eventTime,
        localStartedAt: localStartedAt,
        localEndedAt: localEndedAt,
      );
      final calleeType = duration > 0 ? CallType.incoming : CallType.missed;

      final callerHistoryDoc = _userCallsCollection(
        session.callerId,
      ).doc(callId);
      final calleeHistoryDoc = _userCallsCollection(
        session.calleeId,
      ).doc(callId);

      transaction.set(
        callerHistoryDoc,
        _callHistoryPayload(
          contactName: session.calleeName,
          contactUserId: session.calleeId,
          contactAvatar: session.calleePhotoUrl,
          type: CallType.outgoing,
          timestamp: eventTime,
          duration: duration,
          localStartedAt: localStartedAt,
          localEndedAt: localEndedAt,
        ),
      );

      transaction.set(
        calleeHistoryDoc,
        _callHistoryPayload(
          contactName: session.callerName,
          contactUserId: session.callerId,
          contactAvatar: session.callerPhotoUrl,
          type: calleeType,
          timestamp: eventTime,
          duration: duration,
          localStartedAt: localStartedAt,
          localEndedAt: localEndedAt,
        ),
      );

      transaction.update(callDoc, {
        'historyWritten': true,
        'historyWrittenAt': FieldValue.serverTimestamp(),
      });
    });
  }

  DateTime? _readTimestamp(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  int _durationSeconds(
    ActiveCallSession session,
    DateTime eventTime, {
    DateTime? localStartedAt,
    DateTime? localEndedAt,
  }) {
    if (localStartedAt != null && localEndedAt != null) {
      final localDiff = localEndedAt.difference(localStartedAt).inSeconds;
      if (!localDiff.isNegative) {
        return localDiff;
      }
    }

    final startedAt = session.startedAt;
    if (startedAt == null) return 0;

    final diff = eventTime.difference(startedAt).inSeconds;
    if (diff.isNegative) return 0;
    return diff;
  }

  Map<String, dynamic> _callHistoryPayload({
    required String contactName,
    required String contactUserId,
    String? contactAvatar,
    required CallType type,
    required DateTime timestamp,
    required int duration,
    DateTime? localStartedAt,
    DateTime? localEndedAt,
  }) {
    return {
      'contactName': contactName,
      'contactUserId': contactUserId,
      'contactAvatar': contactAvatar,
      'type': type.index,
      'timestamp': Timestamp.fromDate(timestamp),
      'duration': duration,
      'localStartedAt': localStartedAt == null
          ? null
          : Timestamp.fromDate(localStartedAt),
      'localEndedAt': localEndedAt == null
          ? null
          : Timestamp.fromDate(localEndedAt),
    };
  }

  ActiveCallSession? _selectLatestIncomingRingingCall(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String userId,
  }) {
    if (docs.isEmpty) return null;

    final sessions =
        docs
            .map((doc) => ActiveCallSession.fromFirestore(doc.data(), doc.id))
            .where(
              (session) =>
                  session.calleeId == userId &&
                  session.status == CallSessionStatus.ringing,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (sessions.isEmpty) return null;
    return sessions.first;
  }
}
