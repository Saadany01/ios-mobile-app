import 'package:flutter/material.dart';

import '../../models/contact_model.dart';
import '../../services/contacts_service.dart';

class ContactsController extends ChangeNotifier {
  ContactsController({required ContactsService contactsService})
    : _contactsService = contactsService;

  final ContactsService _contactsService;

  final TextEditingController searchController = TextEditingController();

  String _searchQuery = '';

  String get searchQuery => _searchQuery;

  Stream<List<Contact>> contactsStream(String userId) {
    return _contactsService.watchContacts(userId);
  }

  Stream<int> contactCountStream(String userId) {
    return _contactsService.watchContactsCount(userId);
  }

  void updateSearchQuery(String value) {
    _searchQuery = value.trim().toLowerCase();
    notifyListeners();
  }

  void clearSearch() {
    searchController.clear();
    _searchQuery = '';
    notifyListeners();
  }

  List<Contact> filteredContacts(List<Contact> contacts) {
    final query = _searchQuery;
    if (query.isEmpty) return contacts;

    return contacts.where((contact) {
      return contact.name.toLowerCase().contains(query) ||
          (contact.phone?.toLowerCase().contains(query) ?? false) ||
          (contact.email?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<String?> addContact({
    required String userId,
    required String name,
    String? linkedUserId,
    String? phone,
    String? email,
  }) async {
    if (name.trim().isEmpty) {
      return 'Please enter a name';
    }

    final contact = Contact(
      id: '',
      name: name.trim(),
      linkedUserId: _nullIfEmpty(linkedUserId),
      phone: _nullIfEmpty(phone),
      email: _nullIfEmpty(email),
    );

    try {
      await _contactsService.addContact(userId, contact);
      return null;
    } catch (_) {
      return 'Failed to add contact. Please try again.';
    }
  }

  Future<String?> toggleFavorite(String userId, Contact contact) async {
    try {
      await _contactsService.setFavorite(
        userId: userId,
        contactId: contact.id,
        isFavorite: !contact.isFavorite,
      );
      return null;
    } catch (_) {
      return 'Failed to update favorite status.';
    }
  }

  Future<String?> deleteContact(String userId, String contactId) async {
    try {
      await _contactsService.deleteContact(
        userId: userId,
        contactId: contactId,
      );
      return null;
    } catch (_) {
      return 'Failed to delete contact.';
    }
  }

  String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
