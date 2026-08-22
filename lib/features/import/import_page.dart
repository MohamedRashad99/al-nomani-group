import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/import_service.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';

enum ImportKind { products, customers, inventory }

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  ImportKind _kind = ImportKind.products;
  List<ImportPreviewRow> _rows = const [];
  String? _fileName;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session!;
    final allowedKinds = [
      if (session.can(AppPermission.productsCreate)) ImportKind.products,
      if (session.can(AppPermission.customersCreate)) ImportKind.customers,
      if (session.can(AppPermission.inventoryCreate)) ImportKind.inventory,
    ];
    if (!allowedKinds.contains(_kind) && allowedKinds.isNotEmpty) {
      _kind = allowedKinds.first;
    }
    return AppScaffold(
      title: 'استيراد البيانات',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'نوع البيانات',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ImportKind>(
                    segments: [
                      if (allowedKinds.contains(ImportKind.products))
                        const ButtonSegment(
                          value: ImportKind.products,
                          label: Text('المنتجات'),
                        ),
                      if (allowedKinds.contains(ImportKind.customers))
                        const ButtonSegment(
                          value: ImportKind.customers,
                          label: Text('العملاء'),
                        ),
                      if (allowedKinds.contains(ImportKind.inventory))
                        const ButtonSegment(
                          value: ImportKind.inventory,
                          label: Text('المخزون الافتتاحي'),
                        ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (value) => setState(() {
                      _kind = value.first;
                      _rows = const [];
                      _fileName = null;
                    }),
                  ),
                  const SizedBox(height: 14),
                  Text(_templateHint(_kind)),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(_fileName ?? 'اختيار ملف CSV'),
                  ),
                ],
              ),
            ),
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'معاينة قبل الاستيراد',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${_rows.where((row) => row.error == null).length} صالح • ${_rows.where((row) => row.error != null).length} أخطاء',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final row in _rows.take(100))
                      ListTile(
                        leading: CircleAvatar(child: Text('${row.line}')),
                        title: Text(
                          row.values['name'] ??
                              row.values['sku'] ??
                              'السطر ${row.line}',
                        ),
                        subtitle: Text(
                          row.error ??
                              row.values.entries
                                  .map((entry) => '${entry.key}: ${entry.value}')
                                  .join(' • '),
                        ),
                        trailing: Icon(
                          row.error == null
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: row.error == null
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed:
                          _busy ||
                              _rows.every((row) => row.error != null)
                          ? null
                          : _confirm,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('تأكيد استيراد الصفوف الصالحة'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _templateHint(ImportKind kind) => switch (kind) {
    ImportKind.products =>
      'الأعمدة: name, sku, brand, purchase_price, selling_price, minimum_stock, stock, unit',
    ImportKind.customers => 'الأعمدة: name, phone, address, area, notes',
    ImportKind.inventory => 'الأعمدة: sku, quantity',
  };

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    try {
      final text = utf8.decode(file!.bytes!, allowMalformed: false);
      final importer = sl<ImportService>();
      final rows = switch (_kind) {
        ImportKind.products => importer.previewProducts(text),
        ImportKind.customers => importer.previewCustomers(text),
        ImportKind.inventory => importer.previewOpeningInventory(text),
      };
      setState(() {
        _fileName = file.name;
        _rows = rows;
      });
    } catch (error) {
      _message('تعذر قراءة الملف: $error');
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final session = context.read<AuthCubit>().state.session!;
      final importer = sl<ImportService>();
      final count = switch (_kind) {
        ImportKind.products => await importer.confirmProducts(session, _rows),
        ImportKind.customers => await importer.confirmCustomers(session, _rows),
        ImportKind.inventory => await importer.confirmOpeningInventory(
          session,
          _rows,
        ),
      };
      await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      _message('تم استيراد $count صفوف بنجاح.');
      if (mounted) setState(() => _rows = const []);
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
