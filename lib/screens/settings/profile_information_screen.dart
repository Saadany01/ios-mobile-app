import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/settings/settings_controller.dart';
import '../../core/l10n/app_strings.dart';

class ProfileInformationScreen extends StatefulWidget {
  const ProfileInformationScreen({super.key});

  @override
  State<ProfileInformationScreen> createState() =>
      _ProfileInformationScreenState();
}

class _ProfileInformationScreenState extends State<ProfileInformationScreen> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;

  bool _isSavingDisplayName = false;
  bool _isSavingUsername = false;
  bool _isUpdatingPhoto = false;
  bool _isDeletingAccount = false;
  bool _revealEmail = false;
  bool _revealPhone = false;

  String _lastDisplayName = '';
  String _lastUsername = '';

  @override
  void initState() {
    super.initState();
    final user = context.read<SettingsController>().currentUser;
    _lastDisplayName = (user?.displayName ?? '').trim();
    _displayNameController = TextEditingController(text: _lastDisplayName);
    _usernameController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final user = controller.currentUser;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: controller.currentUserProfileDataStream(),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const <String, dynamic>{};
        final displayName =
            ((user?.displayName ?? profile['displayName'] ?? '') as String)
                .trim();
        final username = (profile['username'] ?? '').toString().trim();
        final photoUrl = (profile['photoURL'] ?? user?.photoURL ?? '')
            .toString()
            .trim();
        final email = (user?.email ?? '').trim();
        final phone = (user?.phoneNumber ?? '').trim();

        if (!_isSavingDisplayName &&
            displayName.isNotEmpty &&
            displayName != _lastDisplayName) {
          _lastDisplayName = displayName;
          _displayNameController.text = displayName;
        }

        if (!_isSavingUsername && username != _lastUsername) {
          _lastUsername = username;
          _usernameController.text = username;
        }

        return Scaffold(
          appBar: AppBar(title: Text(AppStrings.of(context).profileInformation)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileCard(
                displayName: displayName,
                username: username,
                photoUrl: photoUrl.isEmpty ? null : photoUrl,
                isUpdatingPhoto: _isUpdatingPhoto,
                onPhotoTap: _pickAndUploadPhoto,
              ),
              const SizedBox(height: 16),
              _EditableFieldCard(
                title: AppStrings.of(context).displayName,
                hintText: 'Enter display name',
                prefixIcon: Icons.badge_outlined,
                controller: _displayNameController,
                isSaving: _isSavingDisplayName,
                onSave: _saveDisplayName,
              ),
              const SizedBox(height: 12),
              _EditableFieldCard(
                title: AppStrings.of(context).username,
                hintText: 'example_handle',
                prefixIcon: Icons.alternate_email,
                controller: _usernameController,
                isSaving: _isSavingUsername,
                onSave: _saveUsername,
              ),
              const SizedBox(height: 12),
              _InfoCard(
                icon: Icons.email_outlined,
                title: AppStrings.of(context).email,
                value: email.isEmpty
                    ? AppStrings.of(context).noEmailOnAccount
                    : (_revealEmail ? email : _maskEmail(email)),
                actionText: email.isEmpty
                    ? null
                    : (_revealEmail ? AppStrings.of(context).hide : AppStrings.of(context).reveal),
                onAction: email.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _revealEmail = !_revealEmail;
                        });
                      },
              ),
              const SizedBox(height: 12),
              _InfoCard(
                icon: Icons.phone_outlined,
                title: AppStrings.of(context).phoneNumber,
                value: phone.isEmpty
                    ? AppStrings.of(context).noVerifiedPhone
                    : (_revealPhone ? phone : _maskPhone(phone)),
                actionText: phone.isEmpty
                    ? null
                    : (_revealPhone ? AppStrings.of(context).hide : AppStrings.of(context).reveal),
                onAction: phone.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _revealPhone = !_revealPhone;
                        });
                      },
              ),
              const SizedBox(height: 16),
              _DangerZone(
                isDeleting: _isDeletingAccount,
                onDelete: _confirmAndDeleteAccount,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveDisplayName() async {
    final controller = context.read<SettingsController>();
    final nextValue = _displayNameController.text.trim();

    if (_isSavingDisplayName) return;
    if (nextValue == _lastDisplayName) {
      _showMessage(AppStrings.of(context).noDisplayNameChanges);
      return;
    }

    setState(() {
      _isSavingDisplayName = true;
    });

    final message = await controller.updateDisplayName(nextValue);
    if (!mounted) return;

    setState(() {
      _isSavingDisplayName = false;
    });

    if (message != null) {
      _showMessage(message, isError: true);
      return;
    }

    _lastDisplayName = nextValue;
    _showMessage(AppStrings.of(context).displayNameUpdated, isSuccess: true);
  }

  Future<void> _saveUsername() async {
    final controller = context.read<SettingsController>();
    final nextValue = _usernameController.text.trim();

    if (_isSavingUsername) return;
    if (nextValue == _lastUsername) {
      _showMessage(AppStrings.of(context).noUsernameChanges);
      return;
    }

    setState(() {
      _isSavingUsername = true;
    });

    final message = await controller.updateUsername(nextValue);
    if (!mounted) return;

    setState(() {
      _isSavingUsername = false;
    });

    if (message != null) {
      _showMessage(message, isError: true);
      return;
    }

    _lastUsername = nextValue;
    _showMessage(AppStrings.of(context).usernameUpdated, isSuccess: true);
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_isUpdatingPhoto) return;

    setState(() {
      _isUpdatingPhoto = true;
    });

    final message = await context
        .read<SettingsController>()
        .pickAndUploadProfilePhoto();

    if (!mounted) return;

    setState(() {
      _isUpdatingPhoto = false;
    });

    if (message == 'cancelled') {
      return;
    }

    if (message != null) {
      _showMessage(message, isError: true);
      return;
    }

    _showMessage(AppStrings.of(context).profilePictureUpdated, isSuccess: true);
  }

  Future<void> _confirmAndDeleteAccount() async {
    final confirm = await _showDeleteDialog();
    if (!mounted || confirm != true) return;

    if (_isDeletingAccount) return;

    setState(() {
      _isDeletingAccount = true;
    });

    final message = await context.read<SettingsController>().deleteAccount();
    if (!mounted) return;

    setState(() {
      _isDeletingAccount = false;
    });

    if (message != null) {
      _showMessage(message, isError: true);
      return;
    }

    _showMessage(AppStrings.of(context).accountDeleted, isSuccess: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<bool?> _showDeleteDialog() {
    final confirmationController = TextEditingController();
    var isMatch = false;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final s = AppStrings.of(context);
          return AlertDialog(
            title: Text(s.deleteAccount),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.deleteConfirmation),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmationController,
                  onChanged: (value) {
                    setDialogState(() {
                      isMatch = value.trim() == 'DELETE';
                    });
                  },
                  decoration: InputDecoration(labelText: s.typeDeleteToConfirm),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(s.cancel),
              ),
              ElevatedButton(
                onPressed: isMatch
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: Text(s.deleteAccount),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMessage(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    final bgColor = isError
        ? Colors.redAccent
        : isSuccess
        ? Colors.green
        : null;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: bgColor));
  }

  String _maskEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0 || atIndex == email.length - 1) {
      return '********';
    }

    final local = email.substring(0, atIndex);
    final domain = email.substring(atIndex);

    if (local.length <= 2) {
      return '${local[0]}***$domain';
    }

    return '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}$domain';
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) return '****';
    final visible = phone.substring(phone.length - 4);
    final hiddenLength = phone.length - 4;
    return '${'*' * hiddenLength}$visible';
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.isUpdatingPhoto,
    required this.onPhotoTap,
  });

  final String displayName;
  final String username;
  final String? photoUrl;
  final bool isUpdatingPhoto;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final title = displayName.isEmpty ? 'No display name' : displayName;
    final handle = username.isEmpty ? '@set_username' : '@$username';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPhotoTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: (photoUrl ?? '').trim().isEmpty
                      ? null
                      : NetworkImage(photoUrl!.trim()),
                  child: (photoUrl ?? '').trim().isEmpty
                      ? Text(
                          _initials(title),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: isUpdatingPhoto
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_outlined,
                            size: 13,
                            color: Colors.white,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return 'U';
    if (safe.length == 1) return safe.toUpperCase();
    return safe.substring(0, 2).toUpperCase();
  }
}

class _EditableFieldCard extends StatelessWidget {
  const _EditableFieldCard({
    required this.title,
    required this.hintText,
    required this.prefixIcon,
    required this.controller,
    required this.isSaving,
    required this.onSave,
  });

  final String title;
  final String hintText;
  final IconData prefixIcon;
  final TextEditingController controller;
  final bool isSaving;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isSaving,
                  decoration: InputDecoration(
                    hintText: hintText,
                    prefixIcon: Icon(prefixIcon),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isSaving ? null : onSave,
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppStrings.of(context).save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    this.actionText,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
        trailing: actionText == null
            ? null
            : TextButton(onPressed: onAction, child: Text(actionText!)),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.isDeleting, required this.onDelete});

  final bool isDeleting;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.of(context).dangerZone,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(AppStrings.of(context).deleteAccountPermanently),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: isDeleting ? null : onDelete,
            icon: isDeleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_outlined),
            label: Text(isDeleting ? AppStrings.of(context).deleting : AppStrings.of(context).deleteAccount),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
