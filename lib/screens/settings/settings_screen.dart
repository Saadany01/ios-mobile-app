import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../controllers/settings/settings_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../shared/user_profile_avatar.dart';
import 'profile_information_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsController>(
      create: (context) => SettingsController(
        authService: context.read<AuthService>(),
        chatService: context.read<ChatService>(),
      ),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final user = settingsController.currentUser;
    final userName = (user?.displayName ?? '').trim();
    final userPhotoUrl = (user?.photoURL ?? '').trim();
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.settings),
            Text(
              s.manageAccount,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          UserProfileAvatar(
            displayName: userName,
            photoUrlStream: settingsController.profilePhotoUrlStream(),
            initialPhotoUrl: userPhotoUrl,
            showPresenceIndicator: true,
            presenceStatusStream: settingsController
                .currentUserPresenceStatusStream(),
            initialPresenceStatus: 'online',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          // Account Section
          _buildSectionHeader(s.account, isDark),
          _buildSettingTile(
            context,
            icon: Icons.person_outline,
            title: s.profileInformation,
            subtitle: userName.isEmpty ? 'John Doe' : userName,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: settingsController,
                    child: const ProfileInformationScreen(),
                  ),
                ),
              );
            },
          ),
          StreamBuilder<String>(
            stream: settingsController.currentUserPresenceStatusStream(),
            initialData: 'online',
            builder: (context, snapshot) {
              final status = _normalizePresence(snapshot.data ?? 'online');
              return _buildSettingTile(
                context,
                icon: _presenceIcon(status),
                title: s.status,
                subtitle: _presenceLabel(status, s),
                trailing: Icon(
                  Icons.circle,
                  size: 14,
                  color: _presenceColor(status),
                ),
                onTap: () {
                  _showPresenceDialog(
                    context,
                    settingsController,
                    currentStatus: status,
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),

          // Security Section
          _buildSectionHeader(s.security, isDark),
          _buildSettingTile(
            context,
            icon: Icons.lock_outline,
            title: s.changePassword,
            onTap: () {
              _showChangePasswordDialog(context, settingsController);
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.shield_outlined,
            title: s.authenticatorApp,
            subtitle: settingsController.isLoadingTotpStatus
                ? s.checkingStatus
                : settingsController.isTotpEnabled
                ? s.onForLogin
                : settingsController.hasTotpConfiguration
                ? s.offForLoginSaved
                : s.notConfiguredYet,
            trailing: settingsController.isLoadingTotpStatus
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (settingsController.hasTotpConfiguration)
                        IconButton(
                          tooltip: s.remove,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: settingsController.isTotpSetupBusy
                              ? null
                              : () {
                                  _handleTotpConfigurationRemoval(
                                    context,
                                    settingsController,
                                  );
                                },
                        ),
                      Switch(
                        value: settingsController.isTotpEnabled,
                        onChanged: settingsController.isTotpSetupBusy
                            ? null
                            : (value) {
                                _handleTotpToggle(
                                  context,
                                  settingsController,
                                  value,
                                );
                              },
                        activeThumbColor: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
            onTap:
                settingsController.isLoadingTotpStatus ||
                    settingsController.isTotpSetupBusy
                ? null
                : () {
                    _handleTotpToggle(
                      context,
                      settingsController,
                      !settingsController.isTotpEnabled,
                    );
                  },
          ),
          _buildSettingTile(
            context,
            icon: Icons.devices_outlined,
            title: s.trustedDevices,
            subtitle: '3 devices',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.deviceManagementComingSoon)),
              );
            },
          ),

          const SizedBox(height: 24),

          // Preferences Section
          _buildSectionHeader(s.preferences, isDark),
          _buildSettingTile(
            context,
            icon: Icons.language_outlined,
            title: s.language,
            subtitle: settingsController.selectedLanguageLabel,
            onTap: () {
              _showLanguageDialog(context, settingsController);
            },
          ),

          // Theme Toggle with Switch
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              title: Text(
                s.darkMode,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                isDark ? s.darkThemeEnabled : s.lightThemeEnabled,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              trailing: Switch(
                value: isDark,
                onChanged: (value) {
                  themeProvider.toggleTheme();
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),

          _buildSettingTile(
            context,
            icon: Icons.accessibility_outlined,
            title: s.accessibility,
            subtitle: s.configure,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.accessibilityComingSoon)),
              );
            },
          ),

          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader(s.about, isDark),
          _buildSettingTile(
            context,
            icon: Icons.info_outline,
            title: s.aboutApp,
            subtitle: 'Version 1.0.0',
            onTap: () {
              _showAboutDialog(context);
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.help_outline,
            title: s.helpSupport,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.helpCenterComingSoon)),
              );
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.privacy_tip_outlined,
            title: s.privacyPolicy,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.openingPrivacyPolicy)),
              );
            },
          ),

          const SizedBox(height: 24),

          // Logout Button
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: Text(
                s.logout,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () async {
                final confirm = await _showLogoutDialog(context);
                if (confirm == true && context.mounted) {
                  await settingsController.signOut();
                }
              },
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              )
            : null,
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
        onTap: onTap,
      ),
    );
  }

  Future<bool?> _showLogoutDialog(BuildContext context) {
    final s = AppStrings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.logoutConfirmTitle),
        content: Text(s.logoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(s.logout),
          ),
        ],
      ),
    );
  }

  Future<void> _showPresenceDialog(
    BuildContext context,
    SettingsController controller, {
    required String currentStatus,
  }) async {
    final s = AppStrings.of(context);
    final statuses = <String>['online', 'idle', 'dnd', 'offline'];

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.setStatus),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses.map((status) {
            return ListTile(
              leading: Icon(
                _presenceIcon(status),
                color: _presenceColor(status),
              ),
              title: Text(_presenceLabel(status, s)),
              trailing: status == currentStatus
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(dialogContext, status),
            );
          }).toList(),
        ),
      ),
    );

    if (!context.mounted || selected == null) return;

    final message = await controller.updatePresenceStatus(selected);
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${s.status}: ${_presenceLabel(selected, s)}')),
    );
  }

  String _normalizePresence(String value) {
    switch (value.trim().toLowerCase()) {
      case 'online':
      case 'idle':
      case 'dnd':
      case 'offline':
        return value.trim().toLowerCase();
      default:
        return 'online';
    }
  }

  String _presenceLabel(String status, AppStrings s) {
    switch (_normalizePresence(status)) {
      case 'idle':
        return s.presenceIdle;
      case 'dnd':
        return s.presenceDnd;
      case 'offline':
        return s.presenceOffline;
      case 'online':
      default:
        return s.presenceOnline;
    }
  }

  IconData _presenceIcon(String status) {
    switch (_normalizePresence(status)) {
      case 'idle':
        return Icons.schedule;
      case 'dnd':
        return Icons.do_not_disturb_on;
      case 'offline':
        return Icons.offline_bolt;
      case 'online':
      default:
        return Icons.circle;
    }
  }

  Color _presenceColor(String status) {
    switch (_normalizePresence(status)) {
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

  void _showChangePasswordDialog(
    BuildContext context,
    SettingsController controller,
  ) {
    final s = AppStrings.of(context);
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.changePasswordTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: s.currentPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: s.newPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: s.confirmPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final message = await controller.changePassword(
                currentPassword: currentPasswordController.text,
                newPassword: newPasswordController.text,
                confirmPassword: confirmPasswordController.text,
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
                SnackBar(content: Text(s.passwordChangedSuccess)),
              );
            },
            child: Text(s.change),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(
    BuildContext context,
    SettingsController controller,
  ) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    const langs = [
      ('en', 'English',   '🇬🇧'),
      ('es', 'Español',   '🇪🇸'),
      ('fr', 'Français',  '🇫🇷'),
      ('ar', 'العربية',   '🇸🇦'),
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Language / اللغة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: langs.map((lang) {
            final (code, label, flag) = lang;
            return RadioListTile<String>(
              title: Text('$flag  $label'),
              value: code,
              groupValue: controller.languageCode,
              activeColor: const Color(0xFF25D366),
              onChanged: (value) {
                if (value == null) return;
                controller.setLanguage(value);
                themeProvider.setLanguage(value);
                Navigator.pop(dialogContext);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _handleTotpToggle(
    BuildContext context,
    SettingsController controller,
    bool shouldEnable,
  ) async {
    if (shouldEnable == controller.isTotpEnabled) return;

    if (shouldEnable) {
      if (controller.hasTotpConfiguration) {
        final code = await _showEnableExistingTotpDialog(context);
        if (!context.mounted || code == null) return;

        final enableMessage = await controller.enableTotpFromSavedConfiguration(
          code,
        );
        if (!context.mounted) return;

        if (enableMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(enableMessage), backgroundColor: Colors.red),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authenticator app has been turned on.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      await _startTotpSetup(context, controller);
      return;
    }

    final shouldDisable = await _showDisableTotpDialog(context);
    if (!context.mounted || shouldDisable != true) return;

    final disableMessage = await controller.disableTotp();
    if (!context.mounted) return;

    if (disableMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disableMessage), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authenticator app has been turned off.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _startTotpSetup(
    BuildContext context,
    SettingsController controller,
  ) async {
    final startMessage = await controller.beginTotpSetup();
    if (!context.mounted) return;

    if (startMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(startMessage), backgroundColor: Colors.red),
      );
      return;
    }

    String? code;
    try {
      code = await _showTotpSetupDialog(context, controller);
    } catch (_) {
      if (!context.mounted) return;
      controller.cancelTotpSetup();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to open authenticator setup dialog.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!context.mounted || code == null) return;

    final verifyMessage = await controller.confirmTotpSetup(code);
    if (!context.mounted) return;

    if (verifyMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(verifyMessage), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authenticator app setup completed.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _handleTotpConfigurationRemoval(
    BuildContext context,
    SettingsController controller,
  ) async {
    final shouldRemove = await _showRemoveTotpConfigurationDialog(context);
    if (!context.mounted || shouldRemove != true) return;

    final removeMessage = await controller.removeTotpConfiguration();
    if (!context.mounted) return;

    if (removeMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(removeMessage), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authenticator configuration has been removed.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<bool?> _showDisableTotpDialog(BuildContext context) {
    final s = AppStrings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disable Authenticator App?'),
        content: const Text(
          'After turning it off, authenticator codes will not be accepted for login. The saved configuration will remain so you can turn it back on later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(s.turnOff),
          ),
        ],
      ),
    );
  }

  Future<String?> _showEnableExistingTotpDialog(BuildContext context) {
    final s = AppStrings.of(context);
    final codeController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Turn On Authenticator App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the current 6-digit code from your authenticator app to turn it on again.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Authenticator Code',
                hintText: s.enter6DigitCode,
                prefixIcon: const Icon(Icons.security_outlined),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, codeController.text.trim());
            },
            child: Text(s.turnOn),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showRemoveTotpConfigurationDialog(BuildContext context) {
    final s = AppStrings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Authenticator Configuration?'),
        content: const Text(
          'This removes the saved authenticator key. You will need to set up a new configuration before using authenticator login again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(s.remove),
          ),
        ],
      ),
    );
  }

  Future<String?> _showTotpSetupDialog(
    BuildContext context,
    SettingsController controller,
  ) {
    final s = AppStrings.of(context);
    final codeController = TextEditingController();
    final uri = controller.pendingTotpUri;
    final secret = controller.pendingTotpSecret;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Setup Authenticator App'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scan this QR code in Microsoft Authenticator, then enter the 6-digit code from the app.',
              ),
              const SizedBox(height: 16),
              if (uri != null)
                Center(
                  child: SizedBox.square(
                    dimension: 190,
                    child: QrImageView(
                      data: uri,
                      size: 190,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              if (secret != null && secret.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Manual setup key:'),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    secret,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Authenticator Code',
                  hintText: s.enter6DigitCode,
                  prefixIcon: const Icon(Icons.security_outlined),
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.cancelTotpSetup();
              Navigator.pop(dialogContext);
            },
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, codeController.text.trim());
            },
            child: Text(s.verify),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.aboutApp),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Version 1.0.0',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'A video calling app designed for the deaf community with sign language support.',
            ),
            const SizedBox(height: 16),
            Text(
              '© 2025 Sign Language App',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }
}
