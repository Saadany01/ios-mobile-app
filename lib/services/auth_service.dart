import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:otp/otp.dart';

import '../core/config/cloudinary_config.dart';

class PhoneVerificationRequest {
  const PhoneVerificationRequest({
    required this.verificationId,
    this.resendToken,
    this.autoCredential,
  });

  final String verificationId;
  final int? resendToken;
  final PhoneAuthCredential? autoCredential;
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Random _random = Random.secure();
  bool _isSecondFactorPendingForSession = false;

  static const int _maxProfileImageBytes = 3 * 1024 * 1024;
  static const Set<String> _allowedImageMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
  };

  static const String _pendingLoginSecondFactorField =
      'pendingLoginSecondFactor';
  static const String _mustChangePasswordField = 'mustChangePassword';
  static const String _totpEnabledField = 'totpEnabled';
  static const String _totpSecretField = 'totpSecret';
  static final RegExp _usernameAllowedPattern = RegExp(r'^[a-z0-9_]{3,20}$');
  static final RegExp _usernameDisallowedChars = RegExp(r'[^a-z0-9_]');

  User? get currentUser => _auth.currentUser;
  bool get isSecondFactorPendingForSession => _isSecondFactorPendingForSession;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Stream<DocumentSnapshot<Map<String, dynamic>>> userDocumentStream(
    String uid,
  ) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Stream<String?> userPhotoUrlStream(String uid) {
    return userDocumentStream(uid).map((snapshot) {
      final data = snapshot.data();
      final photoUrl = (data?['photoURL'] ?? '').toString().trim();
      return photoUrl.isEmpty ? null : photoUrl;
    });
  }

  Stream<String> userPresenceStatusStream(String uid) {
    return userDocumentStream(uid).map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final raw = (data['presenceStatus'] ?? 'online').toString();
      return _normalizePresenceStatus(raw);
    });
  }

  Stream<Map<String, dynamic>?> currentUserProfileDataStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<Map<String, dynamic>?>.value(null);
    }

    return userDocumentStream(user.uid).map((snapshot) => snapshot.data());
  }

  Future<void> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    _isSecondFactorPendingForSession = true;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await ensureUserDocument();
      await markLoginSecondFactorPending();
      return credential;
    } catch (_) {
      _isSecondFactorPendingForSession = false;
      rethrow;
    }
  }

  Future<UserCredential> signUp({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required PhoneAuthCredential phoneCredential,
    String? username,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    await user?.updateDisplayName(name.trim());

    if (user != null) {
      try {
        await user.linkWithCredential(phoneCredential);
      } on FirebaseAuthException {
        await _deleteFreshUser(user);
        rethrow;
      }
    }

    await ensureUserDocument(
      phoneNumber: phoneNumber,
      preferredUsername: username,
    );
    return credential;
  }

  Future<void> ensureUserDocument({
    String? phoneNumber,
    String? preferredUsername,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = _firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    final resolvedPhone = _resolvePhoneNumber(phoneNumber, user.phoneNumber);
    final existingData = snapshot.data() ?? const <String, dynamic>{};

    var username = (existingData['username'] ?? '').toString().trim();
    if (username.isEmpty) {
      final preferred = _preferredUsernameForUser(
        user,
        explicitPreferredUsername: preferredUsername,
      );
      username = await _resolveUniqueUsername(
        preferred,
        currentUserUid: user.uid,
      );
    }

    final sharedData = <String, dynamic>{
      'uid': user.uid,
      'email': (user.email ?? '').trim(),
      'emailLowercase': (user.email ?? '').trim().toLowerCase(),
      'displayName': user.displayName ?? '',
      'username': username,
      'usernameLowercase': username.toLowerCase(),
      'presenceStatus': _normalizePresenceStatus(
        (existingData['presenceStatus'] ?? 'online').toString(),
      ),
      'photoURL': (user.photoURL ?? '').trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (resolvedPhone != null) {
      sharedData['phoneNumber'] = resolvedPhone;
    }

    if (snapshot.exists) {
      await userDoc.set(sharedData, SetOptions(merge: true));
      return;
    }

    await userDoc.set({
      ...sharedData,
      _pendingLoginSecondFactorField: false,
      _mustChangePasswordField: false,
      _totpEnabledField: false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final value = displayName.trim();
    await user.updateDisplayName(value);
    await _firestore.collection('users').doc(user.uid).set({
      'displayName': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await user.reload();
  }

  Future<void> updateUsername(String rawUsername) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final normalized = _normalizeUsername(rawUsername);
    if (!_usernameAllowedPattern.hasMatch(normalized)) {
      throw FirebaseAuthException(
        code: 'invalid-username',
        message:
            'Username must be 3 to 20 characters and use only lowercase letters, numbers, and underscore.',
      );
    }

    final availability = await _usernameOwnerUid(normalized);
    if (availability != null && availability != user.uid) {
      throw FirebaseAuthException(
        code: 'username-already-in-use',
        message: 'This username is already taken.',
      );
    }

    await _firestore.collection('users').doc(user.uid).set({
      'username': normalized,
      'usernameLowercase': normalized.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateCurrentUserPresenceStatus(String rawStatus) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final normalized = _normalizePresenceStatus(rawStatus);
    await _firestore.collection('users').doc(user.uid).set({
      'presenceStatus': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePhotoUrl(String? photoUrl) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final normalized = photoUrl?.trim() ?? '';
    final resolvedUrl = normalized.isEmpty ? null : normalized;

    await user.updatePhotoURL(resolvedUrl);
    await _firestore.collection('users').doc(user.uid).set({
      'photoURL': resolvedUrl ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await user.reload();
  }

  Future<String> uploadProfilePhotoBytes(
    Uint8List bytes, {
    required String fileName,
    String? contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    if (bytes.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-image',
        message: 'Selected image is empty.',
      );
    }

    if (bytes.length > _maxProfileImageBytes) {
      throw FirebaseException(
        plugin: 'cloudinary',
        code: 'image-too-large',
        message: 'Selected image is too large. Maximum allowed size is 3 MB.',
      );
    }

    final cloudName = CloudinaryConfig.cloudName.trim().toLowerCase();
    final uploadPreset = CloudinaryConfig.uploadPreset.trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-config-missing',
        message:
            'Cloudinary config is missing. Provide CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET with --dart-define.',
      );
    }

    final resolvedContentType = _normalizeContentType(contentType, fileName);
    if (!_allowedImageMimeTypes.contains(resolvedContentType)) {
      throw FirebaseException(
        plugin: 'cloudinary',
        code: 'invalid-content-type',
        message:
            'Unsupported image type. Allowed types: jpg, jpeg, png, webp, gif, heic, heif.',
      );
    }

    final publicId = _buildProfilePhotoPublicId(user.uid);
    final safeName = fileName.trim().isEmpty ? 'profile.jpg' : fileName.trim();

    final downloadUrl = await _uploadToCloudinaryWithRetry(
      cloudName: cloudName,
      uploadPreset: uploadPreset,
      publicId: publicId,
      fileBytes: bytes,
      fileName: safeName,
      contentType: resolvedContentType,
    );

    await updatePhotoUrl(downloadUrl);
    await _firestore.collection('users').doc(user.uid).set({
      'photoProvider': 'cloudinary',
      'photoPublicId': publicId,
      'photoUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return downloadUrl;
  }

  String _safeImageExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return '.jpg';
    }

    final rawExtension = fileName.substring(dotIndex).toLowerCase();
    final normalized = rawExtension.replaceAll(RegExp(r'[^a-z0-9.]'), '');
    const allowed = {
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
      '.heic',
      '.heif',
    };

    return allowed.contains(normalized) ? normalized : '.jpg';
  }

  String _buildProfilePhotoPublicId(String uid) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'users/$uid/avatar_$timestamp';
  }

  String _normalizeContentType(String? contentType, String fileName) {
    final normalized = (contentType ?? '').trim().toLowerCase();
    if (normalized.isNotEmpty) {
      final semicolonIndex = normalized.indexOf(';');
      if (semicolonIndex > 0) {
        return normalized.substring(0, semicolonIndex).trim();
      }
      return normalized;
    }

    final extension = _safeImageExtension(fileName);
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<String> _uploadToCloudinaryWithRetry({
    required String cloudName,
    required String uploadPreset,
    required String publicId,
    required Uint8List fileBytes,
    required String fileName,
    required String contentType,
  }) async {
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 500),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2400),
    ];
    FirebaseException? lastRetriableError;

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      try {
        return await _uploadToCloudinaryOnce(
          cloudName: cloudName,
          uploadPreset: uploadPreset,
          publicId: publicId,
          fileBytes: fileBytes,
          fileName: fileName,
          contentType: contentType,
        );
      } on TimeoutException {
        lastRetriableError = FirebaseException(
          plugin: 'cloudinary',
          code: 'network-request-failed',
          message: 'Cloudinary upload timed out. Please try again.',
        );
      } on http.ClientException {
        lastRetriableError = FirebaseException(
          plugin: 'cloudinary',
          code: 'network-request-failed',
          message: 'Network error while uploading image. Please try again.',
        );
      } on FirebaseException catch (e) {
        if (!_isRetriableCloudinaryError(e)) {
          rethrow;
        }
        lastRetriableError = e;
      }
    }

    throw FirebaseException(
      plugin: 'cloudinary',
      code: lastRetriableError?.code ?? 'cloudinary-upload-failed',
      message:
          lastRetriableError?.message ??
          'Failed to upload image to Cloudinary. Please try again.',
    );
  }

  Future<String> _uploadToCloudinaryOnce({
    required String cloudName,
    required String uploadPreset,
    required String publicId,
    required Uint8List fileBytes,
    required String fileName,
    required String contentType,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['public_id'] = publicId
      ..fields['resource_type'] = 'image'
      ..files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

    final response = await request.send().timeout(const Duration(seconds: 30));
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildCloudinaryError(response.statusCode, responseBody);
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      throw FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-invalid-response',
        message: 'Cloudinary returned an invalid response.',
      );
    }

    final secureUrl = (payload['secure_url'] ?? '').toString().trim();
    if (secureUrl.isEmpty) {
      throw FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-invalid-response',
        message: 'Cloudinary did not return a secure image URL.',
      );
    }

    return secureUrl;
  }

  FirebaseException _buildCloudinaryError(int statusCode, String body) {
    final detail = _extractCloudinaryErrorMessage(body);
    final normalizedDetail = detail.toLowerCase();

    if (normalizedDetail.contains('upload preset') &&
        normalizedDetail.contains('not found')) {
      return FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-preset-not-found',
        message:
            'Cloudinary upload preset was not found. Verify CLOUDINARY_UPLOAD_PRESET. ${detail.trim()}'
                .trim(),
      );
    }

    if (normalizedDetail.contains('unsigned') &&
        normalizedDetail.contains('preset')) {
      return FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-preset-not-unsigned',
        message:
            'Cloudinary upload preset must be unsigned for client-side uploads. ${detail.trim()}'
                .trim(),
      );
    }

    if (normalizedDetail.contains('overwrite parameter is not allowed') &&
        normalizedDetail.contains('unsigned upload')) {
      return FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-unsigned-disallowed-parameter',
        message:
            'Unsigned Cloudinary upload rejected disallowed parameters. Please restart the app with latest code and try again. ${detail.trim()}'
                .trim(),
      );
    }

    if (normalizedDetail.contains('invalid cloud_name') ||
        normalizedDetail.contains('unknown cloud_name') ||
        normalizedDetail.contains('cloud name')) {
      return FirebaseException(
        plugin: 'cloudinary',
        code: 'cloudinary-cloud-name-invalid',
        message:
            'Cloudinary cloud name is invalid. Verify CLOUDINARY_CLOUD_NAME. ${detail.trim()}'
                .trim(),
      );
    }

    final prefix = switch (statusCode) {
      400 => 'Cloudinary rejected the upload request.',
      401 || 403 => 'Cloudinary credentials are invalid or unauthorized.',
      413 => 'The selected image is too large for Cloudinary.',
      _ => 'Cloudinary upload failed ($statusCode).',
    };

    final code = switch (statusCode) {
      401 || 403 => 'cloudinary-unauthorized',
      408 || 429 => 'network-request-failed',
      _ when statusCode >= 500 => 'network-request-failed',
      _ => 'cloudinary-upload-failed',
    };

    final message = detail.isEmpty ? prefix : '$prefix $detail';
    return FirebaseException(
      plugin: 'cloudinary',
      code: code,
      message: message,
    );
  }

  String _extractCloudinaryErrorMessage(String body) {
    if (body.trim().isEmpty) return '';

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          return (error['message'] ?? '').toString().trim();
        }
        return (decoded['message'] ?? '').toString().trim();
      }
    } catch (_) {
      // Ignore parse errors and return empty detail.
    }

    return '';
  }

  bool _isRetriableCloudinaryError(FirebaseException e) {
    return e.code == 'network-request-failed';
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> markLoginSecondFactorPending() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _isSecondFactorPendingForSession = true;

    await _firestore.collection('users').doc(user.uid).set({
      _pendingLoginSecondFactorField: true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> completeLoginSecondFactor() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      _pendingLoginSecondFactorField: false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _isSecondFactorPendingForSession = false;
  }

  Future<void> setMustChangePassword(bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      _mustChangePasswordField: value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> isCurrentUserTotpEnabled() async {
    final data = await _readCurrentUserData();
    return data[_totpEnabledField] == true;
  }

  Future<bool> hasCurrentUserTotpConfiguration() async {
    final data = await _readCurrentUserData();
    final secret = (data[_totpSecretField] ?? '').toString().trim();
    return secret.isNotEmpty;
  }

  Future<String?> getCurrentUserTotpSecret() async {
    final data = await _readCurrentUserData();
    final secret = (data[_totpSecretField] ?? '').toString().trim();
    if (secret.isEmpty) return null;
    return secret;
  }

  String generateTotpSecret({int length = 32}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    return List.generate(
      length,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  String buildTotpUri({
    required String secret,
    String issuer = 'Sign Language App',
    String? accountName,
  }) {
    final currentEmail = _auth.currentUser?.email?.trim();
    final resolvedAccount = (accountName ?? currentEmail ?? 'user').trim();
    final safeAccount = resolvedAccount.isEmpty ? 'user' : resolvedAccount;
    final safeIssuer = issuer.trim().isEmpty ? 'Sign Language App' : issuer;
    final label =
        '${Uri.encodeComponent(safeIssuer)}:${Uri.encodeComponent(safeAccount)}';

    return 'otpauth://totp/$label?secret=${Uri.encodeQueryComponent(secret)}&issuer=${Uri.encodeQueryComponent(safeIssuer)}&algorithm=SHA1&digits=6&period=30';
  }

  bool verifyTotpCodeForSecret({
    required String secret,
    required String code,
    int allowedTimeSteps = 1,
  }) {
    final normalizedSecret = secret.trim().toUpperCase();
    final normalizedCode = code.trim();
    if (normalizedSecret.isEmpty || normalizedCode.length != 6) return false;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const stepMs = 30000;

    try {
      for (
        var offset = -allowedTimeSteps;
        offset <= allowedTimeSteps;
        offset++
      ) {
        final generated = OTP.generateTOTPCodeString(
          normalizedSecret,
          nowMs + (offset * stepMs),
          interval: 30,
          length: 6,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );

        if (generated == normalizedCode) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  Future<void> enableCurrentUserTotp(String secret) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final normalizedSecret = secret
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('=', '');
    if (normalizedSecret.length < 16) {
      throw FirebaseAuthException(
        code: 'invalid-totp-secret',
        message: 'Invalid authenticator secret.',
      );
    }

    await _firestore.collection('users').doc(user.uid).set({
      _totpEnabledField: true,
      _totpSecretField: normalizedSecret,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> disableCurrentUserTotp() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    await _firestore.collection('users').doc(user.uid).set({
      _totpEnabledField: false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> enableCurrentUserTotpFromStoredSecret() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final secret = await getCurrentUserTotpSecret();
    if (secret == null || secret.isEmpty) {
      throw FirebaseAuthException(
        code: 'totp-not-configured',
        message: 'Authenticator app is not configured for this account.',
      );
    }

    await _firestore.collection('users').doc(user.uid).set({
      _totpEnabledField: true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeCurrentUserTotpConfiguration() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    await _firestore.collection('users').doc(user.uid).set({
      _totpEnabledField: false,
      _totpSecretField: FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> verifyCurrentUserTotpCode(
    String code, {
    bool requireEnabled = true,
  }) async {
    final data = await _readCurrentUserData();
    final secret = (data[_totpSecretField] ?? '').toString().trim();
    if (secret.isEmpty) {
      throw FirebaseAuthException(
        code: 'totp-not-configured',
        message: 'Authenticator app is not configured for this account.',
      );
    }

    if (requireEnabled && data[_totpEnabledField] != true) {
      throw FirebaseAuthException(
        code: 'totp-disabled',
        message: 'Authenticator app is currently turned off.',
      );
    }

    final isValid = verifyTotpCodeForSecret(secret: secret, code: code);
    if (!isValid) {
      throw FirebaseAuthException(
        code: 'invalid-verification-code',
        message: 'Invalid authenticator code.',
      );
    }
  }

  Future<PhoneVerificationRequest> requestPhoneVerificationCode({
    required String phoneNumber,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final normalized = phoneNumber.trim();
    final completer = Completer<PhoneVerificationRequest>();

    await _auth.verifyPhoneNumber(
      phoneNumber: normalized,
      forceResendingToken: forceResendingToken,
      timeout: timeout,
      verificationCompleted: (credential) {
        if (completer.isCompleted) return;

        final verificationId = credential.verificationId;
        if (verificationId == null) return;

        completer.complete(
          PhoneVerificationRequest(
            verificationId: verificationId,
            resendToken: forceResendingToken,
            autoCredential: credential,
          ),
        );
      },
      verificationFailed: (exception) {
        if (!completer.isCompleted) {
          completer.completeError(exception);
        }
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneVerificationRequest(
              verificationId: verificationId,
              resendToken: resendToken,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneVerificationRequest(
              verificationId: verificationId,
              resendToken: forceResendingToken,
            ),
          );
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        throw FirebaseAuthException(
          code: 'timeout',
          message: 'Phone verification timed out. Please try again.',
        );
      },
    );
  }

  PhoneAuthCredential createPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) {
    return PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
  }

  Future<void> reauthenticateWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    await user.reauthenticateWithCredential(credential);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;

    if (user == null || email == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
    await _firestore.collection('users').doc(user.uid).set({
      _mustChangePasswordField: false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> changePasswordFromActiveSession({
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    await user.updatePassword(newPassword);
    await _firestore.collection('users').doc(user.uid).set({
      _mustChangePasswordField: false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'presenceStatus': 'offline',
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Ignore presence write failures during sign-out.
      }
    }

    _isSecondFactorPendingForSession = false;
    await _auth.signOut();
  }

  Future<void> deleteCurrentUserAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final uid = user.uid;
    await user.delete();
    _isSecondFactorPendingForSession = false;

    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (_) {
      // Ignore cleanup failures after auth account deletion.
    }

    await _auth.signOut();
  }

  Future<PhoneVerificationRequest> requestCurrentUserPhoneVerificationCode({
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final user = _auth.currentUser;
    final phoneNumber = user?.phoneNumber?.trim() ?? '';

    if (phoneNumber.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-phone-number',
        message: 'No verified phone number found for this account.',
      );
    }

    return requestPhoneVerificationCode(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> _readCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No authenticated user found.',
      );
    }

    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    return snapshot.data() ?? const <String, dynamic>{};
  }

  String? _resolvePhoneNumber(String? preferred, String? fallback) {
    final first = preferred?.trim() ?? '';
    if (first.isNotEmpty) return first;

    final second = fallback?.trim() ?? '';
    if (second.isNotEmpty) return second;

    return null;
  }

  String _preferredUsernameForUser(
    User user, {
    String? explicitPreferredUsername,
  }) {
    final explicit = _normalizeUsername(explicitPreferredUsername ?? '');
    if (explicit.isNotEmpty) return explicit;

    final fromDisplayName = _normalizeUsername((user.displayName ?? '').trim());
    if (fromDisplayName.isNotEmpty) return fromDisplayName;

    final email = (user.email ?? '').trim();
    final local = email.contains('@') ? email.split('@').first : email;
    final fromEmail = _normalizeUsername(local);
    if (fromEmail.isNotEmpty) return fromEmail;

    return 'user';
  }

  String _normalizeUsername(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('@')) {
      value = value.substring(1);
    }

    value = value.replaceAll(RegExp(r'\s+'), '_');
    value = value.replaceAll(_usernameDisallowedChars, '');
    value = value.replaceAll(RegExp(r'_+'), '_');
    value = value.replaceAll(RegExp(r'^_+'), '');
    value = value.replaceAll(RegExp(r'_+$'), '');

    if (value.length > 20) {
      value = value.substring(0, 20);
    }

    return value;
  }

  String _normalizePresenceStatus(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'online':
      case 'idle':
      case 'dnd':
      case 'offline':
        return normalized;
      default:
        return 'online';
    }
  }

  Future<String?> _usernameOwnerUid(String normalizedUsername) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection('users')
          .where(
            'usernameLowercase',
            isEqualTo: normalizedUsername.toLowerCase(),
          )
          .limit(1)
          .get();
    } on FirebaseException catch (e) {
      // Some deployments only allow reading the signed-in user's own document.
      // In that setup, uniqueness pre-check cannot run client-side.
      if (e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.id;
  }

  Future<String> _resolveUniqueUsername(
    String preferred, {
    required String currentUserUid,
  }) async {
    var base = _normalizeUsername(preferred);
    if (base.isEmpty) {
      base = 'user';
    }

    if (base.length < 3) {
      base = '${base}usr';
      if (base.length > 20) {
        base = base.substring(0, 20);
      }
    }

    var candidate = base;

    for (var attempt = 0; attempt < 40; attempt++) {
      final ownerUid = await _usernameOwnerUid(candidate);
      if (ownerUid == null || ownerUid == currentUserUid) {
        return candidate;
      }

      final suffix = (_random.nextInt(9000) + 1000).toString();
      final suffixChunk = '_$suffix';
      final maxBaseLength = 20 - suffixChunk.length;
      final truncatedBase = base.length > maxBaseLength
          ? base.substring(0, maxBaseLength)
          : base;
      candidate = '$truncatedBase$suffixChunk';
    }

    final fallbackSuffix = currentUserUid.substring(0, 4).toLowerCase();
    const fallbackPrefix = 'user_';
    final maxPrefixLength = 20 - fallbackSuffix.length;
    final prefix = fallbackPrefix.length > maxPrefixLength
        ? fallbackPrefix.substring(0, maxPrefixLength)
        : fallbackPrefix;
    return '$prefix$fallbackSuffix';
  }

  Future<void> _deleteFreshUser(User user) async {
    try {
      await user.delete();
    } catch (_) {
      // Ignore cleanup failures; Firebase error is still propagated to caller.
    }
  }
}
