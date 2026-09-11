import 'package:drift/drift.dart';

import '../documents/document_models.dart' show DocumentAccessStateConverter;

/// Persisted SAF tree grants mirrored from Android's persistable URI
/// permissions (schema v5, `docs/documents.md`).
///
/// Android remains the source of truth for whether a grant is currently
/// effective. This table records the last-known grant so a revoked tree can
/// be marked inaccessible without deleting indexed documents.
@TableIndex(name: 'idx_saf_grants_access_state', columns: {#accessState})
class SafGrants extends Table {
  TextColumn get treeUri => text()();

  TextColumn get displayName => text()();

  BoolColumn get persisted => boolean()();

  TextColumn get accessState =>
      text().map(const DocumentAccessStateConverter())();

  IntColumn get lastSeenAt => integer()();

  IntColumn get lastEnumeratedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {treeUri};
}
