import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/chat/direct_messages_controller.dart';
import '../../models/chat_model.dart';

class FriendsManagementScreen extends StatelessWidget {
  const FriendsManagementScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: const _FriendsManagementView(),
    );
  }
}

class _FriendsManagementView extends StatelessWidget {
  const _FriendsManagementView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DirectMessagesController>();
    final user = controller.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Add Friend'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: user == null
          ? const Center(child: Text('Please log in'))
          : TabBarView(
              children: [
                _AddFriendTab(controller: controller),
                _RequestsTab(controller: controller, userId: user.uid),
              ],
            ),
    );
  }
}

class _AddFriendTab extends StatelessWidget {
  const _AddFriendTab({required this.controller});

  final DirectMessagesController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: controller.addFriendController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(context),
          decoration: const InputDecoration(
            labelText: 'Friend Username',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: controller.isSendingRequest
              ? null
              : () => _submit(context),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (controller.isSendingRequest)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.person_add_alt_1),
              const SizedBox(width: 8),
              Text(controller.isSendingRequest ? 'Sending...' : 'Add Friend'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final message = await controller.sendFriendRequest();
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Friend request sent.'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.controller, required this.userId});

  final DirectMessagesController controller;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendRequestItem>>(
      stream: controller.incomingFriendRequestsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return Center(
            child: Text(
              'No friend requests',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        return ListView.separated(
          itemCount: requests.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = requests[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: (item.fromPhotoUrl ?? '').trim().isEmpty
                    ? null
                    : NetworkImage(item.fromPhotoUrl!.trim()),
                child: (item.fromPhotoUrl ?? '').trim().isEmpty
                    ? Text(_initials(item.fromDisplayName))
                    : null,
              ),
              title: Text(item.fromDisplayName),
              subtitle: Text('@${item.fromUsername}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Decline',
                    onPressed: controller.isHandlingRequest
                        ? null
                        : () => _decline(context, item.id),
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: 'Accept',
                    onPressed: controller.isHandlingRequest
                        ? null
                        : () => _accept(context, item.id),
                    icon: const Icon(Icons.check, color: Colors.green),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _accept(BuildContext context, String requestId) async {
    final message = await controller.acceptFriendRequest(requestId);
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Friend request accepted.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _decline(BuildContext context, String requestId) async {
    final message = await controller.declineFriendRequest(requestId);
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Friend request declined.')));
  }

  String _initials(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return 'U';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }
}
