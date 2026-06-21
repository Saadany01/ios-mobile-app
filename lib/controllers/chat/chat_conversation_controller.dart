import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/chat_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';

class ChatConversationController extends ChangeNotifier {
  ChatConversationController({
    required ChatService chatService,
    required AuthService authService,
  }) : _chatService = chatService,
       _authService = authService;

  final ChatService _chatService;
  final AuthService _authService;

  final TextEditingController messageController = TextEditingController();

  bool _isSending = false;

  bool get isSending => _isSending;

  User? get currentUser => _authService.currentUser;

  Stream<List<ChatMessage>> messagesStream(String chatId, {DateTime? since}) {
    return _chatService.watchChatMessages(chatId, since: since);
  }

  Future<void> markConversationSeen({required String chatId}) async {
    final user = currentUser;
    if (user == null) return;

    await _chatService.markChatAsSeen(chatId: chatId, viewerUserId: user.uid);
  }

  Future<String?> deleteChatForCurrentUser({required String chatId}) async {
    final user = currentUser;
    if (user == null) {
      return 'Please log in first.';
    }

    try {
      await _chatService.clearChatForUser(
        chatId: chatId,
        currentUserId: user.uid,
      );
      return null;
    } on FirebaseException catch (e) {
      return e.message ?? 'Failed to delete chat.';
    } catch (_) {
      return 'Failed to delete chat.';
    }
  }

  Future<String?> sendMessage({
    required String chatId,
    required FriendshipPreview friendship,
  }) async {
    final user = currentUser;
    if (user == null) {
      return 'Please log in first.';
    }

    final text = messageController.text.trim();
    if (text.isEmpty) {
      return null;
    }

    _setSending(true);
    try {
      final senderProfile = await _chatService.getRequiredUserProfileById(
        user.uid,
      );
      await _chatService.sendMessage(
        chatId: chatId,
        sender: senderProfile,
        text: text,
      );
      messageController.clear();
      return null;
    } on FirebaseException catch (e) {
      return e.message ?? 'Failed to send message.';
    } catch (_) {
      return 'Failed to send message.';
    } finally {
      _setSending(false);
    }
  }

  void _setSending(bool value) {
    if (_isSending == value) return;
    _isSending = value;
    notifyListeners();
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }
}
