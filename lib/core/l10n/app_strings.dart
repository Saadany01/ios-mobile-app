import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class AppStrings {
  AppStrings(this._locale);
  final Locale _locale;

  static AppStrings of(BuildContext context) {
    return AppStrings(Localizations.localeOf(context));
  }

  String get _lang => _locale.languageCode;

  // ── Auth ────────────────────────────────────────────────────────────
  String get welcomeBack    => _t('Welcome back', 'Bienvenido', 'Bon retour', 'مرحباً بعودتك');
  String get emailAddress   => _t('Email address', 'Correo electrónico', 'Adresse email', 'البريد الإلكتروني');
  String get password       => _t('Password', 'Contraseña', 'Mot de passe', 'كلمة المرور');
  String get forgotPassword => _t('Forgot password?', '¿Olvidaste tu contraseña?', 'Mot de passe oublié?', 'نسيت كلمة المرور؟');
  String get login          => _t('Login', 'Iniciar sesión', 'Connexion', 'تسجيل الدخول');
  String get noAccount      => _t("Don't have an account?", '¿No tienes cuenta?', "Pas de compte?", 'ليس لديك حساب؟');
  String get signUp         => _t('Sign up', 'Registrarse', "S'inscrire", 'إنشاء حساب');
  String get signOut        => _t('Sign out', 'Cerrar sesión', 'Se déconnecter', 'تسجيل الخروج');
  String get logout         => _t('Logout', 'Cerrar sesión', 'Déconnexion', 'تسجيل الخروج');
  String get createAccount  => _t('Create Account', 'Crear cuenta', 'Créer un compte', 'إنشاء حساب');
  String get joinHearMySign => _t('Join HearMySign', 'Únete a HearMySign', 'Rejoindre HearMySign', 'انضم إلى HearMySign');
  String get fullName       => _t('Full Name', 'Nombre completo', 'Nom complet', 'الاسم الكامل');
  String get enterFullName  => _t('Enter your full name', 'Ingresa tu nombre completo', 'Entrez votre nom complet', 'أدخل اسمك الكامل');
  String get confirmPassword      => _t('Confirm Password', 'Confirmar contraseña', 'Confirmer le mot de passe', 'تأكيد كلمة المرور');
  String get confirmPasswordHint  => _t('Confirm your password', 'Confirma tu contraseña', 'Confirmez votre mot de passe', 'أعد إدخال كلمة المرور');
  String get createPasswordHint   => _t('Create a password (min 8 characters)', 'Crea una contraseña (mín 8 caracteres)', 'Créez un mot de passe (min 8 caractères)', 'أنشئ كلمة مرور (8 أحرف على الأقل)');
  String get phoneNumber    => _t('Phone Number', 'Número de teléfono', 'Numéro de téléphone', 'رقم الهاتف');
  String get typePhoneNumber => _t('Type your phone number', 'Ingresa tu número', 'Entrez votre numéro', 'أدخل رقم هاتفك');
  String get verifyPhone    => _t('Verify Phone', 'Verificar teléfono', 'Vérifier le téléphone', 'التحقق من الهاتف');
  String get phoneVerified  => _t('Phone Verified', 'Teléfono verificado', 'Téléphone vérifié', 'تم التحقق من الهاتف');
  String get sendingCode    => _t('Sending Code...', 'Enviando código...', 'Envoi du code...', 'جارٍ الإرسال...');
  String get verifyingCode  => _t('Verifying...', 'Verificando...', 'Vérification...', 'جارٍ التحقق...');
  String get verify         => _t('Verify', 'Verificar', 'Vérifier', 'تحقق');
  String get smsCode        => _t('SMS Code', 'Código SMS', 'Code SMS', 'رمز SMS');
  String get enter6DigitCode => _t('Enter 6-digit code', 'Ingresa código de 6 dígitos', 'Entrez le code à 6 chiffres', 'أدخل الرمز المكون من 6 أرقام');
  String get verifyPhoneNumber => _t('Verify Phone Number', 'Verificar número de teléfono', 'Vérifier le numéro de téléphone', 'التحقق من رقم الهاتف');
  String get phoneVerifiedSuccess => _t('Phone number verified successfully', 'Número verificado con éxito', 'Numéro vérifié avec succès', 'تم التحقق من رقم الهاتف بنجاح');
  String get accountCreatedSuccess => _t('Account created successfully!', '¡Cuenta creada!', 'Compte créé!', 'تم إنشاء الحساب بنجاح!');
  String get alreadyHaveAccount => _t('Already have an account? ', '¿Ya tienes cuenta? ', 'Vous avez un compte? ', 'لديك حساب بالفعل؟ ');
  String get signIn         => _t('Sign in', 'Iniciar sesión', 'Se connecter', 'تسجيل الدخول');
  String get agreeToTerms   => _t('I agree to the ', 'Acepto los ', "J'accepte les ", 'أوافق على ');
  String get termsOfService => _t('Terms of Service', 'Términos de servicio', "Conditions d'utilisation", 'شروط الخدمة');
  String get andConnector   => _t(' and ', ' y ', ' et ', ' و ');
  String get resetPassword  => _t('Reset Password', 'Restablecer contraseña', 'Réinitialiser le mot de passe', 'إعادة تعيين كلمة المرور');
  String get yourEmail      => _t('Your email', 'Tu correo', 'Votre email', 'بريدك الإلكتروني');
  String get send           => _t('Send', 'Enviar', 'Envoyer', 'إرسال');
  String get passwordResetSent => _t('Password reset email sent. Check your inbox.', 'Correo de restablecimiento enviado.', 'Email de réinitialisation envoyé.', 'تم إرسال رابط إعادة تعيين كلمة المرور. تحقق من بريدك.');

  // ── Navigation ──────────────────────────────────────────────────────
  String get communication  => _t('Communication', 'Comunicación', 'Communication', 'التواصل');
  String get directMessages => _t('Direct Messages', 'Mensajes directos', 'Messages directs', 'الرسائل المباشرة');
  String get settings       => _t('Settings', 'Configuración', 'Paramètres', 'الإعدادات');

  // ── Contacts / Calls ────────────────────────────────────────────────
  String get contacts        => _t('Contacts', 'Contactos', 'Contacts', 'جهات الاتصال');
  String get calls           => _t('Calls', 'Llamadas', 'Appels', 'المكالمات');
  String get searchContacts  => _t('Search contacts...', 'Buscar contactos...', 'Rechercher...', 'البحث عن جهات الاتصال...');
  String get noContacts      => _t('No contacts yet', 'Sin contactos', 'Pas de contacts', 'لا توجد جهات اتصال');

  // ── Chat ────────────────────────────────────────────────────────────
  String get writeMessage    => _t('Write a message...', 'Escribe un mensaje...', 'Écrire un message...', 'اكتب رسالة...');
  String get noMessages      => _t('No messages yet', 'Sin mensajes', 'Pas de messages', 'لا توجد رسائل');
  String get friends         => _t('Friends', 'Amigos', 'Amis', 'الأصدقاء');
  String get addFriend       => _t('Add Friend', 'Agregar amigo', 'Ajouter un ami', 'إضافة صديق');
  String get friendUsername  => _t('Friend Username', 'Nombre de usuario', "Nom d'utilisateur", 'اسم المستخدم للصديق');
  String get requests        => _t('Requests', 'Solicitudes', 'Demandes', 'الطلبات');
  String get noFriendReqs    => _t('No friend requests', 'Sin solicitudes', 'Pas de demandes', 'لا توجد طلبات صداقة');
  String get noConversationsYet => _t('No conversations yet', 'Sin conversaciones', 'Pas de conversations', 'لا توجد محادثات بعد');
  String get addFriendsHint  => _t('Add friends and start chatting from the top-right buttons.', 'Agrega amigos y comienza a chatear.', 'Ajoutez des amis et discutez.', 'أضف أصدقاء وابدأ المحادثة من الأزرار في الأعلى.');
  String get pleaseLogIn     => _t('Please log in', 'Por favor inicia sesión', 'Veuillez vous connecter', 'يرجى تسجيل الدخول');

  // ── Settings ────────────────────────────────────────────────────────
  String get manageAccount      => _t('Manage your account', 'Gestiona tu cuenta', 'Gérez votre compte', 'إدارة حسابك');
  String get account            => _t('ACCOUNT', 'CUENTA', 'COMPTE', 'الحساب');
  String get security           => _t('SECURITY', 'SEGURIDAD', 'SÉCURITÉ', 'الأمان');
  String get preferences        => _t('PREFERENCES', 'PREFERENCIAS', 'PRÉFÉRENCES', 'التفضيلات');
  String get about              => _t('ABOUT', 'ACERCA DE', 'À PROPOS', 'حول');
  String get profileInformation => _t('Profile Information', 'Información de perfil', 'Informations du profil', 'معلومات الملف الشخصي');
  String get status             => _t('Status', 'Estado', 'Statut', 'الحالة');
  String get changePassword     => _t('Change Password', 'Cambiar contraseña', 'Changer le mot de passe', 'تغيير كلمة المرور');
  String get language           => _t('Language', 'Idioma', 'Langue', 'اللغة');
  String get theme              => _t('Theme', 'Tema', 'Thème', 'المظهر');
  String get darkMode           => _t('Dark Mode', 'Modo oscuro', 'Mode sombre', 'الوضع الليلي');
  String get darkThemeEnabled   => _t('Dark theme enabled', 'Tema oscuro activado', 'Thème sombre activé', 'الوضع الليلي مفعّل');
  String get lightThemeEnabled  => _t('Light theme enabled', 'Tema claro activado', 'Thème clair activé', 'الوضع النهاري مفعّل');
  String get accessibility      => _t('Accessibility', 'Accesibilidad', 'Accessibilité', 'إمكانية الوصول');
  String get configure          => _t('Configure', 'Configurar', 'Configurer', 'تهيئة');
  String get aboutApp           => _t('About App', "Acerca de la app", "À propos de l'app", 'حول التطبيق');
  String get helpSupport        => _t('Help & Support', 'Ayuda y soporte', 'Aide et support', 'المساعدة والدعم');
  String get privacyPolicy      => _t('Privacy Policy', 'Política de privacidad', 'Politique de confidentialité', 'سياسة الخصوصية');
  String get authenticatorApp   => _t('Authenticator App', 'App autenticador', 'App authentificateur', 'تطبيق المصادقة');
  String get trustedDevices     => _t('Trusted Devices', 'Dispositivos de confianza', 'Appareils de confiance', 'الأجهزة الموثوقة');
  String get thisDeviceActive   => _t('This device • Active now', 'Este dispositivo • Activo', 'Cet appareil • Actif', 'هذا الجهاز • نشط الآن');
  String get checkingStatus     => _t('Checking status...', 'Verificando estado...', 'Vérification...', 'جارٍ التحقق من الحالة...');
  String get onForLogin         => _t('On for login', 'Activado', 'Activé', 'مفعّل لتسجيل الدخول');
  String get offForLoginSaved   => _t('Off for login (configuration saved)', 'Desactivado (guardado)', 'Désactivé (sauvegardé)', 'معطّل (الإعدادات محفوظة)');
  String get notConfiguredYet   => _t('Not configured yet', 'No configurado', 'Pas configuré', 'لم يتم التهيئة بعد');
  String get setStatus          => _t('Set Status', 'Establecer estado', 'Définir le statut', 'تعيين الحالة');
  String get aslServer          => _t('ASL Server', 'Servidor ASL', 'Serveur ASL', 'خادم ASL');
  String get serverUrl          => _t('Server URL', 'URL del servidor', 'URL du serveur', 'رابط الخادم');

  // ── Presence status labels ───────────────────────────────────────────
  String get presenceOnline  => _t('Online', 'En línea', 'En ligne', 'متصل');
  String get presenceIdle    => _t('Idle', 'Ausente', 'Inactif', 'غير نشط');
  String get presenceDnd     => _t('Do Not Disturb', 'No molestar', 'Ne pas déranger', 'لا تزعجني');
  String get presenceOffline => _t('Offline', 'Desconectado', 'Hors ligne', 'غير متصل');

  // ── Dialogs / actions ───────────────────────────────────────────────
  String get logoutConfirmTitle   => _t('Logout', 'Cerrar sesión', 'Déconnexion', 'تسجيل الخروج');
  String get logoutConfirmBody    => _t('Are you sure you want to logout?', '¿Seguro que quieres cerrar sesión?', 'Voulez-vous vraiment vous déconnecter?', 'هل أنت متأكد أنك تريد تسجيل الخروج؟');
  String get changePasswordTitle  => _t('Change Password', 'Cambiar contraseña', 'Changer le mot de passe', 'تغيير كلمة المرور');
  String get currentPassword      => _t('Current Password', 'Contraseña actual', 'Mot de passe actuel', 'كلمة المرور الحالية');
  String get newPassword          => _t('New Password', 'Nueva contraseña', 'Nouveau mot de passe', 'كلمة المرور الجديدة');
  String get change               => _t('Change', 'Cambiar', 'Changer', 'تغيير');
  String get passwordChangedSuccess => _t('Password changed successfully', 'Contraseña cambiada con éxito', 'Mot de passe modifié avec succès', 'تم تغيير كلمة المرور بنجاح');
  String get accessibilityComingSoon => _t('Accessibility settings coming soon', 'Accesibilidad próximamente', 'Accessibilité bientôt disponible', 'إعدادات إمكانية الوصول قريباً');
  String get helpCenterComingSoon => _t('Help center coming soon', 'Centro de ayuda próximamente', 'Centre d\'aide bientôt', 'مركز المساعدة قريباً');
  String get deviceManagementComingSoon => _t('Device management coming soon', 'Gestión de dispositivos próximamente', 'Gestion des appareils bientôt', 'إدارة الأجهزة قريباً');
  String get openingPrivacyPolicy => _t('Opening privacy policy...', 'Abriendo política de privacidad...', 'Ouverture de la politique...', 'فتح سياسة الخصوصية...');

  // ── Profile Information ──────────────────────────────────────────────
  String get displayName       => _t('Display Name', 'Nombre para mostrar', "Nom d'affichage", 'الاسم المعروض');
  String get username          => _t('Username', 'Nombre de usuario', "Nom d'utilisateur", 'اسم المستخدم');
  String get email             => _t('Email', 'Correo electrónico', 'Email', 'البريد الإلكتروني');
  String get noEmailOnAccount  => _t('No email on this account', 'Sin correo en esta cuenta', "Pas d'email sur ce compte", 'لا يوجد بريد إلكتروني لهذا الحساب');
  String get noVerifiedPhone   => _t('No verified phone number', 'Sin número verificado', 'Pas de numéro vérifié', 'لا يوجد رقم هاتف محقق');
  String get hide              => _t('Hide', 'Ocultar', 'Masquer', 'إخفاء');
  String get reveal            => _t('Reveal', 'Revelar', 'Révéler', 'كشف');
  String get dangerZone        => _t('Danger Zone', 'Zona de peligro', 'Zone de danger', 'منطقة الخطر');
  String get deleteAccountPermanently => _t('Delete your account permanently.', 'Elimina tu cuenta permanentemente.', 'Supprimez votre compte définitivement.', 'احذف حسابك بشكل دائم.');
  String get deleteAccount     => _t('Delete Account', 'Eliminar cuenta', 'Supprimer le compte', 'حذف الحساب');
  String get deleting          => _t('Deleting...', 'Eliminando...', 'Suppression...', 'جارٍ الحذف...');
  String get deleteConfirmation => _t('This action is permanent. Type DELETE to confirm.', 'Esta acción es permanente. Escribe DELETE para confirmar.', 'Cette action est permanente. Tapez DELETE pour confirmer.', 'هذا الإجراء دائم. اكتب DELETE للتأكيد.');
  String get typeDeleteToConfirm => _t('Type DELETE', 'Escribe DELETE', 'Tapez DELETE', 'اكتب DELETE');
  String get displayNameUpdated => _t('Display name updated.', 'Nombre actualizado.', 'Nom mis à jour.', 'تم تحديث الاسم المعروض.');
  String get usernameUpdated   => _t('Username updated.', 'Usuario actualizado.', "Nom d'utilisateur mis à jour.", 'تم تحديث اسم المستخدم.');
  String get profilePictureUpdated => _t('Profile picture updated.', 'Foto actualizada.', 'Photo mise à jour.', 'تم تحديث صورة الملف الشخصي.');
  String get accountDeleted    => _t('Account deleted.', 'Cuenta eliminada.', 'Compte supprimé.', 'تم حذف الحساب.');
  String get noDisplayNameChanges => _t('No display name changes to save.', 'Sin cambios en el nombre.', 'Pas de changements.', 'لا توجد تغييرات في الاسم المعروض.');
  String get noUsernameChanges => _t('No username changes to save.', 'Sin cambios en el usuario.', "Pas de changements.", 'لا توجد تغييرات في اسم المستخدم.');

  // ── Call ────────────────────────────────────────────────────────────
  String get connecting     => _t('Connecting...', 'Conectando...', 'Connexion...', 'جارٍ الاتصال...');
  String get callEnded      => _t('Call ended', 'Llamada terminada', 'Appel terminé', 'انتهت المكالمة');
  String get incomingCall   => _t('Incoming call', 'Llamada entrante', 'Appel entrant', 'مكالمة واردة');

  // ── Misc ────────────────────────────────────────────────────────────
  String get save    => _t('Save', 'Guardar', 'Enregistrer', 'حفظ');
  String get cancel  => _t('Cancel', 'Cancelar', 'Annuler', 'إلغاء');
  String get confirm => _t('Confirm', 'Confirmar', 'Confirmer', 'تأكيد');
  String get yes     => _t('Yes', 'Sí', 'Oui', 'نعم');
  String get no      => _t('No', 'No', 'Non', 'لا');
  String get close   => _t('Close', 'Cerrar', 'Fermer', 'إغلاق');
  String get remove  => _t('Remove', 'Eliminar', 'Supprimer', 'حذف');
  String get turnOff => _t('Turn Off', 'Desactivar', 'Désactiver', 'إيقاف');
  String get turnOn  => _t('Turn On', 'Activar', 'Activer', 'تشغيل');

  String _t(String en, String es, String fr, String ar) {
    switch (_lang) {
      case 'es': return es;
      case 'fr': return fr;
      case 'ar': return ar;
      default:   return en;
    }
  }
}
