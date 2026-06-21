import 'package:flutter/material.dart';

class UserProfileAvatar extends StatelessWidget {
  const UserProfileAvatar({
    super.key,
    required this.displayName,
    required this.photoUrlStream,
    this.initialPhotoUrl,
    this.radius = 20,
    this.showPresenceIndicator = false,
    this.presenceStatusStream,
    this.initialPresenceStatus = 'offline',
  });

  final String displayName;
  final Stream<String?> photoUrlStream;
  final String? initialPhotoUrl;
  final double radius;
  final bool showPresenceIndicator;
  final Stream<String>? presenceStatusStream;
  final String initialPresenceStatus;

  @override
  Widget build(BuildContext context) {
    final fallbackUrl = (initialPhotoUrl ?? '').trim();

    return StreamBuilder<String>(
      stream: showPresenceIndicator
          ? (presenceStatusStream ?? Stream.value(initialPresenceStatus))
          : Stream.value('offline'),
      initialData: initialPresenceStatus,
      builder: (context, statusSnapshot) {
        final status = _normalizePresenceStatus(
          statusSnapshot.data ?? 'offline',
        );

        return StreamBuilder<String?>(
          stream: photoUrlStream,
          initialData: fallbackUrl.isEmpty ? null : fallbackUrl,
          builder: (context, snapshot) {
            final photoUrl = (snapshot.data ?? '').trim();
            final initials = _initials(displayName);

            final avatar = photoUrl.isEmpty
                ? _fallbackAvatar(context, initials)
                : SizedBox(
                    width: radius * 2,
                    height: radius * 2,
                    child: ClipOval(
                      child: Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _fallbackFill(context, initials);
                        },
                      ),
                    ),
                  );

            if (!showPresenceIndicator) {
              return avatar;
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: radius * 0.55,
                    height: radius * 0.55,
                    decoration: BoxDecoration(
                      color: _presenceColor(status),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _fallbackAvatar(BuildContext context, String initials) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _fallbackFill(BuildContext context, String initials) {
    return Container(
      color: Theme.of(context).colorScheme.primary,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _initials(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return 'JD';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }

  String _normalizePresenceStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'online':
      case 'idle':
      case 'dnd':
      case 'offline':
        return value.trim().toLowerCase();
      default:
        return 'offline';
    }
  }

  Color _presenceColor(String status) {
    switch (_normalizePresenceStatus(status)) {
      case 'idle':
        return Colors.orange;
      case 'dnd':
        return Colors.redAccent;
      case 'offline':
        return Colors.grey;
      case 'online':
      default:
        return Colors.green;
    }
  }
}
