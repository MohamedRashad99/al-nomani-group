import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_cubit.dart';
import 'features/auth/login_page.dart';
import 'features/backup/backup_page.dart';
import 'features/collections/collections_page.dart';
import 'features/customers/customers_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/import/import_page.dart';
import 'features/more/more_page.dart';
import 'features/outstanding/outstanding_page.dart';
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
      if (loggedIn && state.matchedLocation != '/forbidden') {
        if (state.matchedLocation == '/import' &&
            !{
              AppPermission.productsCreate,
              AppPermission.customersCreate,
              AppPermission.inventoryCreate,
            }.any(auth.state.session!.can)) {
          return '/forbidden';
        }
        final required = _requiredPermission(state.matchedLocation);
        if (required != null && !auth.state.session!.can(required)) {
          return '/forbidden';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/forbidden', builder: (_, _) => const _ForbiddenPage()),
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(path: '/products', builder: (_, _) => const ProductsPage()),
      GoRoute(path: '/inventory', builder: (_, _) => const InventoryPage()),
      GoRoute(path: '/import', builder: (_, _) => const ImportPage()),
      GoRoute(
        path: '/customers',
        builder: (_, _) => const CustomersPage(),
        routes: [
          GoRoute(
            path: ':id/statement',
            builder: (_, state) => CustomerStatementRoutePage(
              customerId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/sales',
        builder: (_, _) => const SalesPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const NewSalePage()),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                SaleDetailPage(saleId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: '/collections', builder: (_, _) => const CollectionsPage()),
      GoRoute(path: '/outstanding', builder: (_, _) => const OutstandingPage()),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
      GoRoute(path: '/users', builder: (_, _) => const UsersPage()),
      GoRoute(path: '/backup', builder: (_, _) => const BackupPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/more', builder: (_, _) => const MorePage()),
    ],
  );
}

String? _requiredPermission(String location) {
  if (location.startsWith('/products')) return AppPermission.productsView;
  if (location.startsWith('/inventory')) return AppPermission.inventoryView;
  if (location == '/sales/new') return AppPermission.salesCreate;
  if (location.startsWith('/sales')) return AppPermission.salesView;
  if (location.startsWith('/customers')) return AppPermission.customersView;
  if (location.startsWith('/collections')) {
    return AppPermission.collectionsView;
  }
  if (location.startsWith('/outstanding')) {
    return AppPermission.outstandingView;
  }
  if (location.startsWith('/reports')) return AppPermission.reportsView;
  if (location.startsWith('/users')) return AppPermission.usersView;
  if (location.startsWith('/backup')) return AppPermission.backupView;
  if (location.startsWith('/settings')) return AppPermission.settingsView;
  return null;
}

class _ForbiddenPage extends StatelessWidget {
  const _ForbiddenPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 52),
              const SizedBox(height: 16),
              const Text(
                'ليست لديك صلاحية لفتح هذه الصفحة.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('العودة إلى لوحة التحكم'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoRouterRefresh extends ChangeNotifier {
  GoRouterRefresh(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
