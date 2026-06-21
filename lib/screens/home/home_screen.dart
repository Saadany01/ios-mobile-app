import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';

import '../../controllers/home/home_controller.dart';
import '../../models/call_model.dart';
import '../../models/chat_model.dart';
import '../../services/auth_service.dart';
import '../../services/calls_service.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/local_notifications_service.dart';
import '../chat/direct_messages_screen.dart';
import '../communication/communication_screen.dart';
import '../calls/call_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HomeController _controller;
  StreamSubscription<ActiveCallSession?>? _incomingCallSubscription;
  StreamSubscription<List<FriendshipPreview>>? _messageNotificationSubscription;
  StreamSubscription<List<FriendRequestItem>>? _friendRequestSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _notificationTapSubscription;
  Timer? _incomingCallPollTimer;
  Timer? _incomingMessageBannerTimer;
  OverlayEntry? _incomingMessageOverlay;
  String? _presentedIncomingCallId;
  String? _activeListenerUserId;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _seededMessageTimeline = false;
  final Map<String, DateTime> _lastSeenMessageAtByChat = <String, DateTime>{};
  final Map<String, String> _contactSyncSignatureByFriendId =
      <String, String>{};
  int _unreadChatCount = 0;
  int _pendingFriendRequestCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = HomeController();
    _bindNotificationTapListener();
    _requestNotificationPermission();
    _startRealtimeListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    _messageNotificationSubscription?.cancel();
    _friendRequestSubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _incomingCallPollTimer?.cancel();
    _incomingMessageBannerTimer?.cancel();
    _dismissIncomingMessageBanner();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  void _bindNotificationTapListener() {
    _notificationTapSubscription?.cancel();
    _notificationTapSubscription = LocalNotificationsService
        .instance
        .tapPayloadStream
        .listen(_handleNotificationTapPayload);

    final launchPayload = LocalNotificationsService.instance
        .consumeLaunchPayload();
    if (launchPayload == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleNotificationTapPayload(launchPayload);
    });
  }

  void _requestNotificationPermission() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        LocalNotificationsService.instance.ensureNotificationPermission(),
      );
    });
  }

  void _handleNotificationTapPayload(String payload) {
    if (!LocalNotificationsService.instance.isDirectMessagePayload(payload)) {
      return;
    }
    _controller.onTabTapped(1);
  }

  void _startRealtimeListeners() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final authService = context.read<AuthService>();
      _bindRealtimeListeners(authService.currentUser?.uid);

      _authSubscription?.cancel();
      _authSubscription = authService.authStateChanges().listen((user) {
        if (!mounted) return;
        _bindRealtimeListeners(user?.uid);
      });
    });
  }

  void _bindRealtimeListeners(String? userId) {
    if (_activeListenerUserId == userId) return;

    _activeListenerUserId = userId;
    _incomingCallSubscription?.cancel();
    _messageNotificationSubscription?.cancel();
    _friendRequestSubscription?.cancel();
    _incomingCallPollTimer?.cancel();
    _presentedIncomingCallId = null;
    _seededMessageTimeline = false;
    _lastSeenMessageAtByChat.clear();
    _contactSyncSignatureByFriendId.clear();
    if (mounted) {
      setState(() {
        _unreadChatCount = 0;
        _pendingFriendRequestCount = 0;
      });
    }
    if (userId == null) return;

    final callsService = context.read<CallsService>();
    _incomingCallSubscription = callsService
        .watchIncomingCall(userId)
        .listen(
          (session) {
            _presentIncomingCallIfNeeded(userId: userId, session: session);
          },
          onError: (_) {
            // Keep polling fallback active when stream query fails due transient issues.
          },
        );

    _startIncomingCallPolling(userId);

    final chatService = context.read<ChatService>();
    _messageNotificationSubscription = chatService
        .watchFriendships(userId)
        .listen((friendships) {
          _handleMessageNotifications(friendships, currentUserId: userId);
          _updateUnreadChatCount(friendships, currentUserId: userId);
          unawaited(
            _syncFriendshipsToContacts(friendships, currentUserId: userId),
          );
        });

    unawaited(_startFriendRequestListener(userId));
  }

  Future<void> _startFriendRequestListener(String userId) async {
    final chatService = context.read<ChatService>();
    try {
      final profile = await chatService.getRequiredUserProfileById(userId);
      if (!mounted || _activeListenerUserId != userId) return;

      _friendRequestSubscription?.cancel();
      _friendRequestSubscription = chatService
          .watchIncomingFriendRequests(profile.username.toLowerCase())
          .listen((requests) {
            if (!mounted) return;
            final nextCount = requests.length;
            if (_pendingFriendRequestCount == nextCount) return;
            setState(() {
              _pendingFriendRequestCount = nextCount;
            });
          });
    } catch (_) {
      // Ignore listener setup failures; UI can still function without badge.
    }
  }

  void _startIncomingCallPolling(String userId) {
    final callsService = context.read<CallsService>();
    _incomingCallPollTimer?.cancel();

    _incomingCallPollTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      if (!mounted || _activeListenerUserId != userId) return;

      try {
        final session = await callsService.getLatestIncomingRingingCall(userId);
        _presentIncomingCallIfNeeded(userId: userId, session: session);
      } catch (_) {
        // Ignore polling errors; stream listener remains the primary path.
      }
    });
  }

  void _presentIncomingCallIfNeeded({
    required String userId,
    required ActiveCallSession? session,
  }) {
    if (!mounted || session == null) return;
    if (session.calleeId != userId) return;
    if (_presentedIncomingCallId == session.id) return;

    _presentedIncomingCallId = session.id;
    unawaited(_openIncomingCall(session.id, session.mediaType));
  }

  void _handleMessageNotifications(
    List<FriendshipPreview> friendships, {
    required String currentUserId,
  }) {
    if (!_seededMessageTimeline) {
      for (final friendship in friendships) {
        _lastSeenMessageAtByChat[friendship.chatId] = friendship.lastMessageAt;
      }
      _seededMessageTimeline = true;
      return;
    }

    for (final friendship in friendships) {
      final previous = _lastSeenMessageAtByChat[friendship.chatId];
      final isNewMessage =
          previous == null || friendship.lastMessageAt.isAfter(previous);
      if (!isNewMessage) continue;

      _lastSeenMessageAtByChat[friendship.chatId] = friendship.lastMessageAt;

      final hasText = friendship.lastMessage.trim().isNotEmpty;
      final fromOtherUser = friendship.lastMessageSenderId != currentUserId;
      if (!hasText || !fromOtherUser) continue;

      final shouldShowInAppBanner =
          _appLifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? true);

      if (shouldShowInAppBanner) {
        _showIncomingMessageBanner(friendship);
      } else {
        unawaited(
          LocalNotificationsService.instance.showIncomingMessageNotification(
            chatId: friendship.chatId,
            senderName: friendship.friendDisplayName,
            messagePreview: friendship.lastMessage,
          ),
        );
      }
    }
  }

  void _updateUnreadChatCount(
    List<FriendshipPreview> friendships, {
    required String currentUserId,
  }) {
    final unread = friendships.where((friendship) {
      if (friendship.lastMessage.trim().isEmpty) return false;
      if (friendship.lastMessageSenderId == currentUserId) return false;
      return friendship.lastMessageAt.isAfter(friendship.currentUserLastSeenAt);
    }).length;

    if (_unreadChatCount == unread) return;
    if (!mounted) return;

    setState(() {
      _unreadChatCount = unread;
    });
  }

  Future<void> _syncFriendshipsToContacts(
    List<FriendshipPreview> friendships, {
    required String currentUserId,
  }) async {
    final contactsService = context.read<ContactsService>();

    for (final friendship in friendships) {
      final friendId = friendship.friendUserId.trim();
      if (friendId.isEmpty) continue;

      if (friendship.isRemovedForCurrentUser) {
        _contactSyncSignatureByFriendId.remove(friendId);
        try {
          await contactsService.deleteContactsByLinkedUserId(
            userId: currentUserId,
            linkedUserId: friendId,
          );
        } catch (_) {
          // Best effort sync; ignore failures.
        }
        continue;
      }

      final signature =
          '${friendship.friendDisplayName}|${friendship.friendPhotoUrl ?? ''}|${friendship.friendPresenceStatus}';
      final lastSignature = _contactSyncSignatureByFriendId[friendId];
      if (lastSignature == signature) continue;

      _contactSyncSignatureByFriendId[friendId] = signature;
      try {
        await contactsService.upsertContactByLinkedUserId(
          userId: currentUserId,
          linkedUserId: friendId,
          name: friendship.friendDisplayName,
          avatarUrl: friendship.friendPhotoUrl,
          isOnline: friendship.friendPresenceStatus == 'online',
        );
      } catch (_) {
        // Best effort sync; ignore failures.
      }
    }
  }

  void _showIncomingMessageBanner(FriendshipPreview friendship) {
    if (!mounted) return;

    _dismissIncomingMessageBanner();

    final overlay = Overlay.of(context, rootOverlay: true);

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final topOffset = MediaQuery.of(overlayContext).padding.top + 10;
        return Positioned(
          top: topOffset,
          left: 12,
          right: 12,
          child: _IncomingMessageBanner(
            friendship: friendship,
            onTap: () {
              _dismissIncomingMessageBanner();
              _controller.onTabTapped(1);
            },
          ),
        );
      },
    );

    overlay.insert(entry);
    _incomingMessageOverlay = entry;
    _incomingMessageBannerTimer = Timer(const Duration(seconds: 4), () {
      _dismissIncomingMessageBanner();
    });
  }

  void _dismissIncomingMessageBanner() {
    _incomingMessageBannerTimer?.cancel();
    _incomingMessageBannerTimer = null;
    _incomingMessageOverlay?.remove();
    _incomingMessageOverlay = null;
  }

  Future<void> _openIncomingCall(String callId, String mediaType) async {
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(callId: callId, isCaller: false, mediaType: mediaType),
      ),
    );

    if (!mounted) return;
    if (_presentedIncomingCallId == callId) {
      _presentedIncomingCallId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dmBadgeCount = _unreadChatCount + _pendingFriendRequestCount;
    return ChangeNotifierProvider<HomeController>.value(
      value: _controller,
      child: _HomeView(directMessagesBadgeCount: dmBadgeCount),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({required this.directMessagesBadgeCount});

  final int directMessagesBadgeCount;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();

    return Scaffold(
      body: PageView(
        controller: controller.pageController,
        onPageChanged: controller.onPageChanged,
        physics:
            const NeverScrollableScrollPhysics(), // Disable swipe to prevent accidental switches
        children: const [
          CommunicationScreen(),
          DirectMessagesScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: controller.currentIndex,
        onTap: controller.onTabTapped,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.forum_outlined),
            activeIcon: const Icon(Icons.forum),
            label: AppStrings.of(context).communication,
          ),
          BottomNavigationBarItem(
            icon: _BottomNavBadgeIcon(icon: Icons.message_outlined, count: directMessagesBadgeCount),
            activeIcon: _BottomNavBadgeIcon(icon: Icons.message, count: directMessagesBadgeCount),
            label: AppStrings.of(context).directMessages,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: AppStrings.of(context).settings,
          ),
        ],
      ),
    );
  }
}

class _BottomNavBadgeIcon extends StatelessWidget {
  const _BottomNavBadgeIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -10,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                count > 99 ? '99+' : '+$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IncomingMessageBanner extends StatelessWidget {
  const _IncomingMessageBanner({required this.friendship, required this.onTap});

  final FriendshipPreview friendship;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photoUrl = (friendship.friendPhotoUrl ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1F2C34),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF25D366),
                backgroundImage: photoUrl.isEmpty
                    ? null
                    : NetworkImage(photoUrl),
                child: photoUrl.isEmpty
                    ? Text(
                        _initials(friendship.friendDisplayName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      friendship.friendDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      friendship.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366)),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final safe = name.trim();
    if (safe.isEmpty) return 'U';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }
}
