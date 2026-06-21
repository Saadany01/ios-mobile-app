import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../controllers/contacts/contacts_controller.dart';
import '../../models/contact_model.dart';
import '../../services/auth_service.dart';
import '../../services/calls_service.dart';
import '../../services/contacts_service.dart';
import '../calls/call_screen.dart';
import '../shared/user_profile_avatar.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ContactsController>(
      create: (context) =>
          ContactsController(contactsService: context.read<ContactsService>()),
      child: _ContactsView(embedded: embedded),
    );
  }
}

class _ContactsView extends StatelessWidget {
  const _ContactsView({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ContactsController>();
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    final userName = (user?.displayName ?? '').trim();
    final userPhotoUrl = (user?.photoURL ?? '').trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final body = _buildBody(context, controller, user?.uid);

    if (embedded) {
      return Column(
        children: [
          _buildEmbeddedHeader(
            context,
            controller,
            userId: user?.uid,
            isDark: isDark,
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contacts'),
            StreamBuilder<int>(
              stream: user == null
                  ? Stream<int>.value(0)
                  : controller.contactCountStream(user.uid),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Text(
                  '$count contacts',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () {
              _showAddContactDialog(context, controller);
            },
          ),
          if (user != null)
            UserProfileAvatar(
              displayName: userName,
              photoUrlStream: authService.userPhotoUrlStream(user.uid),
              initialPhotoUrl: userPhotoUrl,
            )
          else
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Text(
                'JD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: body,
    );
  }

  Widget _buildEmbeddedHeader(
    BuildContext context,
    ContactsController controller, {
    required String? userId,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<int>(
              stream: userId == null
                  ? Stream<int>.value(0)
                  : controller.contactCountStream(userId),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Text(
                  '$count contacts',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ContactsController controller,
    String? userId,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controller.searchController,
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: controller.clearSearch,
                    )
                  : null,
            ),
            onChanged: controller.updateSearchQuery,
          ),
        ),
        Expanded(child: _buildContactsList(context, controller, userId)),
      ],
    );
  }

  Widget _buildContactsList(
    BuildContext context,
    ContactsController controller,
    String? userId,
  ) {
    if (userId == null) {
      return const Center(child: Text('Please log in'));
    }

    return StreamBuilder<List<Contact>>(
      stream: controller.contactsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allContacts = snapshot.data ?? [];

        if (allContacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No contacts yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                if (!embedded)
                  TextButton.icon(
                    onPressed: () => _showAddContactDialog(context, controller),
                    icon: const Icon(Icons.add),
                    label: const Text('Add your first contact'),
                  )
                else
                  Text(
                    'Contacts are synced automatically from your accepted friends.',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          );
        }

        final contacts = controller.filteredContacts(allContacts);

        if (contacts.isEmpty) {
          return Center(
            child: Text(
              'No contacts match your search',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          );
        }

        // Separate favorites
        final favorites = contacts.where((c) => c.isFavorite).toList();
        final regular = contacts.where((c) => !c.isFavorite).toList();

        return ListView(
          children: [
            if (favorites.isNotEmpty) ...[
              ...favorites.map(
                (contact) =>
                    _buildContactTile(context, controller, contact, userId),
              ),
              if (regular.isNotEmpty) const Divider(height: 1),
            ],
            ...regular.map(
              (contact) =>
                  _buildContactTile(context, controller, contact, userId),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContactTile(
    BuildContext context,
    ContactsController controller,
    Contact contact,
    String userId,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[300],
            backgroundImage: contact.avatarUrl != null
                ? NetworkImage(contact.avatarUrl!)
                : null,
            child: contact.avatarUrl == null
                ? Text(
                    _initial(contact.name),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          if (contact.isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(
            contact.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          if (contact.isFavorite) ...[
            const SizedBox(width: 8),
            const Icon(Icons.star, size: 16, color: Colors.amber),
          ],
        ],
      ),
      subtitle: contact.phone != null
          ? Text(
              contact.phone!,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            )
          : null,
      trailing: IconButton(
        icon: Icon(
          Icons.call,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
        onPressed: () {
          _startCall(context, contact, 'audio');
        },
      ),
      onTap: () {
        _showContactDetails(context, controller, contact, userId);
      },
    );
  }

  void _showAddContactDialog(
    BuildContext context,
    ContactsController controller,
  ) {
    final nameController = TextEditingController();
    final linkedUserIdController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: linkedUserIdController,
                decoration: const InputDecoration(
                  labelText: 'App User UID (for audio calls)',
                  prefixIcon: Icon(Icons.perm_identity_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              final message = await controller.addContact(
                userId: user.uid,
                name: nameController.text,
                linkedUserId: linkedUserIdController.text,
                phone: phoneController.text,
                email: emailController.text,
              );

              if (!dialogContext.mounted) return;

              if (message != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
                return;
              }

              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Contact added successfully')),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showContactDetails(
    BuildContext context,
    ContactsController controller,
    Contact contact,
    String userId,
  ) {
    final parentContext = context;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[300],
              child: Text(
                _initial(contact.name),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              contact.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (contact.phone != null) ...[
              const SizedBox(height: 8),
              Text(
                contact.phone!,
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.call, size: 32),
                      color: Theme.of(sheetContext).colorScheme.primary,
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _startCall(parentContext, contact, 'audio');
                      },
                    ),
                    const Text('Audio Call'),
                  ],
                ),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.videocam, size: 32),
                      color: Theme.of(sheetContext).colorScheme.primary,
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _startCall(parentContext, contact, 'video');
                      },
                    ),
                    const Text('Video Call'),
                  ],
                ),
                Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        contact.isFavorite ? Icons.star : Icons.star_outline,
                        size: 32,
                      ),
                      color: contact.isFavorite ? Colors.amber : Colors.grey,
                      onPressed: () async {
                        final message = await controller.toggleFavorite(
                          userId,
                          contact,
                        );

                        if (!sheetContext.mounted) return;

                        Navigator.pop(sheetContext);
                        if (message != null) {
                          ScaffoldMessenger.of(
                            parentContext,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      },
                    ),
                    const Text('Favorite'),
                  ],
                ),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 32),
                      color: Colors.red,
                      onPressed: () async {
                        final message = await controller.deleteContact(
                          userId,
                          contact.id,
                        );

                        if (!sheetContext.mounted) return;

                        Navigator.pop(sheetContext);
                        if (message != null) {
                          ScaffoldMessenger.of(
                            parentContext,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        } else {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            const SnackBar(content: Text('Contact deleted')),
                          );
                        }
                      },
                    ),
                    const Text('Delete'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startCall(BuildContext context, Contact contact, String mediaType) async {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    final calleeId = (contact.linkedUserId ?? '').trim();
    if (calleeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add the contact app UID first to start calls.'),
        ),
      );
      return;
    }

    final callsService = context.read<CallsService>();
    final callerName = (user.displayName ?? '').trim();

    try {
      final session = await callsService.startCall(
        callerId: user.uid,
        callerName: callerName.isEmpty ? 'Unknown' : callerName,
        callerPhotoUrl: user.photoURL,
        calleeId: calleeId,
        calleeName: contact.name,
        calleePhotoUrl: contact.avatarUrl,
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
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call failed (${error.runtimeType}).')),
      );
    }
  }

  String _initial(String name) {
    final safe = name.trim();
    if (safe.isEmpty) return '?';
    return safe.substring(0, 1).toUpperCase();
  }
}
