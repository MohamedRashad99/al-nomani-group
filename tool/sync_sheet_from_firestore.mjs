import {google} from 'googleapis';
import fs from 'fs';

const PROJECT_ID = 'al-nomani-groub';
const API_KEY = 'AIzaSyBJ-DEr0PrkW1BDKw9bRztmfV8Y1SKtJF0';
const SPREADSHEET_ID = '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I';

function loadServiceAccount() {
  if (process.env.GOOGLE_SERVICE_ACCOUNT_JSON) {
    return JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
  }
  const candidates = [
    'assets/config/google_sheets_sa.json',
    'secrets/google-service-account.json',
    'functions/service-account.json',
    'service-account.json',
  ];
  for (const file of candidates) {
    if (fs.existsSync(file)) {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    }
  }
  throw new Error('Missing Google service account JSON');
}

function firestoreValue(value) {
  if (value == null) return '';
  if (value.stringValue != null) return value.stringValue;
  if (value.integerValue != null) return value.integerValue;
  if (value.doubleValue != null) return String(value.doubleValue);
  if (value.booleanValue != null) return value.booleanValue ? 'نعم' : 'لا';
  if (value.timestampValue != null) return String(value.timestampValue);
  if (value.arrayValue?.values) {
    return value.arrayValue.values.map(firestoreValue);
  }
  if (value.mapValue?.fields) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields).map(([key, nested]) => [
        key,
        firestoreValue(nested),
      ]),
    );
  }
  return '';
}

function decodeDocument(doc) {
  const fields = doc.fields || {};
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, firestoreValue(value)]),
  );
}

async function signInAnonymously() {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({returnSecureToken: true}),
    },
  );
  const data = await response.json();
  if (!data.idToken) {
    throw new Error(`Anonymous auth failed: ${JSON.stringify(data)}`);
  }
  return data.idToken;
}

