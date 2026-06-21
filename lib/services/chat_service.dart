import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_model.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _usersCollection() {
    return _firestore.collection('users');
  }

  CollectionReference<Map<String, dynamic>> _friendRequestsCollection() {
    return _firestore.collection('friend_requests');
  }

  CollectionReference<Map<String, dynamic>> _friendshipsCollection() {
    return _firestore.collection('friendships');
  }

  CollectionReference<Map<String, dynamic>> _directChatsCollection() {
    return _firestore.collection('direct_chats');
  }

  DocumentReference<Map<String, dynamic>> _chatDoc(String chatId) {
    return _directChatsCollection().doc(chatId);
  }

  CollectionReference<Map<String, dynamic>> _chatMessagesCollection(
    String chatId,
  ) {
    return _chatDoc(chatId).collection('messages');
  }

  CollectionReference<Map<String, dynamic>> _contactsCollection(String userId) {
    return _usersCollection().doc(userId).collection('contacts');
  }

  DocumentReference<Map<String, dynamic>> _friendshipDoc(String chatId) {
    return _friendshipsCollection().doc(chatId);
  }

  Future<AppUserProfile?> findUserByUsername(String username) async {
    final normalized = _normalizeUsernameForLookup(username);
    if (normalized.isEmpty) return null;

    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _usersCollection()
          .where('usernameLowercase', isEqualTo: normalized)
          .limit(1)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'username-lookup-permission-denied',
          message:
              'Current Firestore rules do not allow searching users by username.',
        );
      }
      rethrow;
    }

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return AppUserProfile.fromFirestore(doc.data(), doc.id);
  }

  Future<AppUserProfile?> getUserProfileById(String userId) async {
    final snapshot = await _usersCollection().doc(userId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return AppUserProfile.fromFirestore(data, snapshot.id);
  }

  Future<AppUserProfile> getRequiredUserProfileById(String userId) async {
    final profile = await getUserProfileById(userId);
    if (profile != null) return profile;

    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'user-not-found',
      message: 'User profile was not found.',
    );
  }

  Future<void> sendFriendRequest({
    required String fromUserId,
    required String targetUsername,
  }) async {
    final fromProfile = await getRequiredUserProfileById(fromUserId);
    final normalizedTargetUsername = _normalizeUsernameForLookup(
      targetUsername,
    );
    if (normalizedTargetUsername.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-username',
        message: 'Please enter a valid username.',
      );
    }

    if (normalizedTargetUsername == fromProfile.username.toLowerCase()) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'cannot-add-yourself',
        message: 'You cannot add yourself.',
      );
    }

    AppUserProfile? targetProfile;
    try {
      targetProfile = await findUserByUsername(normalizedTargetUsername);
    } on FirebaseException catch (e) {
      if (e.code != 'username-lookup-permission-denied') {
        rethrow;
      }
      targetProfile = null;
    }

    if (targetProfile != null && targetProfile.uid == fromUserId) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'cannot-add-yourself',
        message: 'You cannot add yourself.',
      );
    }

    final forwardRequestId = _friendRequestIdByUsername(
      fromUserId,
      normalizedTargetUsername,
    );

    await _friendRequestsCollection().doc(forwardRequestId).set({
      'id': forwardRequestId,
      'fromUserId': fromProfile.uid,
      'fromDisplayName': fromProfile.displayName,
      'fromUsername': fromProfile.username,
      'fromPresenceStatus': fromProfile.presenceStatus,
      'fromPhotoUrl': fromProfile.photoUrl ?? '',
      'toUserId': targetProfile?.uid ?? '',
      'toDisplayName': targetProfile?.displayName ?? '',
      'toUsername': targetProfile?.username ?? normalizedTargetUsername,
      'toPresenceStatus': targetProfile?.presenceStatus ?? 'offline',
      'toUsernameLowercase': normalizedTargetUsername,
      'toPhotoUrl': targetProfile?.photoUrl ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<FriendRequestItem>> watchIncomingFriendRequests(
    String usernameLowercase,
  ) {
    final normalized = _normalizeUsernameForLookup(usernameLowercase);
    if (normalized.isEmpty) {
      return Stream<List<FriendRequestItem>>.value(const []);
    }

    return _friendRequestsCollection()
        .where('toUsernameLowercase', isEqualTo: normalized)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => FriendRequestItem.fromFirestore(doc.data(), doc.id))
              .toList();
          items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return items;
        });
  }

  Future<void> acceptFriendRequest({
    required String currentUserId,
    required String currentUsername,
    required String requestId,
  }) async {
    final requestDoc = _friendRequestsCollection().doc(requestId);
    final normalizedCurrentUsername = _normalizeUsernameForLookup(
      currentUsername,
    );

    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestDoc);
      final requestData = requestSnapshot.data();

      if (!requestSnapshot.exists || requestData == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'request-not-found',
          message: 'Friend request no longer exists.',
        );
      }

      final toUserId = (requestData['toUserId'] ?? '').toString();
      final toUsernameLowercase = _normalizeUsernameForLookup(
        (requestData['toUsernameLowercase'] ?? requestData['toUsername'] ?? '')
            .toString(),
      );
      final fromUserId = (requestData['fromUserId'] ?? '').toString();
      final status = (requestData['status'] ?? '').toString();

      final isRecipient =
          toUserId == currentUserId ||
          (toUsernameLowercase.isNotEmpty &&
              toUsernameLowercase == normalizedCurrentUsername);

      if (!isRecipient || status != 'pending') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'invalid-request',
          message: 'This friend request can no longer be accepted.',
        );
      }

      final currentUserDoc = _usersCollection().doc(currentUserId);

      final currentUserSnapshot = await transaction.get(currentUserDoc);
      final currentUserData = currentUserSnapshot.data();

      if (!currentUserSnapshot.exists || currentUserData == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'user-not-found',
          message: 'Your user profile was not found.',
        );
      }

      final currentProfile = AppUserProfile.fromFirestore(
        currentUserData,
        currentUserSnapshot.id,
      );
      final senderPhoto = (requestData['fromPhotoUrl'] ?? '').toString().trim();
      final fromProfile = AppUserProfile(
        uid: fromUserId,
        displayName: (requestData['fromDisplayName'] ?? 'Unknown').toString(),
        username: (requestData['fromUsername'] ?? 'unknown_user').toString(),
        presenceStatus: (requestData['fromPresenceStatus'] ?? 'online')
            .toString(),
        photoUrl: senderPhoto.isEmpty ? null : senderPhoto,
      );

      final chatId = _chatId(fromUserId, currentUserId);
      final friendshipId = _friendshipId(fromUserId, currentUserId);
      final userAId = _sortedUserIds(fromUserId, currentUserId)[0];
      final userBId = _sortedUserIds(fromUserId, currentUserId)[1];
      final userA = userAId == fromProfile.uid ? fromProfile : currentProfile;
      final userB = userBId == fromProfile.uid ? fromProfile : currentProfile;

      transaction.set(_chatDoc(chatId), {
        'chatId': chatId,
        'memberIds': [userA.uid, userB.uid],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageSenderId': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(_friendshipsCollection().doc(friendshipId), {
        'id': friendshipId,
        'chatId': chatId,
        'memberIds': [userA.uid, userB.uid],
        'removedByUserIds': <String>[],
        'hiddenForUserIds': <String>[],
        'clearedAtBy': <String, dynamic>{},
        'userAId': userA.uid,
        'userADisplayName': userA.displayName,
        'userAUsername': userA.username,
        'userAPhotoUrl': userA.photoUrl ?? '',
        'userAStatus': userA.presenceStatus,
        'userBId': userB.uid,
        'userBDisplayName': userB.displayName,
        'userBUsername': userB.username,
        'userBPhotoUrl': userB.photoUrl ?? '',
        'userBStatus': userB.presenceStatus,
        'userAClearedAt': null,
        'userBClearedAt': null,
        'userALastSeenAt': FieldValue.serverTimestamp(),
        'userBLastSeenAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageSenderId': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.delete(requestDoc);
    });
  }

  Future<void> declineFriendRequest({
    required String currentUserId,
    required String currentUsername,
    required String requestId,
  }) async {
    final requestDoc = _friendRequestsCollection().doc(requestId);
    final snapshot = await requestDoc.get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'request-not-found',
        message: 'Friend request no longer exists.',
      );
    }

    final toUserId = (data['toUserId'] ?? '').toString();
    final toUsernameLowercase = _normalizeUsernameForLookup(
      (data['toUsernameLowercase'] ?? data['toUsername'] ?? '').toString(),
    );
    final normalizedCurrentUsername = _normalizeUsernameForLookup(
      currentUsername,
    );

    final isRecipient =
        toUserId == currentUserId ||
        (toUsernameLowercase.isNotEmpty &&
            toUsernameLowercase == normalizedCurrentUsername);

    if (!isRecipient) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-request',
        message: 'You cannot modify this friend request.',
      );
    }

    await requestDoc.delete();
  }

  Stream<List<FriendshipPreview>> watchFriendships(String userId) {
    return _friendshipsCollection()
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final visibleDocs = snapshot.docs.where((doc) {
            final data = doc.data();
            final hiddenFor =
                ((data['hiddenForUserIds'] as List?) ?? const <dynamic>[])
                    .map((item) => item.toString())
                    .toSet();
            if (hiddenFor.contains(userId)) return false;

            return true;
          });

          final items = visibleDocs
              .map(
                (doc) => FriendshipPreview.fromFirestore(
                  doc.data(),
                  doc.id,
                  currentUserId: userId,
                ),
              )
              .toList();

          items.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
          return items;
        });
  }

  Stream<List<ChatMessage>> watchChatMessages(
    String chatId, {
    DateTime? since,
  }) {
    Query<Map<String, dynamic>> query = _chatMessagesCollection(chatId);

    if (since != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(since),
      );
    }

    return query.orderBy('createdAt').snapshots().map((snapshot) {
      return snapshot.docs
          .map(
            (doc) => ChatMessage.fromFirestore(
              doc.data(),
              doc.id,
              isPendingWrite: doc.metadata.hasPendingWrites,
            ),
          )
          .toList();
    });
  }

  Stream<int> watchUnreadMessageCount({
    required String chatId,
    required String currentUserId,
    required DateTime since,
  }) {
    return _chatMessagesCollection(chatId)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .snapshots()
        .map((snapshot) {
          var unreadCount = 0;
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final senderId = (data['senderId'] ?? '').toString();
            final text = (data['text'] ?? '').toString().trim();
            if (senderId == currentUserId || text.isEmpty) continue;
            unreadCount++;
          }
          return unreadCount;
        });
  }

  Future<void> sendMessage({
    required String chatId,
    required AppUserProfile sender,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    final messageRef = _chatMessagesCollection(chatId).doc();
    final friendshipDoc = _friendshipDoc(chatId);

    final friendshipSnapshot = await friendshipDoc.get();
    final friendshipData =
        friendshipSnapshot.data() ?? const <String, dynamic>{};
    final userAId = (friendshipData['userAId'] ?? '').toString();
    final userBId = (friendshipData['userBId'] ?? '').toString();
    String? senderSeenField;
    if (sender.uid == userAId) {
      senderSeenField = 'userALastSeenAt';
    } else if (sender.uid == userBId) {
      senderSeenField = 'userBLastSeenAt';
    }

    final batch = _firestore.batch();

    batch.set(
      messageRef,
      ChatMessage(
        id: messageRef.id,
        senderId: sender.uid,
        senderDisplayName: sender.displayName,
        senderUsername: sender.username,
        senderPhotoUrl: sender.photoUrl,
        text: normalized,
        createdAt: DateTime.now(),
        readByUserIds: <String>[sender.uid],
      ).toFirestore(),
    );

    batch.set(_chatDoc(chatId), {
      'lastMessage': normalized,
      'lastMessageSenderId': sender.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(friendshipDoc, {
      'lastMessage': normalized,
      'lastMessageSenderId': sender.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'hiddenForUserIds': <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (senderSeenField != null) {
      batch.set(friendshipDoc, {
        senderSeenField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> markChatAsSeen({
    required String chatId,
    required String viewerUserId,
  }) async {
    final friendshipDoc = _friendshipDoc(chatId);
    final snapshot = await friendshipDoc.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return;

    final userAId = (data['userAId'] ?? '').toString();
    final userBId = (data['userBId'] ?? '').toString();

    if (viewerUserId == userAId) {
      await friendshipDoc.set({
        'userALastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (viewerUserId == userBId) {
      await friendshipDoc.set({
        'userBLastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> clearChatForUser({
    required String chatId,
    required String currentUserId,
  }) async {
    final friendshipDoc = _friendshipDoc(chatId);
    final snapshot = await friendshipDoc.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return;

    final members = ((data['memberIds'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .toSet();

    if (!members.contains(currentUserId)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-chat',
        message: 'You cannot modify this chat.',
      );
    }

    final userAId = (data['userAId'] ?? '').toString();
    final userBId = (data['userBId'] ?? '').toString();
    final clearField = currentUserId == userAId
        ? 'userAClearedAt'
        : currentUserId == userBId
        ? 'userBClearedAt'
        : null;

    final updates = <String, dynamic>{
      'clearedAtBy.$currentUserId': FieldValue.serverTimestamp(),
      'hiddenForUserIds': FieldValue.arrayUnion(<String>[currentUserId]),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (clearField != null) {
      updates[clearField] = FieldValue.serverTimestamp();
    }

    try {
      await friendshipDoc.set(updates, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message:
              'Permission denied. Firestore rules must allow chat members to update friendships.',
        );
      }
      rethrow;
    }
  }

  Future<void> updatePresenceStatusInFriendships({
    required String currentUserId,
    required String status,
  }) async {
    final normalizedStatus = _normalizePresenceStatus(status);
    final snapshot = await _friendshipsCollection()
        .where('memberIds', arrayContains: currentUserId)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userAId = (data['userAId'] ?? '').toString();
      final userBId = (data['userBId'] ?? '').toString();

      if (currentUserId == userAId) {
        batch.set(doc.reference, {
          'userAStatus': normalizedStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (currentUserId == userBId) {
        batch.set(doc.reference, {
          'userBStatus': normalizedStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  Future<void> removeFriendship({
    required String currentUserId,
    required String friendUserId,
  }) async {
    final current = currentUserId.trim();
    final friend = friendUserId.trim();

    if (current.isEmpty || friend.isEmpty || current == friend) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-friendship',
        message: 'Invalid friend selection.',
      );
    }

    final friendshipId = _friendshipId(current, friend);
    final friendshipDoc = _friendshipsCollection().doc(friendshipId);
    final snapshot = await friendshipDoc.get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return;
    }

    final members = ((data['memberIds'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .toSet();

    if (!members.contains(current) || !members.contains(friend)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-friendship',
        message: 'This friendship can no longer be removed.',
      );
    }

    try {
      await friendshipDoc.set({
        'removedByUserIds': FieldValue.arrayUnion([current, friend]),
        'removedBy': current,
        'removedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _deleteContactsByLinkedUserId(
        userId: current,
        linkedUserId: friend,
      );

      try {
        await _deleteContactsByLinkedUserId(
          userId: friend,
          linkedUserId: current,
        );
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
        // Best effort for the remote side. Their app sync can still remove it.
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message:
              'You do not have permission to remove this friend. Firestore rules must allow friendship members to update friendships.',
        );
      }
      rethrow;
    }
  }

  Future<void> _deleteContactsByLinkedUserId({
    required String userId,
    required String linkedUserId,
  }) async {
    final snapshot = await _contactsCollection(
      userId,
    ).where('linkedUserId', isEqualTo: linkedUserId).get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  List<String> _sortedUserIds(String userIdA, String userIdB) {
    final ids = [userIdA, userIdB]..sort();
    return ids;
  }

  String _friendRequestId(String fromUserId, String toUserId) {
    return '${fromUserId}_$toUserId';
  }

  String _friendRequestIdByUsername(
    String fromUserId,
    String toUsernameLowercase,
  ) {
    final normalized = _normalizeUsernameForLookup(toUsernameLowercase);
    return _friendRequestId(fromUserId, normalized);
  }

  String _friendshipId(String userIdA, String userIdB) {
    final sorted = _sortedUserIds(userIdA, userIdB);
    return '${sorted[0]}_${sorted[1]}';
  }

  String _chatId(String userIdA, String userIdB) {
    final sorted = _sortedUserIds(userIdA, userIdB);
    return '${sorted[0]}_${sorted[1]}';
  }

  String _normalizeUsernameForLookup(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('@')) {
      value = value.substring(1);
    }
    return value;
  }

  String _normalizePresenceStatus(String value) {
    final normalized = value.trim().toLowerCase();
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
