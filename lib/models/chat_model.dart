import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserProfile {
  AppUserProfile({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.presenceStatus,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String username;
  final String presenceStatus;
  final String? photoUrl;

  factory AppUserProfile.fromFirestore(Map<String, dynamic> data, String uid) {
    final displayName = (data['displayName'] ?? '').toString().trim();
    final username = (data['username'] ?? '').toString().trim();
    final rawPresence = (data['presenceStatus'] ?? 'online').toString().trim();
    final photo = (data['photoURL'] ?? '').toString().trim();

    return AppUserProfile(
      uid: uid,
      displayName: displayName.isEmpty ? 'Unknown' : displayName,
      username: username.isEmpty ? 'unknown_user' : username,
      presenceStatus: _normalizePresenceStatus(rawPresence),
      photoUrl: photo.isEmpty ? null : photo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'username': username,
      'usernameLowercase': username.toLowerCase(),
      'presenceStatus': presenceStatus,
      'photoURL': photoUrl ?? '',
    };
  }

  static String _normalizePresenceStatus(String value) {
    final normalized = value.toLowerCase();
    switch (normalized) {
      case 'online':
      case 'idle':
      case 'dnd':
      case 'offline':
        return normalized;
      default:
        return 'online';
    }
  }
}

class FriendRequestItem {
  FriendRequestItem({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.fromDisplayName,
    required this.fromUsername,
    this.fromPhotoUrl,
    required this.createdAt,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String fromDisplayName;
  final String fromUsername;
  final String? fromPhotoUrl;
  final DateTime createdAt;

  factory FriendRequestItem.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    final rawCreatedAt = data['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.now();

    final photo = (data['fromPhotoUrl'] ?? '').toString().trim();

    return FriendRequestItem(
      id: id,
      fromUserId: (data['fromUserId'] ?? '').toString(),
      toUserId: (data['toUserId'] ?? '').toString(),
      fromDisplayName: (data['fromDisplayName'] ?? 'Unknown').toString(),
      fromUsername: (data['fromUsername'] ?? 'unknown_user').toString(),
      fromPhotoUrl: photo.isEmpty ? null : photo,
      createdAt: createdAt,
    );
  }
}

class FriendshipPreview {
  FriendshipPreview({
    required this.id,
    required this.chatId,
    required this.friendUserId,
    required this.friendDisplayName,
    required this.friendUsername,
    required this.friendPresenceStatus,
    this.friendPhotoUrl,
    required this.lastMessage,
    required this.lastMessageSenderId,
    required this.lastMessageAt,
    required this.currentUserLastSeenAt,
    required this.friendLastSeenAt,
    this.currentUserChatClearedAt,
    this.isRemovedForCurrentUser = false,
  });

  final String id;
  final String chatId;
  final String friendUserId;
  final String friendDisplayName;
  final String friendUsername;
  final String friendPresenceStatus;
  final String? friendPhotoUrl;
  final String lastMessage;
  final String lastMessageSenderId;
  final DateTime lastMessageAt;
  final DateTime currentUserLastSeenAt;
  final DateTime friendLastSeenAt;
  final DateTime? currentUserChatClearedAt;
  final bool isRemovedForCurrentUser;

  factory FriendshipPreview.fromFirestore(
    Map<String, dynamic> data,
    String id, {
    required String currentUserId,
  }) {
    final userAId = (data['userAId'] ?? '').toString();
    final userBId = (data['userBId'] ?? '').toString();
    final currentIsA = userAId == currentUserId;

    final friendId = currentIsA ? userBId : userAId;
    final friendDisplayName =
        (data[currentIsA ? 'userBDisplayName' : 'userADisplayName'] ?? '')
            .toString()
            .trim();
    final friendUsername =
        (data[currentIsA ? 'userBUsername' : 'userAUsername'] ?? '')
            .toString()
            .trim();
    final friendPhoto =
        (data[currentIsA ? 'userBPhotoUrl' : 'userAPhotoUrl'] ?? '')
            .toString()
            .trim();

    final rawLastMessageAt = data['lastMessageAt'];
    final rawCreatedAt = data['createdAt'];
    final fallbackTime = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.now();
    final rawCurrentUserLastSeenAt =
        data[currentIsA ? 'userALastSeenAt' : 'userBLastSeenAt'];
    final rawFriendLastSeenAt =
        data[currentIsA ? 'userBLastSeenAt' : 'userALastSeenAt'];
    final rawFriendPresenceStatus =
        (data[currentIsA ? 'userBStatus' : 'userAStatus'] ?? 'offline')
            .toString()
            .trim();
    final removedBy = ((data['removedByUserIds'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .toSet();
    final isRemovedForCurrentUser = removedBy.contains(currentUserId);
    final clearedAtBy =
        (data['clearedAtBy'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        const <String, dynamic>{};
    final rawCurrentUserClearedAt = clearedAtBy[currentUserId];
    final rawCurrentUserSlotClearedAt =
        data[currentIsA ? 'userAClearedAt' : 'userBClearedAt'];

    DateTime? parsedClearedAt;
    if (rawCurrentUserClearedAt is Timestamp) {
      parsedClearedAt = rawCurrentUserClearedAt.toDate();
    } else if (rawCurrentUserSlotClearedAt is Timestamp) {
      parsedClearedAt = rawCurrentUserSlotClearedAt.toDate();
    }

    return FriendshipPreview(
      id: id,
      chatId: (data['chatId'] ?? id).toString(),
      friendUserId: friendId,
      friendDisplayName: friendDisplayName.isEmpty
          ? 'Unknown'
          : friendDisplayName,
      friendUsername: friendUsername.isEmpty ? 'unknown_user' : friendUsername,
      friendPresenceStatus: AppUserProfile._normalizePresenceStatus(
        rawFriendPresenceStatus,
      ),
      friendPhotoUrl: friendPhoto.isEmpty ? null : friendPhoto,
      lastMessage: (data['lastMessage'] ?? '').toString(),
      lastMessageSenderId: (data['lastMessageSenderId'] ?? '').toString(),
      lastMessageAt: rawLastMessageAt is Timestamp
          ? rawLastMessageAt.toDate()
          : fallbackTime,
      currentUserLastSeenAt: rawCurrentUserLastSeenAt is Timestamp
          ? rawCurrentUserLastSeenAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      friendLastSeenAt: rawFriendLastSeenAt is Timestamp
          ? rawFriendLastSeenAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      currentUserChatClearedAt: parsedClearedAt,
      isRemovedForCurrentUser: isRemovedForCurrentUser,
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderDisplayName,
    required this.senderUsername,
    this.senderPhotoUrl,
    required this.text,
    required this.createdAt,
    this.readByUserIds = const <String>[],
    this.isPendingWrite = false,
  });

  final String id;
  final String senderId;
  final String senderDisplayName;
  final String senderUsername;
  final String? senderPhotoUrl;
  final String text;
  final DateTime createdAt;
  final List<String> readByUserIds;
  final bool isPendingWrite;

  factory ChatMessage.fromFirestore(
    Map<String, dynamic> data,
    String id, {
    bool isPendingWrite = false,
  }) {
    final rawCreatedAt = data['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.now();

    final senderPhoto = (data['senderPhotoUrl'] ?? '').toString().trim();
    final rawReadBy = data['readByUserIds'];
    final readBy = rawReadBy is List
        ? rawReadBy.map((item) => item.toString()).toList()
        : <String>[];

    return ChatMessage(
      id: id,
      senderId: (data['senderId'] ?? '').toString(),
      senderDisplayName: (data['senderDisplayName'] ?? 'Unknown').toString(),
      senderUsername: (data['senderUsername'] ?? 'unknown_user').toString(),
      senderPhotoUrl: senderPhoto.isEmpty ? null : senderPhoto,
      text: (data['text'] ?? '').toString(),
      createdAt: createdAt,
      readByUserIds: readBy,
      isPendingWrite: isPendingWrite,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderDisplayName': senderDisplayName,
      'senderUsername': senderUsername,
      'senderPhotoUrl': senderPhotoUrl ?? '',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'readByUserIds': readByUserIds,
      'type': 'text',
    };
  }
}
