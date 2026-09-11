import 'package:drift/drift.dart';

/// Per-unit checkpoint for incremental MediaStore synchronization
/// (architecture §15). One row per (category, volume) pair.
///
/// [lastGeneration] is the MediaStore generation token observed at the end of
/// the last clean, full-scope scan. The next sync uses it as an "unchanged"
/// fast-check hint: when the current generation still equals it, nothing in
/// that collection changed and the scan is skipped. It is never used as a
/// delta cursor.
///
/// [lastAccessScope] records the scope the checkpoint was taken under. A
/// checkpoint obtained at partial scope must not be reused for a full-scope
/// fast-check, and deleting rows is only ever safe under full scope.
///
/// [lastResult] mirrors the [SyncUnitResult.kind] wire value of the last
/// completed run (`firstIndex`, `unchanged`, `reconciled`, `partialAccess`).
class IndexState extends Table {
  /// `ContentCategory.name` wire value.
  TextColumn get category => text()();

  /// Absolute MediaStore volume name.
  TextColumn get volumeName => text()();

  /// MediaStore generation token; null when unsupported or unknown.
  IntColumn get lastGeneration => integer().nullable()();

  /// `DiscoveryAccessScope.name` wire value under which the checkpoint was taken.
  TextColumn get lastAccessScope => text()();

  /// Epoch seconds of the checkpoint.
  IntColumn get lastSyncAt => integer()();

  /// Wire value of the last run's result kind.
  TextColumn get lastResult => text()();

  @override
  Set<Column<Object>> get primaryKey => {category, volumeName};
}
