import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth/login_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../services/auth_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LoginController>(
      create: (context) =>
          LoginController(authService: context.read<AuthService>()),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatelessWidget {
  const _LoginView();

  Future<void> _handleLogin(BuildContext context) async {
    final controller = context.read<LoginController>();
    final message = await controller.login();
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _handleForgotPassword(BuildContext context) async {
    final controller = context.read<LoginController>();
    final emailCtrl = TextEditingController(text: controller.emailController.text.trim());

    final enteredEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Your email',
            labelStyle: TextStyle(color: Colors.white54),
            prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF25D366)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: () => Navigator.pop(ctx, emailCtrl.text),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (enteredEmail == null || !context.mounted) return;
    final message = await controller.sendPasswordResetEmail(enteredEmail);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message ?? 'Password reset email sent. Check your inbox.'),
      backgroundColor: message != null ? Colors.redAccent : const Color(0xFF25D366),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LoginController>();
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Form(
              key: controller.formKey,
              child: Column(
                children: [
                  Image.asset('assets/images/logo.png', width: 110, height: 110),
                  const SizedBox(height: 12),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Color(0xFF25D366), Color(0xFF00E676)],
                    ).createShader(b),
                    child: const Text(
                      'HearMySign',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(s.welcomeBack, style: const TextStyle(color: Colors.white38, fontSize: 14)),
                  const SizedBox(height: 40),

                  _Field(
                    controller: controller.emailController,
                    hint: s.emailAddress,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: controller.validateEmail,
                  ),
                  const SizedBox(height: 14),

                  _Field(
                    controller: controller.passwordController,
                    hint: s.password,
                    icon: Icons.lock_outline,
                    obscure: controller.obscurePassword,
                    validator: controller.validatePassword,
                    suffix: IconButton(
                      icon: Icon(
                        controller.obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: Colors.white38, size: 20,
                      ),
                      onPressed: controller.togglePasswordVisibility,
                    ),
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: controller.isLoading ? null : () => _handleForgotPassword(context),
                      child: Text(s.forgotPassword, style: const TextStyle(color: Color(0xFF25D366), fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF00C853)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: const Color(0xFF25D366).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: ElevatedButton(
                        onPressed: controller.isLoading ? null : () => _handleLogin(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: controller.isLoading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : Text(s.login, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.noAccount, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                        child: Text(s.signUp, style: const TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: Icon(icon, color: const Color(0xFF25D366), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF1A2332),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A3942), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF25D366), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
