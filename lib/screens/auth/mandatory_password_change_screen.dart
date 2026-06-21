import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth/mandatory_password_change_controller.dart';
import '../../services/auth_service.dart';

class MandatoryPasswordChangeScreen extends StatelessWidget {
  const MandatoryPasswordChangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MandatoryPasswordChangeController>(
      create: (context) => MandatoryPasswordChangeController(
        authService: context.read<AuthService>(),
      ),
      child: const _MandatoryPasswordChangeView(),
    );
  }
}

class _MandatoryPasswordChangeView extends StatelessWidget {
  const _MandatoryPasswordChangeView();

  Future<void> _submit(BuildContext context) async {
    final controller = context.read<MandatoryPasswordChangeController>();
    final message = await controller.submit();
    if (!context.mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password updated successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MandatoryPasswordChangeController>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Change Password'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: controller.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_reset_outlined, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    'Password update required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For security reasons, you need to change your password before continuing.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: controller.newPasswordController,
                    obscureText: controller.obscureNewPassword,
                    validator: controller.validateNewPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          controller.obscureNewPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: controller.toggleNewPasswordVisibility,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller.confirmPasswordController,
                    obscureText: controller.obscureConfirmPassword,
                    validator: controller.validateConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          controller.obscureConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: controller.toggleConfirmPasswordVisibility,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: controller.isLoading
                        ? null
                        : () => _submit(context),
                    child: controller.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Update Password'),
                  ),
                  TextButton(
                    onPressed: controller.isLoading
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
        ),
      ),
    );
  }
}
