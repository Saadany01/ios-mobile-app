import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class SignupController extends ChangeNotifier {
  SignupController({required AuthService authService})
    : _authService = authService;

  final AuthService _authService;

  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isSendingPhoneCode = false;
  bool _isVerifyingPhoneCode = false;
  bool _isPhoneVerified = false;
  String _selectedCountryDialCode = '+1';
  String _normalizedPhoneNumber = '';

  String? _phoneVerificationId;
  int? _phoneResendToken;
  String? _verifiedPhoneNumber;
  PhoneAuthCredential? _phoneCredential;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');
  final RegExp _e164PhonePattern = RegExp(r'^\+[1-9]\d{7,14}$');

  bool get isLoading => _isLoading;
  bool get isSendingPhoneCode => _isSendingPhoneCode;
  bool get isVerifyingPhoneCode => _isVerifyingPhoneCode;
  bool get isPhoneVerified => _isPhoneVerified;
  String get selectedCountryDialCode => _selectedCountryDialCode;
  String get normalizedPhoneNumber => _normalizedPhoneNumber;
  bool get obscurePassword => _obscurePassword;
  bool get obscureConfirmPassword => _obscureConfirmPassword;
  bool get agreedToTerms => _agreedToTerms;

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }
    return null;
  }

  String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Please enter your email';
    }
    if (!_emailPattern.hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? validateUsername(String? value) {
    final username = (value ?? '').trim().toLowerCase();
    if (username.isEmpty) {
      return 'Please enter a username';
    }
    if (!_usernamePattern.hasMatch(username)) {
      return 'Use 3-20 lowercase letters, numbers, or _';
    }
    return null;
  }

  String? validatePhoneNumber(String? value) {
    final normalized = _buildE164(
      localNumber: value ?? '',
      countryDialCode: _selectedCountryDialCode,
    );
    if (normalized.isEmpty) {
      return 'Please enter your phone number';
    }
    if (!_e164PhonePattern.hasMatch(normalized)) {
      return 'Use phone format like +1234567890';
    }
    return null;
  }

  // Backward-compatible alias used by older UI code.
  String? validateEmailOrPhone(String? value) => validateEmail(value);

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    return null;
  }

  void togglePasswordVisibility() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    _obscureConfirmPassword = !_obscureConfirmPassword;
    notifyListeners();
  }

  void setAgreedToTerms(bool value) {
    _agreedToTerms = value;
    notifyListeners();
  }

  void onPhoneNumberChanged({
    required String localNumber,
    required String countryDialCode,
  }) {
    _selectedCountryDialCode = _normalizeCountryDialCode(countryDialCode);
    final normalized = _buildE164(
      localNumber: localNumber,
      countryDialCode: _selectedCountryDialCode,
    );
    _normalizedPhoneNumber = normalized;

    if (_verifiedPhoneNumber == normalized) return;

    if (_isPhoneVerified ||
        _phoneCredential != null ||
        _phoneVerificationId != null) {
      _isPhoneVerified = false;
      _phoneCredential = null;
      _phoneVerificationId = null;
      _phoneResendToken = null;
      _verifiedPhoneNumber = null;
      notifyListeners();
    }
  }

  Future<String?> sendPhoneVerificationCode() async {
    final phoneValidation = validatePhoneNumber(phoneController.text);
    if (phoneValidation != null) {
      return phoneValidation;
    }

    final normalizedPhone = _buildE164(
      localNumber: phoneController.text,
      countryDialCode: _selectedCountryDialCode,
    );
    _normalizedPhoneNumber = normalizedPhone;
    _setSendingPhoneCode(true);

    try {
      final request = await _authService.requestPhoneVerificationCode(
        phoneNumber: normalizedPhone,
        forceResendingToken: _phoneResendToken,
      );

      _phoneVerificationId = request.verificationId;
      _phoneResendToken = request.resendToken;
      _phoneCredential = request.autoCredential;
      _isPhoneVerified = request.autoCredential != null;
      _verifiedPhoneNumber = _isPhoneVerified ? normalizedPhone : null;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _phoneMessageFromAuthError(e);
    } catch (_) {
      return 'Failed to send verification code. Try again.';
    } finally {
      _setSendingPhoneCode(false);
    }
  }

  Future<String?> verifyPhoneCode(String smsCode) async {
    final verificationId = _phoneVerificationId;
    if (verificationId == null) {
      return 'Please request a verification code first.';
    }

    final code = smsCode.trim();
    if (code.length < 6) {
      return 'Enter the 6-digit verification code.';
    }

    _setVerifyingPhoneCode(true);
    try {
      _phoneCredential = _authService.createPhoneCredential(
        verificationId: verificationId,
        smsCode: code,
      );
      _isPhoneVerified = true;
      _verifiedPhoneNumber = _buildE164(
        localNumber: phoneController.text,
        countryDialCode: _selectedCountryDialCode,
      );
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _phoneMessageFromAuthError(e);
    } catch (_) {
      return 'Failed to verify code. Please try again.';
    } finally {
      _setVerifyingPhoneCode(false);
    }
  }

  Future<String?> signUp() async {
    if (!(formKey.currentState?.validate() ?? false)) {
      return 'Please complete all required fields.';
    }

    if (!_agreedToTerms) {
      return 'Please agree to Terms of Service and Privacy Policy';
    }

    if (passwordController.text != confirmPasswordController.text) {
      return 'Passwords do not match';
    }

    final phoneValidation = validatePhoneNumber(phoneController.text);
    if (phoneValidation != null) {
      return phoneValidation;
    }

    final normalizedPhone = _buildE164(
      localNumber: phoneController.text,
      countryDialCode: _selectedCountryDialCode,
    );
    _normalizedPhoneNumber = normalizedPhone;

    // Phone SMS verification is optional. If the user verified their phone we
    // link that credential; otherwise we still create the account and just
    // store the phone number on the profile.
    final verifiedCredential =
        (_isPhoneVerified && _verifiedPhoneNumber == normalizedPhone)
        ? _phoneCredential
        : null;

    _setLoading(true);
    try {
      await _authService.signUp(
        name: nameController.text,
        email: emailController.text,
        password: passwordController.text,
        phoneNumber: normalizedPhone,
        phoneCredential: verifiedCredential,
        username: usernameController.text,
      );

      _isPhoneVerified = false;
      _verifiedPhoneNumber = null;
      _phoneCredential = null;
      _phoneVerificationId = null;
      _phoneResendToken = null;
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromAuthError(e);
    } catch (_) {
      return 'Sign up failed. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  String _messageFromAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Password is too weak';
      case 'email-already-in-use':
        return 'Email is already registered';
      case 'invalid-email':
        return 'Please enter a valid email address';
      case 'credential-already-in-use':
      case 'phone-number-already-exists':
        return 'This phone number is already linked to another account';
      case 'invalid-verification-code':
        return 'The SMS code is invalid. Please verify phone again';
      case 'session-expired':
        return 'Verification code expired. Please request a new code';
      default:
        return e.message ?? 'Sign up failed';
    }
  }

  String _phoneMessageFromAuthError(FirebaseAuthException e) {
    final message = e.message ?? '';
    if (message.contains('BILLING_NOT_ENABLED')) {
      return 'Phone verification requires billing to be enabled in Firebase project settings.';
    }

    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number format';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try later';
      case 'session-expired':
        return 'Verification session expired. Request a new code';
      case 'invalid-verification-code':
        return 'Invalid verification code';
      default:
        return e.message ?? 'Phone verification failed';
    }
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  void _setSendingPhoneCode(bool value) {
    if (_isSendingPhoneCode == value) return;
    _isSendingPhoneCode = value;
    notifyListeners();
  }

  void _setVerifyingPhoneCode(bool value) {
    if (_isVerifyingPhoneCode == value) return;
    _isVerifyingPhoneCode = value;
    notifyListeners();
  }

  String _normalizeCountryDialCode(String dialCode) {
    final compact = dialCode.replaceAll(RegExp(r'\s+'), '').trim();
    if (compact.isEmpty) return '+1';
    if (compact.startsWith('+')) return compact;
    return '+$compact';
  }

  String _buildE164({
    required String localNumber,
    required String countryDialCode,
  }) {
    final localDigits = localNumber.replaceAll(RegExp(r'\D'), '');
    if (localDigits.isEmpty) return '';

    final normalizedLocal =
        localDigits.startsWith('0') && localDigits.length > 1
        ? localDigits.substring(1)
        : localDigits;
    final dial = _normalizeCountryDialCode(countryDialCode);
    return '$dial$normalizedLocal';
  }

  @override
  void dispose() {
    nameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
