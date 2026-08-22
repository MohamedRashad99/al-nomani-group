import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_cubit.dart';
import 'features/auth/login_page.dart';
import 'features/backup/backup_page.dart';
import 'features/collections/collections_page.dart';
import 'features/customers/customers_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/products/products_page.dart';
import 'features/reports/reports_page.dart';
import 'features/sales/sales_page.dart';
import 'features/settings/settings_page.dart';
import 'features/users/users_page.dart';

GoRouter createRouter(AuthCubit auth) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: GoRouterRefresh(auth.stream),
    redirect: (context, state) {
      final loggedIn = auth.state.isAuthenticated;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(path: '/products', builder: (_, _) => const ProductsPage()),
      GoRoute(path: '/inventory', builder: (_, _) => const InventoryPage()),
      GoRoute(path: '/customers', builder: (_, _) => const CustomersPage()),
      GoRoute(path: '/sales', builder: (_, _) => const SalesPage()),
      GoRoute(path: '/collections', builder: (_, _) => const CollectionsPage()),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
      GoRoute(path: '/users', builder: (_, _) => const UsersPage()),
      GoRoute(path: '/backup', builder: (_, _) => const BackupPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    ],
  );
}

class GoRouterRefresh extends ChangeNotifier {
  GoRouterRefresh(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
