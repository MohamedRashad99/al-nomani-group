abstract final class AppPermission {
  static const productsView = 'products.view';
  static const productsCreate = 'products.create';
  static const productsUpdate = 'products.update';
  static const productsDelete = 'products.delete';

  static const inventoryView = 'inventory.view';
  static const inventoryCreate = 'inventory.create';
  static const inventoryAdjust = 'inventory.adjust';

  static const customersView = 'customers.view';
  static const customersCreate = 'customers.create';
  static const customersUpdate = 'customers.update';

  static const salesView = 'sales.view';
  static const salesCreate = 'sales.create';
  static const salesCancel = 'sales.cancel';

  static const collectionsView = 'collections.view';
  static const collectionsCreate = 'collections.create';

  static const reportsView = 'reports.view';
  static const reportsExport = 'reports.export';

  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersUpdate = 'users.update';
  static const usersDisable = 'users.disable';

  static const backupView = 'backup.view';
  static const backupSync = 'backup.sync';
  static const backupRetry = 'backup.retry';
  static const backupFullSync = 'backup.full_sync';

  static const settingsView = 'settings.view';
  static const settingsUpdate = 'settings.update';

  static const outstandingView = 'outstanding.view';
  static const outstandingCreate = 'outstanding.create';

  static const suppliersView = 'suppliers.view';
  static const suppliersCreate = 'suppliers.create';
  static const suppliersUpdate = 'suppliers.update';
  static const suppliersDelete = 'suppliers.delete';

  static const purchasesView = 'purchases.view';
  static const purchasesCreate = 'purchases.create';
  static const purchasesCancel = 'purchases.cancel';

  static const all = <String>[
    productsView,
    productsCreate,
    productsUpdate,
    productsDelete,
    inventoryView,
    inventoryCreate,
    inventoryAdjust,
    customersView,
    customersCreate,
    customersUpdate,
    salesView,
    salesCreate,
    salesCancel,
    collectionsView,
    collectionsCreate,
    reportsView,
    reportsExport,
    usersView,
    usersCreate,
    usersUpdate,
    usersDisable,
    backupView,
    backupSync,
    backupRetry,
    backupFullSync,
    settingsView,
    settingsUpdate,
    outstandingView,
    outstandingCreate,
    suppliersView,
    suppliersCreate,
    suppliersUpdate,
    suppliersDelete,
    purchasesView,
    purchasesCreate,
    purchasesCancel,
  ];
}

abstract final class AppRole {
  static const admin = 'admin';
  static const manager = 'manager';
  static const cashier = 'cashier';
  static const viewer = 'viewer';
}

abstract final class RolePermissions {
  static const Map<String, List<String>> matrix = {
    AppRole.admin: AppPermission.all,
    AppRole.manager: [
      AppPermission.productsView,
      AppPermission.productsCreate,
      AppPermission.productsUpdate,
      AppPermission.inventoryView,
      AppPermission.inventoryCreate,
      AppPermission.inventoryAdjust,
      AppPermission.customersView,
      AppPermission.customersCreate,
      AppPermission.customersUpdate,
      AppPermission.salesView,
      AppPermission.salesCreate,
      AppPermission.salesCancel,
      AppPermission.collectionsView,
      AppPermission.collectionsCreate,
      AppPermission.reportsView,
      AppPermission.reportsExport,
      AppPermission.backupView,
      AppPermission.settingsView,
      AppPermission.outstandingView,
      AppPermission.outstandingCreate,
      AppPermission.suppliersView,
      AppPermission.suppliersCreate,
      AppPermission.suppliersUpdate,
      AppPermission.purchasesView,
      AppPermission.purchasesCreate,
      AppPermission.purchasesCancel,
    ],
    AppRole.cashier: [
      AppPermission.productsView,
      AppPermission.inventoryView,
      AppPermission.customersView,
      AppPermission.customersCreate,
      AppPermission.salesView,
      AppPermission.salesCreate,
      AppPermission.collectionsView,
      AppPermission.collectionsCreate,
      AppPermission.suppliersView,
      AppPermission.purchasesView,
      AppPermission.purchasesCreate,
    ],
    AppRole.viewer: [
      AppPermission.productsView,
      AppPermission.inventoryView,
      AppPermission.customersView,
      AppPermission.salesView,
      AppPermission.collectionsView,
      AppPermission.reportsView,
      AppPermission.outstandingView,
      AppPermission.suppliersView,
      AppPermission.purchasesView,
    ],
  };
}
