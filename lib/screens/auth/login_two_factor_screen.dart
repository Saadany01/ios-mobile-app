import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth/login_two_factor_controller.dart';
import '../../services/auth_service.dart';

class LoginTwoFactorScreen extends StatelessWidget {
  const LoginTwoFactorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LoginTwoFactorController>(
      create: (context) =>
          LoginTwoFactorController(authService: context.read<AuthService>()),
      child: const _LoginTwoFactorView(),
    );
  }
}

class _LoginTwoFactorView extends StatefulWidget {
  const _LoginTwoFactorView();

  @override
  State<_LoginTwoFactorView> createState() => _LoginTwoFactorViewState();
}

class _LoginTwoFactorViewState extends State<_LoginTwoFactorView> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode(BuildContext context) async {
    final controller = context.read<LoginTwoFactorController>();
    final usesAuthenticator =
        controller.selectedMethod == LoginVerificationMethod.authenticator;
    final message = await controller.sendCode();
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          usesAuthenticator
              ? 'Open Microsoft Authenticator and enter the current 6-digit code.'
              : 'Verification code sent.',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _verifyCode(BuildContext context) async {
    final controller = context.read<LoginTwoFactorController>();
    final message = await controller.verifyCode(_codeController.text);
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LoginTwoFactorController>();
    final usingAuthenticator =
        controller.selectedMethod == LoginVerificationMethod.authenticator;

    if (controller.isCheckingAuthenticator) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final authenticatorUnavailableHint =
        controller.hasAuthenticatorConfiguration
        ? 'Authenticator app is turned off in Settings. Turn it on to use it for login.'
        : 'Authenticator app is not configured. Set it up in Settings first.';

    final methodHint = usingAuthenticator
        ? controller.isAuthenticatorConfigured
              ? 'Open Microsoft Authenticator and enter the current 6-digit code.'
              : authenticatorUnavailableHint
        : controller.hasPhoneNumber
        ? 'Send a 6-digit SMS code to ${controller.maskedPhone}.'
        : 'No verified phone number found for this account.';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Verify Your Identity'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined, size: 72),
              const SizedBox(height: 20),
              Text(
                'Two-step verification',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to receive your verification code.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Authenticator App'),
                    selected:
                        controller.selectedMethod ==
                        LoginVerificationMethod.authenticator,
                    onSelected: controller.isAuthenticatorConfigured
                        ? (_) {
                            controller.selectMethod(
                              LoginVerificationMethod.authenticator,
                            );
                          }
                        : null,
                  ),
                  ChoiceChip(
                    label: const Text('Phone'),
                    selected:
                        controller.selectedMethod ==
                        LoginVerificationMethod.phone,
                    onSelected: controller.hasPhoneNumber
                        ? (_) {
                            controller.selectMethod(
                              LoginVerificationMethod.phone,
                            );
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                methodHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!controller.isAuthenticatorConfigured)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.hasAuthenticatorConfiguration
                        ? 'Authenticator app is saved but currently turned off in Settings.'
                        : 'Set up Authenticator App in Settings before using it for login.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: controller.isBusy ? null : () => _sendCode(context),
                icon: controller.isSendingCode
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        usingAuthenticator
                            ? Icons.shield_outlined
                            : Icons.send_outlined,
                      ),
                label: Text(
                  controller.isSendingCode
                      ? 'Sending...'
                      : usingAuthenticator
                      ? 'Use Authenticator App'
                      : 'Send 6-digit code',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  hintText: 'Enter 6-digit code',
                  prefixIcon: Icon(Icons.password_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: controller.isBusy
                    ? null
                    : () => _verifyCode(context),
                child: controller.isVerifyingCode
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Verify'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () async {
                        await controller.signOut();
                      },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
