/// Build-time configuration.
///
///   flutter run --dart-define=KYC_API_BASE_URL=https://api.yourbank.com.bd
///
/// When KYC_API_BASE_URL is empty the app runs in demo mode and fakes the
/// submission. In production, take the bearer token from your login session,
/// not from --dart-define.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('KYC_API_BASE_URL');
  static const apiToken = String.fromEnvironment('KYC_API_TOKEN');

  static bool get isDemo => apiBaseUrl.isEmpty;
}
