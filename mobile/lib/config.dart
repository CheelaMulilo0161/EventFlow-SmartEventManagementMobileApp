class AppConfig {
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.19.25.191:3000',
  );

  static const String appName = 'EventFlow';
  static const String demoPassword = 'Password123!';
}