async function listDocuments(idToken, section) {
  const docs = [];
  let pageToken = '';
  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/companies/al_nomani/${section}`,
    );
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await fetch(url, {
      headers: {Authorization: `Bearer ${idToken}`},
    });
    const data = await response.json();
    if (data.error) {
      if (String(data.error.status || '').includes('NOT_FOUND')) {
        return docs;
      }
      throw new Error(`${section}: ${data.error.message}`);
    }
    for (const doc of data.documents || []) {
      docs.push(decodeDocument(doc));
    }
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return docs;
}

function pick(doc, ...keys) {
  for (const key of keys) {
    if (doc[key] != null && doc[key] !== '') return doc[key];
  }
  return '';
}

function alive(doc) {
  return (
    doc.is_deleted !== true &&
    doc.isDeleted !== true &&
    String(doc.operation || '') !== 'delete'
  );
}

function names(docs, idKey = 'id', nameKey = 'name') {
  const map = {};
  for (const doc of docs) {
    const id = pick(doc, idKey, 'entityId');
    if (id) map[id] = pick(doc, nameKey, 'display_name', 'displayName') || id;
  }
  return map;
}

function table(headers, rows) {
  return [headers, ...rows];
}

async function buildFromCollections(idToken) {
  const [
    customers,
    products,
    categories,
    accounts,
    accountTx,
    sales,
    items,
    collections,
    inventory,
    users,
    settings,
    audits,
    roles,
  ] = await Promise.all([
    listDocuments(idToken, 'customers'),
    listDocuments(idToken, 'products'),
    listDocuments(idToken, 'categories'),
    listDocuments(idToken, 'accounts'),
    listDocuments(idToken, 'account_transactions'),
    listDocuments(idToken, 'sales'),
    listDocuments(idToken, 'sale_items'),
    listDocuments(idToken, 'collections'),
    listDocuments(idToken, 'inventory'),
    listDocuments(idToken, 'users'),
    listDocuments(idToken, 'settings'),
    listDocuments(idToken, 'audit_logs'),
    listDocuments(idToken, 'roles'),
  ]);
  const customerNames = names(customers);
  const productNames = names(products);
  const categoryNames = names(categories);
  const userNames = names(users, 'id', 'display_name');
  const roleNames = names(roles, 'id', 'display_name_ar');
  const liveCustomers = customers.filter(alive);
  const liveProducts = products.filter(alive);
  const liveSales = sales.filter(alive);
  const liveCollections = collections.filter(alive);
  return {
    'نظرة عامة': table(
      ['البيان', 'العدد'],
      [
        ['وقت التحديث', new Date().toISOString()],
        ['التصنيفات', String(categories.filter(alive).length)],
        ['المنتجات', String(liveProducts.length)],
        ['العملاء', String(liveCustomers.length)],
        ['المبيعات', String(liveSales.length)],
        ['بنود المبيعات', String(items.length)],
        ['المبالغ الآجلة', String(accounts.length)],
        ['التحصيلات', String(liveCollections.length)],
        ['المخزون', String(inventory.length)],
        ['المستخدمون', String(users.filter(alive).length)],
      ],
    ),
    المبيعات: table(
      [
        'رقم الفاتورة',
        'العميل',
        'الحالة',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'نوع الدفع',
        'البائع',
        'التاريخ',
      ],
      liveSales.map((sale) => {
        const paid = Number(pick(sale, 'paid_amount', 'paidAmount') || 0);
        const remaining = Number(
          pick(sale, 'remaining_amount', 'remainingAmount') || 0,
        );
        const payType = paid <= 0 ? 'آجل' : remaining <= 0 ? 'نقداً' : 'دفعة جزئية';
        const customerId = pick(sale, 'customer_id', 'customerId');
        return [
          pick(sale, 'sale_number', 'saleNumber'),
          customerNames[customerId] || customerId,
          pick(sale, 'status') || 'مكتملة',
          pick(sale, 'subtotal'),
          pick(sale, 'paid_amount', 'paidAmount'),
          pick(sale, 'remaining_amount', 'remainingAmount'),
          payType,
          userNames[pick(sale, 'created_by', 'createdBy')] ||
            pick(sale, 'created_by', 'createdBy'),
          pick(sale, 'sold_at', 'soldAt'),
        ];
      }),
    ),
    'بنود المبيعات': table(
      ['رقم الفاتورة', 'المنتج', 'الكمية', 'الوحدة', 'سعر الوحدة', 'الإجمالي'],
      items.map((item) => {
        const sale = sales.find(
          (row) => pick(row, 'id', 'entityId') === pick(item, 'sale_id', 'saleId'),
        );
        const productId = pick(item, 'product_id', 'productId');
        return [
          pick(sale || {}, 'sale_number', 'saleNumber') ||
            pick(item, 'sale_id', 'saleId'),
          productNames[productId] || productId,
          pick(item, 'quantity'),
          pick(item, 'unit'),
          pick(item, 'unit_price', 'unitPrice'),
          pick(item, 'line_total', 'lineTotal'),
        ];
      }),
    ),
    العملاء: table(
      ['الاسم', 'الهاتف', 'العنوان', 'المنطقة', 'الرصيد الآجل', 'نشط'],
      liveCustomers.map((customer) => {
        const id = pick(customer, 'id', 'entityId');
        const account = accounts.find(
          (row) => pick(row, 'customer_id', 'customerId') === id,
        );
        return [
          pick(customer, 'name'),
          pick(customer, 'phone'),
          pick(customer, 'address'),
          pick(customer, 'area'),
          pick(account || {}, 'cached_balance', 'cachedBalance') || '0',
          pick(customer, 'is_active', 'isActive'),
        ];
      }),
    ),
    'المبالغ الآجلة': table(
      ['العميل', 'الرصيد الآجل'],
      accounts.map((account) => {
        const id = pick(account, 'customer_id', 'customerId');
        return [customerNames[id] || id, pick(account, 'cached_balance', 'cachedBalance')];
      }),
    ),
    'حركات الآجل': table(
      ['التاريخ', 'العميل', 'النوع', 'المبلغ', 'الرصيد بعد الحركة', 'المستخدم'],
      accountTx.map((tx) => {
        const id = pick(tx, 'customer_id', 'customerId');
        return [
          pick(tx, 'created_at', 'createdAt'),
          customerNames[id] || id,
          pick(tx, 'type'),
          pick(tx, 'amount'),
          pick(tx, 'running_balance', 'runningBalance'),
          userNames[pick(tx, 'created_by', 'createdBy')] ||
            pick(tx, 'created_by', 'createdBy'),
        ];
      }),
    ),
    المنتجات: table(
      [
        'الاسم',
        'الرمز',
        'التصنيف',
        'سعر الشراء',
        'سعر البيع',
        'المخزون الحالي',
        'الوحدة',
        'نشط',
      ],
      liveProducts.map((product) => [
        pick(product, 'name'),
        pick(product, 'sku'),
        categoryNames[pick(product, 'category_id', 'categoryId')] || '',
        pick(product, 'purchase_price', 'purchasePrice'),
        pick(product, 'selling_price', 'sellingPrice'),
        pick(product, 'current_stock', 'currentStock'),
        pick(product, 'unit'),
        pick(product, 'is_active', 'isActive'),
      ]),
    ),
    التصنيفات: table(
      ['الاسم', 'الوصف', 'نشط'],
      categories.filter(alive).map((row) => [
        pick(row, 'name'),
        pick(row, 'description'),
        pick(row, 'is_active', 'isActive'),
      ]),
    ),
    المخزون: table(
      [
        'التاريخ',
        'المنتج',
        'النوع',
        'الكمية',
        'المخزون السابق',
        'المخزون الجديد',
        'المستخدم',
      ],
      inventory.map((row) => {
        const productId = pick(row, 'product_id', 'productId');
        return [
          pick(row, 'created_at', 'createdAt'),
          productNames[productId] || productId,
          pick(row, 'type'),
          pick(row, 'quantity'),
          pick(row, 'previous_stock', 'previousStock'),
          pick(row, 'new_stock', 'newStock'),
          userNames[pick(row, 'created_by', 'createdBy')] ||
            pick(row, 'created_by', 'createdBy'),
        ];
      }),
    ),
    التحصيلات: table(
      ['العميل', 'المبلغ', 'طريقة الدفع', 'التاريخ', 'المحصّل', 'الحالة'],
      liveCollections.map((row) => {
        const id = pick(row, 'customer_id', 'customerId');
        return [
          customerNames[id] || id,
          pick(row, 'amount'),
          pick(row, 'payment_method', 'paymentMethod'),
          pick(row, 'collected_at', 'collectedAt'),
          userNames[pick(row, 'created_by', 'createdBy')] ||
            pick(row, 'created_by', 'createdBy'),
          pick(row, 'status'),
        ];
      }),
    ),
    المستخدمون: table(
      ['اسم المستخدم', 'الاسم', 'الدور', 'نشط'],
      users.filter(alive).map((row) => [
        pick(row, 'username'),
        pick(row, 'display_name', 'displayName'),
        roleNames[pick(row, 'role_id', 'roleId')] || pick(row, 'role_id', 'roleId'),
        pick(row, 'is_active', 'isActive'),
      ]),
    ),
    الإعدادات: table(
      ['المفتاح', 'القيمة'],
      settings.map((row) => [pick(row, 'key'), pick(row, 'value')]),
    ),
    'سجل العمليات': table(
      ['التاريخ', 'الإجراء', 'النوع', 'المستخدم'],
      audits.map((row) => [
        pick(row, 'created_at', 'createdAt'),
        pick(row, 'action'),
        pick(row, 'entity_type', 'entityType'),
        userNames[pick(row, 'user_id', 'userId')] || pick(row, 'user_id', 'userId'),
      ]),
    ),
  };
}

function tabValues(tab) {
  if (typeof tab.valuesJson === 'string' && tab.valuesJson.trim()) {
    try {
      const parsed = JSON.parse(tab.valuesJson);
      if (Array.isArray(parsed)) return parsed;
    } catch (_) {
      return null;
    }
  }
  if (Array.isArray(tab.values)) return tab.values;
  return null;
}

async function loadSections(idToken) {
  const tabs = await listDocuments(idToken, 'sheet_tabs');
  const sections = {};
  for (const tab of tabs) {
    const values = tabValues(tab);
    if (tab.tab && values) {
      sections[tab.tab] = values;
    }
  }
  if (Object.keys(sections).length) {
    return sections;
  }
  return buildFromCollections(idToken);
}

async function writeSections(spreadsheetId, sections) {
  const sa = loadServiceAccount();
  const auth = new google.auth.JWT(
    sa.client_email,
    undefined,
    sa.private_key,
    ['https://www.googleapis.com/auth/spreadsheets'],
  );
  const sheets = google.sheets({version: 'v4', auth});
  const meta = await sheets.spreadsheets.get({spreadsheetId});
  const existing = new Set(
    (meta.data.sheets || [])
      .map((sheet) => sheet.properties && sheet.properties.title)
      .filter(Boolean),
  );
  const add = Object.keys(sections)
    .filter((title) => !existing.has(title))
    .map((title) => ({addSheet: {properties: {title}}}));
  if (add.length) {
    await sheets.spreadsheets.batchUpdate({
      spreadsheetId,
      requestBody: {requests: add},
    });
  }
  for (const [title, values] of Object.entries(sections)) {
    const range = `'${title}'!A:ZZ`;
    await sheets.spreadsheets.values.clear({spreadsheetId, range});
    if (Array.isArray(values) && values.length) {
      await sheets.spreadsheets.values.update({
        spreadsheetId,
        range,
        valueInputOption: 'RAW',
        requestBody: {values},
      });
    }
  }
}

const idToken = await signInAnonymously();
const sections = await loadSections(idToken);
await writeSections(SPREADSHEET_ID, sections);
console.log(`Wrote ${Object.keys(sections).length} Arabic tabs to Google Sheets`);
