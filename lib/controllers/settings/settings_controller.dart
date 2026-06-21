import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/chat_service.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required AuthService authService,
    required ChatService chatService,
  }) : _authService = authService,
       _chatService = chatService {
    _loadTotpStatus();
  }

  final AuthService _authService;
  final ChatService _chatService;
  final ImagePicker _imagePicker = ImagePicker();

  bool _notificationsEnabled = true;
  String _languageCode = 'en';
  bool _isTotpEnabled = false;
  bool _hasTotpConfiguration = false;
  bool _isLoadingTotpStatus = true;
  bool _isTotpSetupBusy = false;
  String? _pendingTotpSecret;

  bool get notificationsEnabled => _notificationsEnabled;
  String get languageCode => _languageCode;
  bool get isTotpEnabled => _isTotpEnabled;
  bool get hasTotpConfiguration => _hasTotpConfiguration;
  bool get isLoadingTotpStatus => _isLoadingTotpStatus;
  bool get isTotpSetupBusy => _isTotpSetupBusy;
  String? get pendingTotpSecret => _pendingTotpSecret;
  String? get pendingTotpUri {
    final secret = _pendingTotpSecret;
    if (secret == null || secret.isEmpty) return null;
    return _authService.buildTotpUri(secret: secret);
  }

  User? get currentUser => _authService.currentUser;

  Stream<String?> profilePhotoUrlStream() {
    final user = _authService.currentUser;
    if (user == null) {
      return Stream<String?>.value(null);
    }

    return _authService.userPhotoUrlStream(user.uid);
  }

  Stream<Map<String, dynamic>?> currentUserProfileDataStream() {
    return _authService.currentUserProfileDataStream();
  }

  String get selectedLanguageLabel {
    switch (_languageCode) {
      case 'es': return 'Español';
      case 'fr': return 'Français';
      case 'ar': return 'العربية';
      default:   return 'English';
    }
  }

  Stream<String> currentUserPresenceStatusStream() {
    final user = _authService.currentUser;
    if (user == null) {
      return Stream<String>.value('offline');
    }

    return _authService.userPresenceStatusStream(user.uid);
  }

  Future<String?> updatePresenceStatus(String status) async {
    final user = _authService.currentUser;
    if (user == null) {
      return 'Please log in first.';
    }

    final normalized = _normalizePresenceStatus(status);
    try {
      await _authService.updateCurrentUserPresenceStatus(normalized);
      await _chatService.updatePresenceStatusInFriendships(
        currentUserId: user.uid,
        status: normalized,
      );
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to update presence status';
    } on FirebaseException catch (e) {
      return e.message ?? 'Failed to update presence status';
    } catch (_) {
      return 'Failed to update presence status';
    }
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void setLanguage(String code) {
    _languageCode = code;
    notifyListeners();
  }

  Future<String?> updateDisplayName(String value) async {
    if (value.trim().isEmpty) {
      return 'Display name cannot be empty.';
    }

    try {
      await _authService.updateDisplayName(value);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to update profile';
    } catch (_) {
      return 'Failed to update profile';
    }
  }

  Future<String?> updateUsername(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'Username cannot be empty.';
    }

    try {
      await _authService.updateUsername(normalized);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-username':
          return 'Username must be 3 to 20 characters using lowercase letters, numbers, or underscore.';
        case 'username-already-in-use':
          return 'This username is already taken.';
        default:
          return e.message ?? 'Failed to update username';
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Permission denied while updating username. Please check Firestore rules for users/{uid}.';
      }
      return e.message ?? 'Failed to update username';
    } catch (_) {
      return 'Failed to update username';
    }
  }

  Future<String?> pickAndUploadProfilePhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
      );

      if (picked == null) {
        return 'cancelled';
      }

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        return 'Could not read the selected image.';
      }

      final contentType = _imageContentType(picked.name);
      await _authService.uploadProfilePhotoBytes(
        bytes,
        fileName: picked.name,
        contentType: contentType,
      );

      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to upload profile photo';
    } on FirebaseException catch (e) {
      switch (e.code) {
        case 'cloudinary-config-missing':
          return 'Cloudinary is not configured. Please contact support.';
        case 'cloudinary-cloud-name-invalid':
          return e.message ??
              'Cloudinary cloud name is invalid. Check CLOUDINARY_CLOUD_NAME.';
        case 'cloudinary-preset-not-found':
          return e.message ??
              'Cloudinary upload preset was not found. Check CLOUDINARY_UPLOAD_PRESET.';
        case 'cloudinary-preset-not-unsigned':
          return e.message ??
              'Cloudinary upload preset must be unsigned for app uploads.';
        case 'cloudinary-unsigned-disallowed-parameter':
          return e.message ??
              'Cloudinary rejected unsigned upload parameters. Please restart the app and try again.';
        case 'cloudinary-unauthorized':
          return e.message ??
              'Cloudinary rejected credentials/upload permissions. Check cloud name and upload preset.';
        case 'invalid-content-type':
          return 'Please choose a JPG, PNG, WEBP, GIF, HEIC, or HEIF image.';
        case 'image-too-large':
          return 'Image is too large. Please choose one under 3 MB.';
        case 'network-request-failed':
          return 'Network issue while uploading the image. Please try again.';
        case 'cloudinary-invalid-response':
          return 'Upload succeeded but image URL was invalid. Please try again.';
        default:
          break;
      }

      return e.message ?? 'Failed to upload profile photo';
    } catch (_) {
      return 'Failed to upload profile photo';
    }
  }

  Future<void> reloadCurrentUser() async {
    await _authService.reloadCurrentUser();
    notifyListeners();
  }

  Future<String?> updatePhotoUrl(String value) async {
    final url = value.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      final isValid =
          uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      if (!isValid) {
        return 'Enter a valid image URL starting with http or https.';
      }
    }

    try {
      await _authService.updatePhotoUrl(url.isEmpty ? null : url);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to update profile photo';
    } catch (_) {
      return 'Failed to update profile photo';
    }
  }

  Future<String?> removePhotoUrl() async {
    try {
      await _authService.updatePhotoUrl(null);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to remove profile photo';
    } catch (_) {
      return 'Failed to remove profile photo';
    }
  }

  Future<String?> deleteAccount() async {
    try {
      await _authService.deleteCurrentUserAccount();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _deleteAccountMessage(e);
    } catch (_) {
      return 'Failed to delete account';
    }
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (newPassword != confirmPassword) {
      return 'Passwords do not match';
    }
    if (newPassword.length < 8) {
      return 'Password must be at least 8 characters';
    }

    try {
      await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _passwordChangeMessage(e);
    } catch (_) {
      return 'Failed to change password';
    }
  }

  Future<String?> beginTotpSetup() async {
    _setTotpSetupBusy(true);
    try {
      _pendingTotpSecret = _authService.generateTotpSecret();
      notifyListeners();
      return null;
    } catch (_) {
      return 'Failed to prepare authenticator setup.';
    } finally {
      _setTotpSetupBusy(false);
    }
  }

  Future<String?> confirmTotpSetup(String code) async {
    final secret = _pendingTotpSecret;
    if (secret == null || secret.isEmpty) {
      return 'Please start setup first.';
    }

    final normalized = code.trim();
    if (normalized.length != 6) {
      return 'Enter the 6-digit authenticator code.';
    }

    _setTotpSetupBusy(true);
    try {
      final isValid = _authService.verifyTotpCodeForSecret(
        secret: secret,
        code: normalized,
      );
      if (!isValid) {
        return 'Invalid authenticator code. Try again.';
      }

      await _authService.enableCurrentUserTotp(secret);
      _isTotpEnabled = true;
      _hasTotpConfiguration = true;
      _pendingTotpSecret = null;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _totpMessage(e, fallback: 'Failed to enable authenticator app.');
    } catch (_) {
      return 'Failed to enable authenticator app.';
    } finally {
      _setTotpSetupBusy(false);
    }
  }

  Future<String?> disableTotp() async {
    _setTotpSetupBusy(true);
    try {
      await _authService.disableCurrentUserTotp();
      _isTotpEnabled = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _totpMessage(e, fallback: 'Failed to disable authenticator app.');
    } catch (_) {
      return 'Failed to disable authenticator app.';
    } finally {
      _setTotpSetupBusy(false);
    }
  }

  Future<String?> enableTotpFromSavedConfiguration(String code) async {
    if (!_hasTotpConfiguration) {
      return 'Authenticator app is not configured yet.';
    }

    final normalized = code.trim();
    if (normalized.length != 6) {
      return 'Enter the 6-digit authenticator code.';
    }

    _setTotpSetupBusy(true);
    try {
      await _authService.verifyCurrentUserTotpCode(
        normalized,
        requireEnabled: false,
      );
      await _authService.enableCurrentUserTotpFromStoredSecret();
      _isTotpEnabled = true;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _totpMessage(e, fallback: 'Failed to enable authenticator app.');
    } catch (_) {
      return 'Failed to enable authenticator app.';
    } finally {
      _setTotpSetupBusy(false);
    }
  }

  Future<String?> removeTotpConfiguration() async {
    _setTotpSetupBusy(true);
    try {
      await _authService.removeCurrentUserTotpConfiguration();
      _isTotpEnabled = false;
      _hasTotpConfiguration = false;
      _pendingTotpSecret = null;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _totpMessage(
        e,
        fallback: 'Failed to remove authenticator configuration.',
      );
    } catch (_) {
      return 'Failed to remove authenticator configuration.';
    } finally {
      _setTotpSetupBusy(false);
    }
  }

  void cancelTotpSetup() {
    if (_pendingTotpSecret == null) return;
    _pendingTotpSecret = null;
    notifyListeners();
  }

  Future<void> _loadTotpStatus() async {
    _setLoadingTotpStatus(true);
    try {
      _hasTotpConfiguration = await _authService
          .hasCurrentUserTotpConfiguration();
      final isEnabled = await _authService.isCurrentUserTotpEnabled();
      _isTotpEnabled = isEnabled && _hasTotpConfiguration;
    } catch (_) {
      _isTotpEnabled = false;
      _hasTotpConfiguration = false;
    } finally {
      _setLoadingTotpStatus(false);
    }
  }

  String _totpMessage(FirebaseAuthException e, {required String fallback}) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Invalid authenticator code. Try again.';
      case 'totp-not-configured':
        return 'Authenticator app is not configured yet.';
      case 'totp-disabled':
        return 'Authenticator app is currently turned off.';
      default:
        return e.message ?? fallback;
    }
  }

  String _passwordChangeMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect';
      case 'weak-password':
        return 'New password is too weak';
      default:
        return e.message ?? 'Failed to change password';
    }
  }

  String _deleteAccountMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'requires-recent-login':
        return 'Please log in again, then try deleting your account.';
      case 'user-not-found':
        return 'No authenticated user found.';
      default:
        return e.message ?? 'Failed to delete account';
    }
  }

  String _imageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  void _setLoadingTotpStatus(bool value) {
    if (_isLoadingTotpStatus == value) return;
    _isLoadingTotpStatus = value;
    notifyListeners();
  }

  void _setTotpSetupBusy(bool value) {
    if (_isTotpSetupBusy == value) return;
    _isTotpSetupBusy = value;
    notifyListeners();
  }

  String _normalizePresenceStatus(String value) {
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

  Future<void> signOut() async {
    final user = _authService.currentUser;
    if (user != null) {
      try {
        await _chatService.updatePresenceStatusInFriendships(
          currentUserId: user.uid,
          status: 'offline',
        );
      } catch (_) {
        // Ignore presence-propagation failures during sign-out.
      }
    }

    await _authService.signOut();
  }
}
