import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class LoginController extends ChangeNotifier {
  LoginController({required AuthService authService})
    : _authService = authService;

  final AuthService _authService;

  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get isLoading => _isLoading;
  bool get obscurePassword => _obscurePassword;

  String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Enter email';
    }
    if (!_emailPattern.hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Enter password';
    }
    return null;
  }

  void togglePasswordVisibility() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  Future<String?> login() async {
    if (!(formKey.currentState?.validate() ?? false)) {
      return 'Please complete all required fields.';
    }

    _setLoading(true);
    try {
      await _authService.signIn(
        email: emailController.text,
        password: passwordController.text,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromAuthError(e);
    } catch (_) {
      return 'Login failed. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  Future<String?> sendPasswordResetEmail([String? emailInput]) async {
    final email = (emailInput ?? emailController.text).trim();

    if (email.isEmpty) {
      return 'Enter your registered email address.';
    }

    if (!_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }

    try {
      await _authService.sendPasswordResetEmail(email);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No user found with this email';
        case 'invalid-email':
          return 'Invalid email address';
        case 'too-many-requests':
          return 'Too many requests. Please try again later.';
        default:
          return e.message ?? 'Could not send reset email';
      }
    } catch (_) {
      return 'Could not send reset email';
    }
  }

  String _messageFromAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-credential':
        return 'Invalid email or password';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? 'Login failed';
    }
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
