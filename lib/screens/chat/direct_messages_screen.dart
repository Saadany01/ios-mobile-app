import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/chat/direct_messages_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../models/chat_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../shared/user_profile_avatar.dart';
import 'chat_conversation_screen.dart';
import 'friends_management_screen.dart';

class DirectMessagesScreen extends StatelessWidget {
  const DirectMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DirectMessagesController>(
      create: (context) => DirectMessagesController(
        chatService: context.read<ChatService>(),
        authService: context.read<AuthService>(),
      ),
      child: const _DirectMessagesView(),
    );
  }
}

class _DirectMessagesView extends StatelessWidget {
  const _DirectMessagesView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DirectMessagesController>();
    final authService = context.read<AuthService>();
    final user = controller.currentUser;

    final userName = (user?.displayName ?? '').trim();
    final userPhotoUrl = (user?.photoURL ?? '').trim();

    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.directMessages),
        actions: [
          if (user != null)
            _FriendsHubBadgeButton(
              requestsStream: controller.incomingFriendRequestsStream(user.uid),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: controller,
                      child: const FriendsManagementScreen(initialTab: 0),
                    ),
                  ),
                );
              },
            ),
          if (user != null)
            UserProfileAvatar(
              displayName: userName,
              photoUrlStream: authService.userPhotoUrlStream(user.uid),
              initialPhotoUrl: userPhotoUrl,
              showPresenceIndicator: true,
              presenceStatusStream: authService.userPresenceStatusStream(
                user.uid,
              ),
              initialPresenceStatus: 'online',
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: user == null
          ? Center(child: Text(s.pleaseLogIn))
          : StreamBuilder<List<FriendshipPreview>>(
              stream: controller.friendshipsStream(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final chats = snapshot.data ?? [];
                if (chats.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 76,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            s.noConversationsYet,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.addFriendsHint,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: chats.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return ListTile(
                      leading: _FriendAvatar(
                        displayName: chat.friendDisplayName,
                        photoUrl: chat.friendPhotoUrl,
                        presenceStatus: chat.friendPresenceStatus,
                      ),
                      title: Text(
                        chat.friendDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        chat.lastMessage.isEmpty
                            ? '@${chat.friendUsername}'
                            : chat.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _ChatItemMeta(
                        timeLabel: controller.formatLastMessageTime(
                          chat.lastMessageAt,
                        ),
                        unreadCountStream: controller.unreadCountStream(chat),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatConversationScreen(friendship: chat),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _FriendsHubBadgeButton extends StatelessWidget {
  const _FriendsHubBadgeButton({
    required this.requestsStream,
    required this.onTap,
  });

  final Stream<List<FriendRequestItem>> requestsStream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendRequestItem>>(
      stream: requestsStream,
      builder: (context, snapshot) {
        final count = (snapshot.data ?? []).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Friends',
              onPressed: onTap,
              icon: const Icon(Icons.group_add_outlined),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
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
      },
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({
    required this.displayName,
    required this.presenceStatus,
    this.photoUrl,
  });

  final String displayName;
  final String presenceStatus;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(displayName);
    final normalizedUrl = (photoUrl ?? '').trim();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          backgroundImage: normalizedUrl.isEmpty
              ? null
              : NetworkImage(normalizedUrl),
          child: normalizedUrl.isEmpty
              ? Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: _presenceColor(presenceStatus),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _initials(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return 'U';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }

  Color _presenceColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'idle':
        return Colors.orange;
      case 'dnd':
        return Colors.redAccent;
      case 'offline':
      default:
        return Colors.grey;
    }
  }
}

class _ChatItemMeta extends StatelessWidget {
  const _ChatItemMeta({
    required this.timeLabel,
    required this.unreadCountStream,
  });

  final String timeLabel;
  final Stream<int> unreadCountStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: unreadCountStream,
      builder: (context, snapshot) {
        final unread = (snapshot.data ?? 0).clamp(0, 999);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(timeLabel, style: Theme.of(context).textTheme.bodySmall),
            if (unread > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unread > 99 ? '99+' : unread.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
