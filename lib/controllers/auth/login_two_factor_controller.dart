import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

enum LoginVerificationMethod { authenticator, phone }

class LoginTwoFactorController extends ChangeNotifier {
  LoginTwoFactorController({required AuthService authService})
    : _authService = authService {
    _loadAuthenticatorState();
  }

  final AuthService _authService;

  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isCheckingAuthenticator = true;
  bool _isAuthenticatorConfigured = false;
  bool _hasAuthenticatorConfiguration = false;
  LoginVerificationMethod _selectedMethod = LoginVerificationMethod.phone;

  String? _phoneVerificationId;
  int? _phoneResendToken;

  bool get isSendingCode => _isSendingCode;
  bool get isVerifyingCode => _isVerifyingCode;
  bool get isBusy => _isSendingCode || _isVerifyingCode;
  bool get isCheckingAuthenticator => _isCheckingAuthenticator;
  bool get isAuthenticatorConfigured => _isAuthenticatorConfigured;
  bool get hasAuthenticatorConfiguration => _hasAuthenticatorConfiguration;
  LoginVerificationMethod get selectedMethod => _selectedMethod;

  bool get hasPhoneNumber {
    final phone = _authService.currentUser?.phoneNumber?.trim() ?? '';
    return phone.isNotEmpty;
  }

  String get maskedPhone {
    final phone = _authService.currentUser?.phoneNumber ?? '';
    return _maskPhone(phone);
  }

  Future<void> refreshAuthenticatorStatus() => _loadAuthenticatorState();

  void selectMethod(LoginVerificationMethod method) {
    if (method == LoginVerificationMethod.authenticator &&
        !_isAuthenticatorConfigured) {
      return;
    }

    if (_selectedMethod == method) return;
    _selectedMethod = method;
    notifyListeners();
  }

  Future<String?> sendCode() async {
    if (_selectedMethod == LoginVerificationMethod.authenticator) {
      return null;
    }

    if (!hasPhoneNumber) {
      return 'No verified phone number found on this account.';
    }

    return _sendPhoneCode();
  }

  Future<String?> verifyCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.length != 6) {
      return 'Enter the 6-digit verification code.';
    }

    if (_selectedMethod == LoginVerificationMethod.authenticator) {
      return _verifyAuthenticatorCode(code);
    }

    return _verifyPhoneCode(code);
  }

  Future<void> signOut() => _authService.signOut();

  Future<void> _loadAuthenticatorState() async {
    _setCheckingAuthenticator(true);
    try {
      _hasAuthenticatorConfiguration = await _authService
          .hasCurrentUserTotpConfiguration();
      final isEnabled = await _authService.isCurrentUserTotpEnabled();
      _isAuthenticatorConfigured = isEnabled && _hasAuthenticatorConfiguration;
      _selectedMethod = _isAuthenticatorConfigured
          ? LoginVerificationMethod.authenticator
          : LoginVerificationMethod.phone;
    } catch (_) {
      _isAuthenticatorConfigured = false;
      _hasAuthenticatorConfiguration = false;
      _selectedMethod = LoginVerificationMethod.phone;
    } finally {
      _setCheckingAuthenticator(false);
    }
  }

  Future<String?> _sendPhoneCode() async {
    _setSendingCode(true);
    try {
      final request = await _authService
          .requestCurrentUserPhoneVerificationCode(
            forceResendingToken: _phoneResendToken,
          );

      _phoneVerificationId = request.verificationId;
      _phoneResendToken = request.resendToken;
      notifyListeners();

      if (request.autoCredential != null) {
        return _completeWithPhoneCredential(request.autoCredential!);
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Failed to send phone verification code.';
    } finally {
      _setSendingCode(false);
    }
  }

  Future<String?> _verifyAuthenticatorCode(String code) async {
    _setVerifyingCode(true);
    try {
      await _authService.verifyCurrentUserTotpCode(code);
      await _authService.completeLoginSecondFactor();
      return null;
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Failed to verify authenticator code.';
    } finally {
      _setVerifyingCode(false);
    }
  }

  Future<String?> _verifyPhoneCode(String code) async {
    final verificationId = _phoneVerificationId;
    if (verificationId == null) {
      return 'Please request a phone code first.';
    }

    try {
      final credential = _authService.createPhoneCredential(
        verificationId: verificationId,
        smsCode: code,
      );
      return _completeWithPhoneCredential(credential);
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Failed to verify phone code.';
    }
  }

  Future<String?> _completeWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    _setVerifyingCode(true);
    try {
      await _authService.reauthenticateWithPhoneCredential(credential);
      await _authService.completeLoginSecondFactor();
      return null;
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Phone verification failed.';
    } finally {
      _setVerifyingCode(false);
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Invalid verification code';
      case 'session-expired':
        return 'Verification session expired. Request a new code';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'missing-phone-number':
        return 'No verified phone number found for this account.';
      case 'totp-not-configured':
        return 'Authenticator app is not configured. Use phone verification.';
      case 'totp-disabled':
        return 'Authenticator app is turned off. Use phone verification.';
      default:
        return e.message ?? 'Verification failed';
    }
  }

  void _setSendingCode(bool value) {
    if (_isSendingCode == value) return;
    _isSendingCode = value;
    notifyListeners();
  }

  void _setVerifyingCode(bool value) {
    if (_isVerifyingCode == value) return;
    _isVerifyingCode = value;
    notifyListeners();
  }

  void _setCheckingAuthenticator(bool value) {
    if (_isCheckingAuthenticator == value) return;
    _isCheckingAuthenticator = value;
    notifyListeners();
  }

  String _maskPhone(String phone) {
    final safe = phone.trim();
    if (safe.length <= 4) return safe;
    final last = safe.substring(safe.length - 4);
    return '***$last';
  }
}
