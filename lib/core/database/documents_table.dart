import 'package:drift/drift.dart';

import '../documents/document_models.dart' show DocumentAccessStateConverter;

/// Metadata index for user-granted SAF documents (schema v5).
///
/// Separate from `media_items`: MediaStore media and SAF documents are
/// different content sources and must not share fake media rows.
@TableIndex(name: 'idx_documents_tree_uri', columns: {#treeUri})
@TableIndex(
  name: 'idx_documents_access_stable',
  columns: {#accessState, #stableKey},
)
@TableIndex(name: 'idx_documents_date_modified', columns: {#dateModified})
class Documents extends Table {
  /// `saf:{urlencoded treeUri}:{urlencoded documentId}` from Kotlin.
  TextColumn get stableKey => text()();

  TextColumn get treeUri => text()();

  TextColumn get documentId => text()();

  /// Content URI reconstructible from the tree grant + document id.
  TextColumn get uri => text()();

  TextColumn get displayName => text()();

  TextColumn get mimeType => text().nullable()();

  IntColumn get sizeBytes => integer().nullable()();

  /// Epoch seconds (converted from DocumentsContract milliseconds).
  IntColumn get dateModified => integer().nullable()();

  /// Tree-relative display path (`Folder/Sub/file.pdf`).
  TextColumn get relativePath => text().nullable()();

  /// `size|modified|mime` snapshot; compared on upsert to decide revision bumps.
  TextColumn get contentFingerprint => text()();

  /// Monotonic counter; copied onto `document_content.source_revision`.
  IntColumn get sourceRevision => integer()();

  TextColumn get accessState =>
      text().map(const DocumentAccessStateConverter())();

  IntColumn get firstDiscoveredAt => integer()();

  IntColumn get lastDiscoveredAt => integer()();

  /// Normalized name + path + mime for metadata keyword retrieval.
  TextColumn get searchableText => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {stableKey};
}
