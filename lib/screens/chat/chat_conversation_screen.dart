import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/chat/chat_conversation_controller.dart';
import '../../models/chat_model.dart';
import '../../services/auth_service.dart';
import '../../services/calls_service.dart';
import '../../services/chat_service.dart';
import '../calls/call_screen.dart';

class ChatConversationScreen extends StatelessWidget {
  const ChatConversationScreen({required this.friendship, super.key});

  final FriendshipPreview friendship;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatConversationController>(
      create: (context) => ChatConversationController(
        chatService: context.read<ChatService>(),
        authService: context.read<AuthService>(),
      ),
      child: _ChatConversationView(friendship: friendship),
    );
  }
}

class _ChatConversationView extends StatefulWidget {
  const _ChatConversationView({required this.friendship});

  final FriendshipPreview friendship;

  @override
  State<_ChatConversationView> createState() => _ChatConversationViewState();
}

class _ChatConversationViewState extends State<_ChatConversationView>
    with WidgetsBindingObserver {
  DateTime? _lastSeenMarkAt;
  final ScrollController _messagesScrollController = ScrollController();
  String? _lastNewestMessageId;
  bool _didInitialAutoScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markSeen();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      if (bottomInset > 100) {
        _scrollToBottom(force: true, animated: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatConversationController>();
    final user = controller.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF031A1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF042A2B),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showFriendProfileSheet(context),
          child: Row(
            children: [
              _Avatar(
                name: widget.friendship.friendDisplayName,
                photoUrl: widget.friendship.friendPhotoUrl,
                radius: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.friendship.friendDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${widget.friendship.friendUsername}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Audio Call',
            onPressed: user == null
                ? null
                : () => _startCall(context, 'audio'),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: 'Video Call',
            onPressed: user == null
                ? null
                : () => _startCall(context, 'video'),
            icon: const Icon(Icons.videocam_outlined),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please log in'))
          : Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF042A2B), Color(0xFF021318)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -80,
                  right: -40,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -90,
                  left: -50,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34B7F1).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<ChatMessage>>(
                        stream: controller.messagesStream(
                          widget.friendship.chatId,
                          since: widget.friendship.currentUserChatClearedAt,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final messages = snapshot.data ?? [];
                          _handleMessagesChanged(
                            messages,
                            currentUserId: user.uid,
                          );

                          if (messages.isEmpty) {
                            return Center(
                              child: Text(
                                'No messages yet. Say hi to ${widget.friendship.friendDisplayName}.',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            );
                          }

                          final maxBubbleWidth =
                              MediaQuery.of(context).size.width * 0.72;
                          return ListView.builder(
                            key: PageStorageKey<String>(
                              'chat_${widget.friendship.chatId}',
                            ),
                            controller: _messagesScrollController,
                            addAutomaticKeepAlives: false,
                            addRepaintBoundaries: true,
                            addSemanticIndexes: false,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              final isMine = message.senderId == user.uid;
                              final nextMessage = index + 1 < messages.length
                                  ? messages[index + 1]
                                  : null;
                              final showPeerAvatar =
                                  !isMine &&
                                  (nextMessage == null ||
                                      nextMessage.senderId != message.senderId);
                              final prevMessage =
                                  index > 0 ? messages[index - 1] : null;
                              final showDateSep = prevMessage == null ||
                                  !_isSameDay(
                                    prevMessage.createdAt,
                                    message.createdAt,
                                  );

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showDateSep)
                                    _DateSeparator(date: message.createdAt),
                                  Align(
                                    alignment: isMine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          if (!isMine)
                                            showPeerAvatar
                                                ? _Avatar(
                                                    name: message
                                                        .senderDisplayName,
                                                    photoUrl:
                                                        message.senderPhotoUrl,
                                                    radius: 14,
                                                    onTap: () =>
                                                        _showFriendProfileSheet(
                                                          context,
                                                        ),
                                                  )
                                                : const SizedBox(
                                                    width: 28,
                                                    height: 28,
                                                  ),
                                          if (!isMine)
                                            const SizedBox(width: 8),
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: maxBubbleWidth,
                                            ),
                                            child: _MessageBubble(
                                              message: message,
                                              isMine: isMine,
                                              friendLastSeenAt: widget
                                                  .friendship
                                                  .friendLastSeenAt,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0D2B33,
                            ).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 14,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller.messageController,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(context),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Colors.transparent,
                                    hintText: 'Write a message...',
                                    hintStyle: TextStyle(color: Colors.white60),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF25D366),
                                      Color(0xFF1DAE57),
                                    ],
                                  ),
                                ),
                                child: IconButton(
                                  onPressed: controller.isSending
                                      ? null
                                      : () => _send(context),
                                  icon: controller.isSending
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_rounded,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final controller = context.read<ChatConversationController>();
    final message = await controller.sendMessage(
      chatId: widget.friendship.chatId,
      friendship: widget.friendship,
    );

    if (!context.mounted) return;
    if (message == null) {
      _scrollToBottom(force: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _handleMessagesChanged(
    List<ChatMessage> messages, {
    required String currentUserId,
  }) {
    if (messages.isEmpty) return;

    final newestId = messages.last.id;
    final hasNewMessage = newestId != _lastNewestMessageId;
    final isInitialLayout = !_didInitialAutoScroll;
    final latestFromPeer = messages.last.senderId != currentUserId;

    if (!hasNewMessage && !isInitialLayout) return;

    final shouldAutoScroll = isInitialLayout || _isNearBottom();
    _lastNewestMessageId = newestId;
    if (isInitialLayout) {
      _didInitialAutoScroll = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (latestFromPeer) {
        _markSeen();
      }
      if (shouldAutoScroll) {
        _scrollToBottom(force: true, animated: !isInitialLayout);
      }
    });
  }

  bool _isNearBottom({double threshold = 140}) {
    if (!_messagesScrollController.hasClients) return true;

    final position = _messagesScrollController.position;
    final remaining = position.maxScrollExtent - position.pixels;
    return remaining <= threshold;
  }

  void _scrollToBottom({bool force = false, bool animated = true}) {
    if (!_messagesScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(force: force, animated: animated);
      });
      return;
    }

    if (!force && !_isNearBottom()) return;

    final target = _messagesScrollController.position.maxScrollExtent;
    if (animated) {
      _messagesScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _messagesScrollController.jumpTo(target);
  }

  Future<void> _startCall(BuildContext context, String mediaType) async {
    final authService = context.read<AuthService>();
    final callsService = context.read<CallsService>();
    final user = authService.currentUser;
    if (user == null) return;

    try {
      final callerName = (user.displayName ?? '').trim();
      final session = await callsService.startCall(
        callerId: user.uid,
        callerName: callerName.isEmpty ? 'Unknown' : callerName,
        callerPhotoUrl: user.photoURL,
        calleeId: widget.friendship.friendUserId,
        calleeName: widget.friendship.friendDisplayName,
        calleePhotoUrl: widget.friendship.friendPhotoUrl,
        mediaType: mediaType,
      );

      if (!context.mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(callId: session.id, isCaller: true, mediaType: mediaType),
        ),
      );
    } on FirebaseException catch (error) {
      if (!context.mounted) return;

      final message = (error.message ?? '').trim();
      final reason = message.isEmpty ? error.code : '${error.code}: $message';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Call failed ($reason)')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to start call.')));
    }
  }

  Future<void> _markSeen() async {
    final now = DateTime.now();
    if (_lastSeenMarkAt != null &&
        now.difference(_lastSeenMarkAt!) < const Duration(milliseconds: 1500)) {
      return;
    }

    _lastSeenMarkAt = now;
    final controller = context.read<ChatConversationController>();
    try {
      await controller.markConversationSeen(chatId: widget.friendship.chatId);
    } catch (_) {
      // Ignore seen-update failures and keep conversation usable.
    }
  }

  Future<void> _showFriendProfileSheet(BuildContext context) async {
    final presenceLabel = _presenceLabel(
      widget.friendship.friendPresenceStatus,
    );
    final presenceColor = _presenceColor(
      widget.friendship.friendPresenceStatus,
    );
    final isRemovedForCurrentUser = widget.friendship.isRemovedForCurrentUser;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Avatar(
                  name: widget.friendship.friendDisplayName,
                  photoUrl: widget.friendship.friendPhotoUrl,
                  radius: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.friendship.friendDisplayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '@${widget.friendship.friendUsername}',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: presenceColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: presenceColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        presenceLabel,
                        style: TextStyle(
                          color: presenceColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          if (isRemovedForCurrentUser) {
                            await _sendFriendRequestFromChat(context);
                          } else {
                            await _confirmAndRemoveFriend(context);
                          }
                        },
                        icon: Icon(
                          isRemovedForCurrentUser
                              ? Icons.person_add_alt_1_rounded
                              : Icons.person_remove_alt_1_rounded,
                        ),
                        label: Text(
                          isRemovedForCurrentUser
                              ? 'Add Friend'
                              : 'Remove Friend',
                        ),
                        style: FilledButton.styleFrom(
                          foregroundColor: isRemovedForCurrentUser
                              ? Colors.lightGreen
                              : Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _confirmAndDeleteChat(context);
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Delete Chat'),
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndRemoveFriend(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove friend?'),
          content: Text(
            'Remove ${widget.friendship.friendDisplayName} from your friends and contacts?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final user = authService.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    try {
      await chatService.removeFriendship(
        currentUserId: user.uid,
        friendUserId: widget.friendship.friendUserId,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.friendship.friendDisplayName} removed.'),
        ),
      );
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to remove friend.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to remove friend.')));
    }
  }

  Future<void> _sendFriendRequestFromChat(BuildContext context) async {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final user = authService.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    try {
      await chatService.sendFriendRequest(
        fromUserId: user.uid,
        targetUsername: widget.friendship.friendUsername,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Friend request sent to ${widget.friendship.friendDisplayName}.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!context.mounted) return;

      String message;
      switch (e.code) {
        case 'cannot-add-yourself':
          message = 'You cannot add yourself.';
          break;
        case 'invalid-username':
          message = 'Invalid username.';
          break;
        case 'permission-denied':
          message = 'Request blocked by Firestore rules.';
          break;
        default:
          message = e.message ?? 'Failed to send friend request.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send friend request.')),
      );
    }
  }

  Future<void> _confirmAndDeleteChat(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete chat?'),
          content: Text(
            'Delete this chat for you only? ${widget.friendship.friendDisplayName} will still keep their chat history until they delete it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final controller = context.read<ChatConversationController>();
    final message = await controller.deleteChatForCurrentUser(
      chatId: widget.friendship.chatId,
    );

    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chat deleted for you.')));
    Navigator.of(context).pop();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _presenceLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'online':
        return 'Online';
      case 'idle':
        return 'Idle';
      case 'dnd':
        return 'Do Not Disturb';
      case 'offline':
      default:
        return 'Offline';
    }
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.friendLastSeenAt,
  });

  final ChatMessage message;
  final bool isMine;
  final DateTime friendLastSeenAt;

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white;
    final timeColor = isMine ? Colors.white60 : const Color(0xFF8696A0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFF005C4B) : const Color(0xFF1F2C34),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('HH:mm').format(message.createdAt),
                style: TextStyle(fontSize: 11, color: timeColor),
              ),
              if (isMine) ...[
                const SizedBox(width: 4),
                _deliveryIcon(
                  isPending: message.isPendingWrite,
                  isSeenByFriend:
                      !message.isPendingWrite &&
                      !friendLastSeenAt.isBefore(message.createdAt),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _deliveryIcon({
    required bool isPending,
    required bool isSeenByFriend,
  }) {
    if (isPending) {
      return const Icon(Icons.done, size: 14, color: Colors.white70);
    }

    if (isSeenByFriend) {
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Colors.lightBlueAccent,
      );
    }

    return const Icon(Icons.done_all, size: 14, color: Colors.white70);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    this.photoUrl,
    this.radius = 16,
    this.onTap,
  });

  final String name;
  final String? photoUrl;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      backgroundImage: url.isEmpty ? null : NetworkImage(url),
      child: url.isEmpty
          ? Text(
              _initials(name),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
              ),
            )
          : null,
    );

    if (onTap == null) {
      return avatar;
    }

    return GestureDetector(onTap: onTap, child: avatar);
  }

  String _initials(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return 'U';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMMM d, y').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white12)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _label(),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Colors.white12)),
        ],
      ),
    );
  }
}
