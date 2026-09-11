import 'package:drift/drift.dart';

import '../documents/document_models.dart' show DocumentContentStatusConverter;

/// Derived text extracted from a SAF document (schema v5).
///
/// Never stores original file bytes. `ON DELETE CASCADE` from `documents`
/// so confirmed deletions cannot leave orphaned text.
@TableIndex(
  name: 'idx_document_content_status_key',
  columns: {#status, #documentStableKey},
)
class DocumentContent extends Table {
  TextColumn get documentStableKey => text()();

  TextColumn get rawText => text().nullable()();

  TextColumn get normalizedText => text().nullable()();

  TextColumn get status => text().map(const DocumentContentStatusConverter())();

  IntColumn get sourceRevision => integer()();

  BoolColumn get truncated => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  TextColumn get errorCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentStableKey};

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (document_stable_key) '
        'REFERENCES documents (stable_key) ON DELETE CASCADE',
  ];
}
