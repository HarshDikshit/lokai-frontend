import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/public/landing_screen.dart';
import '../screens/public/login_screen.dart';
import '../screens/public/register_screen.dart';
import '../screens/citizen/citizen_home_screen.dart';
import '../screens/citizen/submit_issue_screen.dart';
import '../screens/citizen/my_issues_screen.dart';
import '../screens/citizen/issue_detail_screen.dart';
import '../screens/leader/leader_dashboard_screen.dart';
import '../screens/leader/issues_list_screen.dart';
import '../screens/leader/task_management_screen.dart';
import '../screens/authority/authority_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;
      final loc = state.matchedLocation;

      if (!isAuth && !_isPublicRoute(loc)) {
        return '/login';
      }

      if (isAuth && _isPublicRoute(loc) && loc != '/') {
        return _homeForRole(authState.role);
      }

      return null;
    },
    routes: [
      // Public
      GoRoute(path: '/', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // Citizen
      GoRoute(path: '/citizen', builder: (_, __) => const CitizenHomeScreen()),
      GoRoute(path: '/citizen/submit', builder: (_, __) => const SubmitIssueScreen()),
      GoRoute(path: '/citizen/issues', builder: (_, __) => const MyIssuesScreen()),
      GoRoute(
        path: '/issue/:id',
        builder: (_, state) => IssueDetailScreen(issueId: state.pathParameters['id']!),
      ),

      // Leader
      GoRoute(path: '/leader', builder: (_, __) => const LeaderDashboardScreen()),
      GoRoute(path: '/leader/issues', builder: (_, __) => const LeaderIssuesListScreen()),
      GoRoute(path: '/leader/tasks', builder: (_, __) => const TaskManagementScreen()),

      // Higher Authority
      GoRoute(path: '/authority', builder: (_, __) => const AuthorityScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});

bool _isPublicRoute(String loc) => ['/', '/login', '/register'].contains(loc);

String _homeForRole(String? role) {
  switch (role) {
    case 'leader':
      return '/leader';
    case 'higher_authority':
      return '/authority';
    case 'admin':
      return '/leader'; // Admin can use leader view
    default:
      return '/citizen';
  }
}