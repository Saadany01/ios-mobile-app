import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/contact_model.dart';

class ContactsService {
  ContactsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _contactsCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('contacts');
  }

  Stream<List<Contact>> watchContacts(String userId) {
    return _contactsCollection(userId).orderBy('name').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => Contact.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  Stream<int> watchContactsCount(String userId) {
    return _contactsCollection(
      userId,
    ).snapshots().map((snapshot) => snapshot.docs.length);
  }

  Future<void> addContact(String userId, Contact contact) {
    return _contactsCollection(userId).add(contact.toFirestore());
  }

  Future<void> upsertContactByLinkedUserId({
    required String userId,
    required String linkedUserId,
    required String name,
    String? avatarUrl,
    bool isOnline = false,
  }) async {
    final snapshot = await _contactsCollection(
      userId,
    ).where('linkedUserId', isEqualTo: linkedUserId).limit(1).get();

    final payload = <String, dynamic>{
      'name': name,
      'linkedUserId': linkedUserId,
      'avatarUrl': avatarUrl,
      'isOnline': isOnline,
    };

    if (snapshot.docs.isEmpty) {
      await _contactsCollection(userId).add(payload);
      return;
    }

    await snapshot.docs.first.reference.set(payload, SetOptions(merge: true));
  }

  Future<void> setFavorite({
    required String userId,
    required String contactId,
    required bool isFavorite,
  }) {
    return _contactsCollection(
      userId,
    ).doc(contactId).update({'isFavorite': isFavorite});
  }

  Future<void> deleteContact({
    required String userId,
    required String contactId,
  }) {
    return _contactsCollection(userId).doc(contactId).delete();
  }

  Future<void> deleteContactsByLinkedUserId({
    required String userId,
    required String linkedUserId,
  }) async {
    final normalized = linkedUserId.trim();
    if (normalized.isEmpty) return;

    final snapshot = await _contactsCollection(
      userId,
    ).where('linkedUserId', isEqualTo: normalized).get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
