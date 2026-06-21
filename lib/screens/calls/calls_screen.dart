import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../controllers/calls/calls_controller.dart';
import '../../models/call_model.dart';
import '../../services/auth_service.dart';
import '../../services/calls_service.dart';
import 'call_screen.dart';
import '../shared/user_profile_avatar.dart';

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Provider<CallsController>(
      create: (context) =>
          CallsController(callsService: context.read<CallsService>()),
      child: _CallsView(embedded: embedded),
    );
  }
}

class _CallsView extends StatelessWidget {
  const _CallsView({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CallsController>();
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    final userName = (user?.displayName ?? '').trim();
    final userPhotoUrl = (user?.photoURL ?? '').trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final body = _buildBody(context, controller, user?.uid, isDark);

    if (embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: [
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

  Widget _buildBody(
    BuildContext context,
    CallsController controller,
    String? userId,
    bool isDark,
  ) {
    if (userId == null) {
      return const Center(child: Text('Please log in'));
    }

    return StreamBuilder<List<CallRecord>>(
      stream: controller.callsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final calls = snapshot.data ?? [];

        if (calls.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone_outlined, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No call history',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a call from Contacts',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: calls.length,
          itemBuilder: (context, index) {
            final call = calls[index];
            return _buildCallTile(context, call, isDark, controller);
          },
        );
      },
    );
  }

  Widget _buildCallTile(
    BuildContext context,
    CallRecord call,
    bool isDark,
    CallsController controller,
  ) {
    final callIcon = controller.iconForType(call.type);
    final callIconColor = controller.colorForType(call.type);
    final timeText = controller.formatTimeLabel(call.timestamp);
    final safeName = call.contactName.trim();
    final avatarText = safeName.isEmpty
        ? '?'
        : safeName.substring(0, 1).toUpperCase();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[300],
        child: call.contactAvatar != null
            ? null
            : Text(
                avatarText,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
      title: Text(
        call.contactName,
        style: TextStyle(
          fontSize: 16,
          fontWeight: call.type == CallType.missed
              ? FontWeight.bold
              : FontWeight.w500,
          color: call.type == CallType.missed ? Colors.red : null,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(callIcon, size: 16, color: callIconColor),
          const SizedBox(width: 4),
          Text(
            timeText,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          if (call.duration > 0) ...[
            const Text(' • '),
            Text(
              call.formattedDuration,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.call,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
        onPressed: () {
          _makeCall(context, call);
        },
      ),
    );
  }

  Future<void> _makeCall(BuildContext context, CallRecord call) async {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    final calleeId = (call.contactUserId ?? '').trim();
    if (calleeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This call record has no linked app UID to call.'),
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
        calleeName: call.contactName,
        calleePhotoUrl: call.contactAvatar,
        mediaType: 'audio',
      );

      if (!context.mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(callId: session.id, isCaller: true, mediaType: 'audio'),
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
}
