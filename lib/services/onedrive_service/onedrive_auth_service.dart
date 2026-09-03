import 'package:msal_auth/msal_auth.dart';

class OneDriveAuthException implements Exception {
  OneDriveAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Wraps `msal_auth` to get a Microsoft Graph access token with
/// `Files.ReadWrite` scope, so [OneDriveExcelService] can read/write the
/// user's OneDrive/SharePoint-hosted Excel file.
///
/// ============================================================
/// SETUP REQUIRED BEFORE THIS WORKS (one-time, done by you, not in code):
/// ============================================================
/// 1. Go to https://portal.azure.com → "App registrations" → "New
///    registration".
///    - Any personal Microsoft account (outlook.com, hotmail.com, etc.)
///      can do this — Azure automatically gives you a default,
///      unmanaged directory the first time you open this page, no actual
///      "organization"/work account required.
///    - Name: anything (e.g. "Fiş Tarayıcı").
///    - Supported account types: "Personal Microsoft accounts only"
///      (matches the `PersonalMicrosoftAccount` audience in
///      assets/msal_config.json — since you're not part of an
///      organization, this is the correct choice, not the "any org
///      directory" options).
/// 2. Copy the "Application (client) ID" shown after registration —
///    paste it into [_clientId] below.
/// 3. Add a platform: "Authentication" → "Add a platform" → "Android" /
///    "iOS":
///    - Android redirect URI format: msauth://<package_name>/<hash>
///      where <hash> = base64(SHA1(your signing certificate)), URL-
///      encoded. Generate it with:
///        keytool -exportcert -alias <your_key_alias> \
///          -keystore <path_to_keystore> | openssl sha1 -binary | \
///          openssl base64
///      then URL-encode the result (e.g. with a "URL encode" tool).
///      Package name is in android/app/build.gradle (`applicationId`).
///    - iOS redirect URI format: msauth.<bundle_id>://auth
///      (bundle_id is in ios/Runner.xcodeproj, e.g. via Xcode's General
///      tab → Bundle Identifier).
///    Paste whichever you need into [_redirectUriAndroid] /
///    [_redirectUriIOS] below.
/// 4. "API permissions" → "Add a permission" → "Microsoft Graph" →
///    "Delegated permissions" → search "Files.ReadWrite" → add it.
///    (No admin consent needed for this delegated, per-user permission.)
/// ============================================================
class OneDriveAuthService {
  OneDriveAuthService._();
  static final OneDriveAuthService instance = OneDriveAuthService._();

  // TODO: fill these in from your own Azure app registration (step 2-3
  // above). Leaving the placeholder will fail fast with a clear error
  // rather than silently misbehaving.
  static const _clientId = '49aee5ab-4312-44bc-84cd-965b17f9d9bc';
  static const _redirectUriAndroid = 'msauth://com.example.receiptscanner/AIqW%2Fh3D%2Fyo%2BBStSPqBZvoQK7Xc%3D';
  static const _redirectUriIOS = 'msauth.com.example.receiptscanner://auth';

  static const _scopes = ['Files.ReadWrite'];

  SingleAccountPca? _pca;

  bool get isConfigured =>
      _clientId != '49aee5ab-4312-44bc-84cd-965b17f9d9bc' &&
      !_redirectUriAndroid.contains('AIqW%2Fh3D%2Fyo%2BBStSPqBZvoQK7Xc%3D');

  Future<SingleAccountPca> _client() async {
    if (!isConfigured) {
      throw OneDriveAuthException(
        'OneDrive bağlantısı henüz yapılandırılmadı. '
        'lib/services/onedrive_service/onedrive_auth_service.dart içindeki '
        'Azure kurulum adımlarını tamamlamanız gerekiyor.',
      );
    }
    return _pca ??= await SingleAccountPca.create(
      clientId: _clientId,
      androidConfig: AndroidConfig(
        configFilePath: 'assets/msal_config.json',
        redirectUri: _redirectUriAndroid,
      ),
      appleConfig: AppleConfig(
        authority: 'https://login.microsoftonline.com/common',
        authorityType: AuthorityType.aad,
      ),
    );
  }

  /// Interactive sign-in (shows the Microsoft login UI). Call this the
  /// first time, or whenever silent token acquisition fails.
  Future<String> signInInteractive() async {
    final pca = await _client();
    try {
      final result = await pca.acquireToken(scopes: _scopes);
      return result.accessToken;
    } on MsalException catch (e) {
      throw OneDriveAuthException('Microsoft ile giriş başarısız: ${e.message}');
    }
  }

  /// Tries to get a fresh access token without showing UI (uses the
  /// cached account from a previous [signInInteractive]). Falls back to
  /// interactive sign-in if there's no cached session.
  Future<String> getAccessToken() async {
    final pca = await _client();
    try {
      final result = await pca.acquireTokenSilent(scopes: _scopes);
      return result.accessToken;
    } on MsalException {
      return signInInteractive();
    }
  }

  Future<bool> isSignedIn() async {
    if (!isConfigured) return false;
    final pca = await _client();
    try {
      await pca.currentAccount;
      return true;
    } on MsalException {
      // Thrown (not null-returned) when there's no signed-in account —
      // verified against msal_auth's actual source.
      return false;
    }
  }

  Future<void> signOut() async {
    final pca = await _client();
    await pca.signOut();
  }
}
