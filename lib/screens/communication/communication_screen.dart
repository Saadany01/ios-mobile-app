import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/auth_service.dart';
import '../calls/calls_screen.dart';
import '../contacts/contacts_screen.dart';
import '../shared/user_profile_avatar.dart';

class CommunicationScreen extends StatelessWidget {
  const CommunicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(length: 2, child: _CommunicationView());
  }
}

class _CommunicationView extends StatelessWidget {
  const _CommunicationView();

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    final userName = (user?.displayName ?? '').trim();
    final userPhotoUrl = (user?.photoURL ?? '').trim();
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.communication),
        actions: [
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
        bottom: TabBar(
          tabs: [
            Tab(text: s.contacts, icon: const Icon(Icons.people_outline)),
            Tab(text: s.calls, icon: const Icon(Icons.phone_outlined)),
          ],
        ),
      ),
      body: const TabBarView(
        children: [ContactsScreen(embedded: true), CallsScreen(embedded: true)],
      ),
    );
  }
}
