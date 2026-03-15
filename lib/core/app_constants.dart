class ApiConstants {
  // ── Uncomment the one matching your setup ────────────────────────────────
  // Physical Android (same WiFi) — run `ipconfig` to get PC IP
  static const String baseUrl = 'http://192.168.1.6:8000/api/v1'; // ← change IP
  // Android Emulator
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  // iOS Simulator / Flutter Web
  // static const String baseUrl = 'http://localhost:8000/api/v1';

  // ── Auth ───────────────────────────────────────────────────────────────────
  static const String register = '/auth/register';
  static const String login    = '/auth/login';
  static const String me       = '/auth/me';

  // ── Issues ─────────────────────────────────────────────────────────────────
  static const String issues          = '/issues';
  static const String escalatedIssues = '/issues/escalated/list';

  // ── Verifications ──────────────────────────────────────────────────────────
  static const String verifications = '/verifications';

  // ── Dashboard ─────────────────────────────────────────────────────────────
  static const String leaderDashboard  = '/dashboard/leader';
  static const String adminDashboard   = '/dashboard/admin';
  static const String citizenDashboard = '/dashboard/citizen';
  static const String users            = '/dashboard/users';

  // ── Polling ────────────────────────────────────────────────────────────────
  static const int pollingIntervalSeconds = 10;
}

class AppConstants {
  static const String appName  = 'LokAI';
  static const String tagline  = 'Local Leadership Decision Intelligence';
  static const String tokenKey = 'auth_token';
  static const String roleKey  = 'user_role';
  static const String userIdKey   = 'user_id';
  static const String userNameKey = 'user_name';
}

class IssueStatus {
  static const String open        = 'OPEN';
  static const String resolvedL1  = 'RESOLVED_L1';
  static const String resolvedL2  = 'RESOLVED_L2';
  static const String escalated   = 'ESCALATED';
  static const String closed      = 'CLOSED';
}