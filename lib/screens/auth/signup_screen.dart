import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth/signup_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../services/auth_service.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SignupController>(
      create: (context) =>
          SignupController(authService: context.read<AuthService>()),
      child: const _SignUpView(),
    );
  }
}

class _SignUpView extends StatelessWidget {
  const _SignUpView();

  Future<void> _handleSignUp(BuildContext context) async {
    final controller = context.read<SignupController>();
    final message = await controller.signUp();

    if (!context.mounted) return;

    if (message != null) {
      final isWarning =
          message.contains('Terms of Service') ||
          message.contains('verify your phone number');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isWarning ? Colors.orange : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).accountCreatedSuccess),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _handlePhoneVerification(BuildContext context) async {
    final controller = context.read<SignupController>();
    final sendMessage = await controller.sendPhoneVerificationCode();

    if (!context.mounted) return;

    if (sendMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sendMessage), backgroundColor: Colors.red),
      );
      return;
    }

    if (controller.isPhoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).phoneVerifiedSuccess),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    final smsCode = await _showOtpDialog(context);
    if (smsCode == null || !context.mounted) return;

    final verifyMessage = await controller.verifyPhoneCode(smsCode);
    if (!context.mounted) return;

    if (verifyMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(verifyMessage), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).phoneVerifiedSuccess),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<String?> _showOtpDialog(BuildContext context) {
    final otpController = TextEditingController();

    final s = AppStrings.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.verifyPhoneNumber),
        content: TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: s.smsCode,
            hintText: s.enter6DigitCode,
            prefixIcon: const Icon(Icons.sms_outlined),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, otpController.text.trim());
            },
            child: Text(s.verify),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SignupController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final s = AppStrings.of(context);
    final localeCountryCode = Localizations.maybeLocaleOf(
      context,
    )?.countryCode?.toUpperCase();
    final initialCountryCode =
        (localeCountryCode != null && localeCountryCode.length == 2)
        ? localeCountryCode
        : 'US';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.createAccount,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              s.joinHearMySign,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400] : Colors.grey[300],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: controller.formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  s.fullName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller.nameController,
                  decoration: InputDecoration(
                    hintText: s.enterFullName,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: controller.validateName,
                ),
                const SizedBox(height: 20),
                Text(
                  s.username,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller.usernameController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'zzzz_z',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  onChanged: (value) {
                    final lower = value.toLowerCase();
                    if (lower == value) return;
                    controller.usernameController.value = TextEditingValue(
                      text: lower,
                      selection: TextSelection.collapsed(offset: lower.length),
                    );
                  },
                  validator: controller.validateUsername,
                ),
                const SizedBox(height: 20),
                Text(
                  s.emailAddress,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller.emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'email@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: controller.validateEmail,
                ),
                const SizedBox(height: 20),
                Text(
                  s.phoneNumber,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                IntlPhoneField(
                  controller: controller.phoneController,
                  initialCountryCode: initialCountryCode,
                  decoration: InputDecoration(
                    hintText: s.typePhoneNumber,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    suffixIcon: controller.isPhoneVerified
                        ? const Icon(Icons.verified, color: Colors.green)
                        : null,
                  ),
                  disableLengthCheck: false,
                  onChanged: (phone) {
                    controller.onPhoneNumberChanged(
                      localNumber: phone.number,
                      countryDialCode: phone.countryCode,
                    );
                  },
                  onCountryChanged: (country) {
                    controller.onPhoneNumberChanged(
                      localNumber: controller.phoneController.text,
                      countryDialCode: '+${country.dialCode}',
                    );
                  },
                  validator: (_) {
                    return controller.validatePhoneNumber(
                      controller.phoneController.text,
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed:
                        controller.isSendingPhoneCode ||
                            controller.isVerifyingPhoneCode ||
                            controller.isLoading
                        ? null
                        : () => _handlePhoneVerification(context),
                    icon:
                        controller.isSendingPhoneCode ||
                            controller.isVerifyingPhoneCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            controller.isPhoneVerified
                                ? Icons.verified_outlined
                                : Icons.sms_outlined,
                          ),
                    label: Text(
                      controller.isSendingPhoneCode
                          ? s.sendingCode
                          : controller.isVerifyingPhoneCode
                          ? s.verifyingCode
                          : controller.isPhoneVerified
                          ? s.phoneVerified
                          : s.verifyPhone,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  s.password,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller.passwordController,
                  obscureText: controller.obscurePassword,
                  decoration: InputDecoration(
                    hintText: s.createPasswordHint,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        controller.obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: controller.togglePasswordVisibility,
                    ),
                  ),
                  validator: controller.validatePassword,
                ),
                const SizedBox(height: 20),
                Text(
                  s.confirmPassword,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller.confirmPasswordController,
                  obscureText: controller.obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: s.confirmPasswordHint,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        controller.obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: controller.toggleConfirmPasswordVisibility,
                    ),
                  ),
                  validator: controller.validateConfirmPassword,
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: controller.agreedToTerms,
                        onChanged: (value) {
                          controller.setAgreedToTerms(value ?? false);
                        },
                        activeColor: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        children: [
                          Text(
                            s.agreeToTerms,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            s.termsOfService,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? const Color(0xFF00D9D9)
                                  : primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            s.andConnector,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            s.privacyPolicy,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? const Color(0xFF00D9D9)
                                  : primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: controller.isLoading
                        ? null
                        : () => _handleSignUp(context),
                    child: controller.isLoading
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: isDark ? Colors.black : Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(s.createAccount),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s.alreadyHaveAccount,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 15,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        s.signIn,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF00D9D9)
                              : primaryColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
