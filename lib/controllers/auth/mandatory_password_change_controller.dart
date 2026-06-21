import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class MandatoryPasswordChangeController extends ChangeNotifier {
  MandatoryPasswordChangeController({required AuthService authService})
    : _authService = authService;

  final AuthService _authService;

  final formKey = GlobalKey<FormState>();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  bool get isLoading => _isLoading;
  bool get obscureNewPassword => _obscureNewPassword;
  bool get obscureConfirmPassword => _obscureConfirmPassword;

  void toggleNewPasswordVisibility() {
    _obscureNewPassword = !_obscureNewPassword;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    _obscureConfirmPassword = !_obscureConfirmPassword;
    notifyListeners();
  }

  Future<String?> submit() async {
    if (!(formKey.currentState?.validate() ?? false)) {
      return 'Please complete all required fields.';
    }

    if (newPasswordController.text != confirmPasswordController.text) {
      return 'Passwords do not match';
    }

    if (newPasswordController.text.length < 8) {
      return 'Password must be at least 8 characters';
    }

    _setLoading(true);
    try {
      await _authService.changePasswordFromActiveSession(
        newPassword: newPasswordController.text,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'weak-password':
          return 'New password is too weak';
        case 'requires-recent-login':
          return 'Please sign in again, then change password.';
        default:
          return e.message ?? 'Failed to change password';
      }
    } catch (_) {
      return 'Failed to change password';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() => _authService.signOut();

  String? validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Enter a new password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirm your new password';
    }
    return null;
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
