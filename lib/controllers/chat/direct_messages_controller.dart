import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';

class DirectMessagesController extends ChangeNotifier {
  DirectMessagesController({
    required ChatService chatService,
    required AuthService authService,
  }) : _chatService = chatService,
       _authService = authService;

  final ChatService _chatService;
  final AuthService _authService;

  final TextEditingController addFriendController = TextEditingController();

  bool _isSendingRequest = false;
  bool _isHandlingRequest = false;

  bool get isSendingRequest => _isSendingRequest;
  bool get isHandlingRequest => _isHandlingRequest;

  User? get currentUser => _authService.currentUser;

  Stream<List<FriendshipPreview>> friendshipsStream(String userId) {
    return _chatService.watchFriendships(userId);
  }

  Stream<int> unreadCountStream(FriendshipPreview friendship) {
    final user = currentUser;
    if (user == null) return Stream<int>.value(0);

    final clearedAt = friendship.currentUserChatClearedAt;
    final since =
        clearedAt != null && clearedAt.isAfter(friendship.currentUserLastSeenAt)
        ? clearedAt
        : friendship.currentUserLastSeenAt;

    return _chatService.watchUnreadMessageCount(
      chatId: friendship.chatId,
      currentUserId: user.uid,
      since: since,
    );
  }

  Stream<List<FriendRequestItem>> incomingFriendRequestsStream(String userId) {
    return Stream.fromFuture(
      _chatService.getRequiredUserProfileById(userId),
    ).asyncExpand((profile) {
      return _chatService.watchIncomingFriendRequests(
        profile.username.toLowerCase(),
      );
    });
  }

  Future<String?> sendFriendRequest() async {
    final user = currentUser;
    if (user == null) {
      return 'Please log in first.';
    }

    final handle = addFriendController.text.trim();
    if (handle.isEmpty) {
      return 'Enter a username to add.';
    }

    _setSendingRequest(true);
    try {
      await _chatService.sendFriendRequest(
        fromUserId: user.uid,
        targetUsername: handle,
      );
      addFriendController.clear();
      return null;
    } on FirebaseException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No user found with that username.';
        case 'cannot-add-yourself':
          return 'You cannot add yourself.';
        case 'already-friends':
          return 'You are already friends with this user.';
        case 'request-already-sent':
          return 'Friend request already sent.';
        case 'incoming-request-exists':
          return 'This user already sent you a request. Accept it below.';
        case 'username-lookup-permission-denied':
          return 'Cannot find users by username with current Firestore rules. Allow read access for users.usernameLowercase lookup.';
        case 'permission-denied':
          return 'Request blocked by Firestore rules. Allow authenticated users to create friend_requests and read target users.';
        default:
          return e.message ?? 'Failed to send friend request.';
      }
    } catch (_) {
      return 'Failed to send friend request.';
    } finally {
      _setSendingRequest(false);
    }
  }

  Future<String?> acceptFriendRequest(String requestId) async {
    final user = currentUser;
    if (user == null) {
      return 'Please log in first.';
    }

    _setHandlingRequest(true);
    try {
      final currentProfile = await _chatService.getRequiredUserProfileById(
        user.uid,
      );
      await _chatService.acceptFriendRequest(
        currentUserId: user.uid,
        currentUsername: currentProfile.username,
        requestId: requestId,
      );
      return null;
    } on FirebaseException catch (e) {
      return e.message ?? 'Failed to accept friend request.';
    } catch (_) {
      return 'Failed to accept friend request.';
    } finally {
      _setHandlingRequest(false);
    }
  }

  Future<String?> declineFriendRequest(String requestId) async {
    final user = currentUser;
    if (user == null) {
      return 'Please log in first.';
    }

    _setHandlingRequest(true);
    try {
      final currentProfile = await _chatService.getRequiredUserProfileById(
        user.uid,
      );
      await _chatService.declineFriendRequest(
        currentUserId: user.uid,
        currentUsername: currentProfile.username,
        requestId: requestId,
      );
      return null;
    } on FirebaseException catch (e) {
      return e.message ?? 'Failed to decline friend request.';
    } catch (_) {
      return 'Failed to decline friend request.';
    } finally {
      _setHandlingRequest(false);
    }
  }

  String formatLastMessageTime(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(value);
    }

    if (diff.inDays == 1) {
      return 'Yesterday';
    }

    if (diff.inDays < 7) {
      return DateFormat('EEE').format(value);
    }

    return DateFormat('MMM d').format(value);
  }

  void _setSendingRequest(bool value) {
    if (_isSendingRequest == value) return;
    _isSendingRequest = value;
    notifyListeners();
  }

  void _setHandlingRequest(bool value) {
    if (_isHandlingRequest == value) return;
    _isHandlingRequest = value;
    notifyListeners();
  }

  @override
  void dispose() {
    addFriendController.dispose();
    super.dispose();
  }
}
