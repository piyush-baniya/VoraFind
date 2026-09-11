// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MediaItemsTable extends MediaItems
    with TableInfo<$MediaItemsTable, MediaItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _stableKeyMeta = const VerificationMeta(
    'stableKey',
  );
  @override
  late final GeneratedColumn<String> stableKey = GeneratedColumn<String>(
    'stable_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _volumeNameMeta = const VerificationMeta(
    'volumeName',
  );
  @override
  late final GeneratedColumn<String> volumeName = GeneratedColumn<String>(
    'volume_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaStoreIdMeta = const VerificationMeta(
    'mediaStoreId',
  );
  @override
  late final GeneratedColumn<int> mediaStoreId = GeneratedColumn<int>(
    'media_store_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentUriMeta = const VerificationMeta(
    'contentUri',
  );
  @override
  late final GeneratedColumn<String> contentUri = GeneratedColumn<String>(
    'content_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<int> dateAdded = GeneratedColumn<int>(
    'date_added',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateModifiedMeta = const VerificationMeta(
    'dateModified',
  );
  @override
  late final GeneratedColumn<int> dateModified = GeneratedColumn<int>(
    'date_modified',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bucketDisplayNameMeta = const VerificationMeta(
    'bucketDisplayName',
  );
  @override
  late final GeneratedColumn<String> bucketDisplayName =
      GeneratedColumn<String>(
        'bucket_display_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumArtistMeta = const VerificationMeta(
    'albumArtist',
  );
  @override
  late final GeneratedColumn<String> albumArtist = GeneratedColumn<String>(
    'album_artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discNumberMeta = const VerificationMeta(
    'discNumber',
  );
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
    'disc_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _screenshotScoreMeta = const VerificationMeta(
    'screenshotScore',
  );
  @override
  late final GeneratedColumn<int> screenshotScore = GeneratedColumn<int>(
    'screenshot_score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isScreenshotMeta = const VerificationMeta(
    'isScreenshot',
  );
  @override
  late final GeneratedColumn<bool> isScreenshot = GeneratedColumn<bool>(
    'is_screenshot',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_screenshot" IN (0, 1))',
    ),
  );
  static const VerificationMeta _relinkSignatureMeta = const VerificationMeta(
    'relinkSignature',
  );
  @override
  late final GeneratedColumn<String> relinkSignature = GeneratedColumn<String>(
    'relink_signature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstDiscoveredAtMeta = const VerificationMeta(
    'firstDiscoveredAt',
  );
  @override
  late final GeneratedColumn<int> firstDiscoveredAt = GeneratedColumn<int>(
    'first_discovered_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastDiscoveredAtMeta = const VerificationMeta(
    'lastDiscoveredAt',
  );
  @override
  late final GeneratedColumn<int> lastDiscoveredAt = GeneratedColumn<int>(
    'last_discovered_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastIndexedGenerationMeta =
      const VerificationMeta('lastIndexedGeneration');
  @override
  late final GeneratedColumn<int> lastIndexedGeneration = GeneratedColumn<int>(
    'last_indexed_generation',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataRevisionMeta = const VerificationMeta(
    'metadataRevision',
  );
  @override
  late final GeneratedColumn<int> metadataRevision = GeneratedColumn<int>(
    'metadata_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<IndexingStatus, String>
  indexingStatus = GeneratedColumn<String>(
    'indexing_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<IndexingStatus>($MediaItemsTable.$converterindexingStatus);
  static const VerificationMeta _lastSeenAccessScopeMeta =
      const VerificationMeta('lastSeenAccessScope');
  @override
  late final GeneratedColumn<String> lastSeenAccessScope =
      GeneratedColumn<String>(
        'last_seen_access_scope',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    stableKey,
    category,
    volumeName,
    mediaStoreId,
    contentUri,
    displayName,
    title,
    mimeType,
    sizeBytes,
    dateAdded,
    dateModified,
    relativePath,
    bucketDisplayName,
    width,
    height,
    durationMs,
    artist,
    album,
    albumArtist,
    trackNumber,
    discNumber,
    genre,
    screenshotScore,
    isScreenshot,
    relinkSignature,
    firstDiscoveredAt,
    lastDiscoveredAt,
    lastIndexedGeneration,
    metadataRevision,
    indexingStatus,
    lastSeenAccessScope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stable_key')) {
      context.handle(
        _stableKeyMeta,
        stableKey.isAcceptableOrUnknown(data['stable_key']!, _stableKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_stableKeyMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('volume_name')) {
      context.handle(
        _volumeNameMeta,
        volumeName.isAcceptableOrUnknown(data['volume_name']!, _volumeNameMeta),
      );
    } else if (isInserting) {
      context.missing(_volumeNameMeta);
    }
    if (data.containsKey('media_store_id')) {
      context.handle(
        _mediaStoreIdMeta,
        mediaStoreId.isAcceptableOrUnknown(
          data['media_store_id']!,
          _mediaStoreIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mediaStoreIdMeta);
    }
    if (data.containsKey('content_uri')) {
      context.handle(
        _contentUriMeta,
        contentUri.isAcceptableOrUnknown(data['content_uri']!, _contentUriMeta),
      );
    } else if (isInserting) {
      context.missing(_contentUriMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    if (data.containsKey('date_modified')) {
      context.handle(
        _dateModifiedMeta,
        dateModified.isAcceptableOrUnknown(
          data['date_modified']!,
          _dateModifiedMeta,
        ),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    }
    if (data.containsKey('bucket_display_name')) {
      context.handle(
        _bucketDisplayNameMeta,
        bucketDisplayName.isAcceptableOrUnknown(
          data['bucket_display_name']!,
          _bucketDisplayNameMeta,
        ),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('album_artist')) {
      context.handle(
        _albumArtistMeta,
        albumArtist.isAcceptableOrUnknown(
          data['album_artist']!,
          _albumArtistMeta,
        ),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    if (data.containsKey('disc_number')) {
      context.handle(
        _discNumberMeta,
        discNumber.isAcceptableOrUnknown(data['disc_number']!, _discNumberMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('screenshot_score')) {
      context.handle(
        _screenshotScoreMeta,
        screenshotScore.isAcceptableOrUnknown(
          data['screenshot_score']!,
          _screenshotScoreMeta,
        ),
      );
    }
    if (data.containsKey('is_screenshot')) {
      context.handle(
        _isScreenshotMeta,
        isScreenshot.isAcceptableOrUnknown(
          data['is_screenshot']!,
          _isScreenshotMeta,
        ),
      );
    }
    if (data.containsKey('relink_signature')) {
      context.handle(
        _relinkSignatureMeta,
        relinkSignature.isAcceptableOrUnknown(
          data['relink_signature']!,
          _relinkSignatureMeta,
        ),
      );
    }
    if (data.containsKey('first_discovered_at')) {
      context.handle(
        _firstDiscoveredAtMeta,
        firstDiscoveredAt.isAcceptableOrUnknown(
          data['first_discovered_at']!,
          _firstDiscoveredAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstDiscoveredAtMeta);
    }
    if (data.containsKey('last_discovered_at')) {
      context.handle(
        _lastDiscoveredAtMeta,
        lastDiscoveredAt.isAcceptableOrUnknown(
          data['last_discovered_at']!,
          _lastDiscoveredAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastDiscoveredAtMeta);
    }
    if (data.containsKey('last_indexed_generation')) {
      context.handle(
        _lastIndexedGenerationMeta,
        lastIndexedGeneration.isAcceptableOrUnknown(
          data['last_indexed_generation']!,
          _lastIndexedGenerationMeta,
        ),
      );
    }
    if (data.containsKey('metadata_revision')) {
      context.handle(
        _metadataRevisionMeta,
        metadataRevision.isAcceptableOrUnknown(
          data['metadata_revision']!,
          _metadataRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metadataRevisionMeta);
    }
    if (data.containsKey('last_seen_access_scope')) {
      context.handle(
        _lastSeenAccessScopeMeta,
        lastSeenAccessScope.isAcceptableOrUnknown(
          data['last_seen_access_scope']!,
          _lastSeenAccessScopeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {stableKey};
  @override
  MediaItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItem(
      stableKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stable_key'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      volumeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}volume_name'],
      )!,
      mediaStoreId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_store_id'],
      )!,
      contentUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_uri'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_added'],
      ),
      dateModified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_modified'],
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      ),
      bucketDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bucket_display_name'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      albumArtist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_artist'],
      ),
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
      discNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_number'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      screenshotScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}screenshot_score'],
      ),
      isScreenshot: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_screenshot'],
      ),
      relinkSignature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relink_signature'],
      ),
      firstDiscoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_discovered_at'],
      )!,
      lastDiscoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_discovered_at'],
      )!,
      lastIndexedGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_indexed_generation'],
      ),
      metadataRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}metadata_revision'],
      )!,
      indexingStatus: $MediaItemsTable.$converterindexingStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}indexing_status'],
        )!,
      ),
      lastSeenAccessScope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_seen_access_scope'],
      ),
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<IndexingStatus, String, String>
  $converterindexingStatus = const EnumNameConverter<IndexingStatus>(
    IndexingStatus.values,
  );
}

class MediaItem extends DataClass implements Insertable<MediaItem> {
  /// Primary identity (`volumeName:mediaStoreId`), unchanged from discovery.
  final String stableKey;

  /// Media content category (`ContentCategory.name` wire value).
  final String category;
  final String volumeName;

  /// MediaStore `_ID` within [volumeName]'s collection.
  final int mediaStoreId;
  final String contentUri;
  final String displayName;
  final String? title;
  final String? mimeType;
  final int? sizeBytes;
  final int? dateAdded;
  final int? dateModified;
  final String? relativePath;
  final String? bucketDisplayName;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? artist;
  final String? album;

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  final String? albumArtist;

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  final int? trackNumber;

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  final int? discNumber;

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  final String? genre;
  final int? screenshotScore;
  final bool? isScreenshot;

  /// Relink signature computed by the scanner. Stored verbatim — the database
  /// layer never recomputes it.
  final String? relinkSignature;

  /// Epoch seconds when this stable identity was first seen.
  final int firstDiscoveredAt;

  /// Epoch seconds of the most recent upsert.
  final int lastDiscoveredAt;

  /// MediaStore generation reported on the discovery batch that last carried
  /// this record (API 30+; null below). Metadata only — no delta logic yet.
  final int? lastIndexedGeneration;

  /// Monotonic counter, incremented once per upsert. Distinguishes "re-seen
  /// unchanged" from "metadata changed" without storing a content hash.
  final int metadataRevision;

  /// Durable extraction state (see [IndexingStatus]); managed by later
  /// extraction prompts, preserved across metadata updates.
  final IndexingStatus indexingStatus;

  /// Access scope (`DiscoveryAccessScope.name`: `full`/`partial`) under which
  /// this record was last seen. A partial-access re-scan that no longer
  /// returns a row must NOT be treated as deletion — this column is what lets
  /// a future reconciler make that distinction.
  final String? lastSeenAccessScope;
  const MediaItem({
    required this.stableKey,
    required this.category,
    required this.volumeName,
    required this.mediaStoreId,
    required this.contentUri,
    required this.displayName,
    this.title,
    this.mimeType,
    this.sizeBytes,
    this.dateAdded,
    this.dateModified,
    this.relativePath,
    this.bucketDisplayName,
    this.width,
    this.height,
    this.durationMs,
    this.artist,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.genre,
    this.screenshotScore,
    this.isScreenshot,
    this.relinkSignature,
    required this.firstDiscoveredAt,
    required this.lastDiscoveredAt,
    this.lastIndexedGeneration,
    required this.metadataRevision,
    required this.indexingStatus,
    this.lastSeenAccessScope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stable_key'] = Variable<String>(stableKey);
    map['category'] = Variable<String>(category);
    map['volume_name'] = Variable<String>(volumeName);
    map['media_store_id'] = Variable<int>(mediaStoreId);
    map['content_uri'] = Variable<String>(contentUri);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    if (!nullToAbsent || dateAdded != null) {
      map['date_added'] = Variable<int>(dateAdded);
    }
    if (!nullToAbsent || dateModified != null) {
      map['date_modified'] = Variable<int>(dateModified);
    }
    if (!nullToAbsent || relativePath != null) {
      map['relative_path'] = Variable<String>(relativePath);
    }
    if (!nullToAbsent || bucketDisplayName != null) {
      map['bucket_display_name'] = Variable<String>(bucketDisplayName);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || albumArtist != null) {
      map['album_artist'] = Variable<String>(albumArtist);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || screenshotScore != null) {
      map['screenshot_score'] = Variable<int>(screenshotScore);
    }
    if (!nullToAbsent || isScreenshot != null) {
      map['is_screenshot'] = Variable<bool>(isScreenshot);
    }
    if (!nullToAbsent || relinkSignature != null) {
      map['relink_signature'] = Variable<String>(relinkSignature);
    }
    map['first_discovered_at'] = Variable<int>(firstDiscoveredAt);
    map['last_discovered_at'] = Variable<int>(lastDiscoveredAt);
    if (!nullToAbsent || lastIndexedGeneration != null) {
      map['last_indexed_generation'] = Variable<int>(lastIndexedGeneration);
    }
    map['metadata_revision'] = Variable<int>(metadataRevision);
    {
      map['indexing_status'] = Variable<String>(
        $MediaItemsTable.$converterindexingStatus.toSql(indexingStatus),
      );
    }
    if (!nullToAbsent || lastSeenAccessScope != null) {
      map['last_seen_access_scope'] = Variable<String>(lastSeenAccessScope);
    }
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      stableKey: Value(stableKey),
      category: Value(category),
      volumeName: Value(volumeName),
      mediaStoreId: Value(mediaStoreId),
      contentUri: Value(contentUri),
      displayName: Value(displayName),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      dateAdded: dateAdded == null && nullToAbsent
          ? const Value.absent()
          : Value(dateAdded),
      dateModified: dateModified == null && nullToAbsent
          ? const Value.absent()
          : Value(dateModified),
      relativePath: relativePath == null && nullToAbsent
          ? const Value.absent()
          : Value(relativePath),
      bucketDisplayName: bucketDisplayName == null && nullToAbsent
          ? const Value.absent()
          : Value(bucketDisplayName),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      albumArtist: albumArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(albumArtist),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      screenshotScore: screenshotScore == null && nullToAbsent
          ? const Value.absent()
          : Value(screenshotScore),
      isScreenshot: isScreenshot == null && nullToAbsent
          ? const Value.absent()
          : Value(isScreenshot),
      relinkSignature: relinkSignature == null && nullToAbsent
          ? const Value.absent()
          : Value(relinkSignature),
      firstDiscoveredAt: Value(firstDiscoveredAt),
      lastDiscoveredAt: Value(lastDiscoveredAt),
      lastIndexedGeneration: lastIndexedGeneration == null && nullToAbsent
          ? const Value.absent()
          : Value(lastIndexedGeneration),
      metadataRevision: Value(metadataRevision),
      indexingStatus: Value(indexingStatus),
      lastSeenAccessScope: lastSeenAccessScope == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAccessScope),
    );
  }

  factory MediaItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItem(
      stableKey: serializer.fromJson<String>(json['stableKey']),
      category: serializer.fromJson<String>(json['category']),
      volumeName: serializer.fromJson<String>(json['volumeName']),
      mediaStoreId: serializer.fromJson<int>(json['mediaStoreId']),
      contentUri: serializer.fromJson<String>(json['contentUri']),
      displayName: serializer.fromJson<String>(json['displayName']),
      title: serializer.fromJson<String?>(json['title']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      dateAdded: serializer.fromJson<int?>(json['dateAdded']),
      dateModified: serializer.fromJson<int?>(json['dateModified']),
      relativePath: serializer.fromJson<String?>(json['relativePath']),
      bucketDisplayName: serializer.fromJson<String?>(
        json['bucketDisplayName'],
      ),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      albumArtist: serializer.fromJson<String?>(json['albumArtist']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      genre: serializer.fromJson<String?>(json['genre']),
      screenshotScore: serializer.fromJson<int?>(json['screenshotScore']),
      isScreenshot: serializer.fromJson<bool?>(json['isScreenshot']),
      relinkSignature: serializer.fromJson<String?>(json['relinkSignature']),
      firstDiscoveredAt: serializer.fromJson<int>(json['firstDiscoveredAt']),
      lastDiscoveredAt: serializer.fromJson<int>(json['lastDiscoveredAt']),
      lastIndexedGeneration: serializer.fromJson<int?>(
        json['lastIndexedGeneration'],
      ),
      metadataRevision: serializer.fromJson<int>(json['metadataRevision']),
      indexingStatus: $MediaItemsTable.$converterindexingStatus.fromJson(
        serializer.fromJson<String>(json['indexingStatus']),
      ),
      lastSeenAccessScope: serializer.fromJson<String?>(
        json['lastSeenAccessScope'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stableKey': serializer.toJson<String>(stableKey),
      'category': serializer.toJson<String>(category),
      'volumeName': serializer.toJson<String>(volumeName),
      'mediaStoreId': serializer.toJson<int>(mediaStoreId),
      'contentUri': serializer.toJson<String>(contentUri),
      'displayName': serializer.toJson<String>(displayName),
      'title': serializer.toJson<String?>(title),
      'mimeType': serializer.toJson<String?>(mimeType),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'dateAdded': serializer.toJson<int?>(dateAdded),
      'dateModified': serializer.toJson<int?>(dateModified),
      'relativePath': serializer.toJson<String?>(relativePath),
      'bucketDisplayName': serializer.toJson<String?>(bucketDisplayName),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'albumArtist': serializer.toJson<String?>(albumArtist),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'genre': serializer.toJson<String?>(genre),
      'screenshotScore': serializer.toJson<int?>(screenshotScore),
      'isScreenshot': serializer.toJson<bool?>(isScreenshot),
      'relinkSignature': serializer.toJson<String?>(relinkSignature),
      'firstDiscoveredAt': serializer.toJson<int>(firstDiscoveredAt),
      'lastDiscoveredAt': serializer.toJson<int>(lastDiscoveredAt),
      'lastIndexedGeneration': serializer.toJson<int?>(lastIndexedGeneration),
      'metadataRevision': serializer.toJson<int>(metadataRevision),
      'indexingStatus': serializer.toJson<String>(
        $MediaItemsTable.$converterindexingStatus.toJson(indexingStatus),
      ),
      'lastSeenAccessScope': serializer.toJson<String?>(lastSeenAccessScope),
    };
  }

  MediaItem copyWith({
    String? stableKey,
    String? category,
    String? volumeName,
    int? mediaStoreId,
    String? contentUri,
    String? displayName,
    Value<String?> title = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    Value<int?> dateAdded = const Value.absent(),
    Value<int?> dateModified = const Value.absent(),
    Value<String?> relativePath = const Value.absent(),
    Value<String?> bucketDisplayName = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<String?> albumArtist = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<int?> screenshotScore = const Value.absent(),
    Value<bool?> isScreenshot = const Value.absent(),
    Value<String?> relinkSignature = const Value.absent(),
    int? firstDiscoveredAt,
    int? lastDiscoveredAt,
    Value<int?> lastIndexedGeneration = const Value.absent(),
    int? metadataRevision,
    IndexingStatus? indexingStatus,
    Value<String?> lastSeenAccessScope = const Value.absent(),
  }) => MediaItem(
    stableKey: stableKey ?? this.stableKey,
    category: category ?? this.category,
    volumeName: volumeName ?? this.volumeName,
    mediaStoreId: mediaStoreId ?? this.mediaStoreId,
    contentUri: contentUri ?? this.contentUri,
    displayName: displayName ?? this.displayName,
    title: title.present ? title.value : this.title,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    dateAdded: dateAdded.present ? dateAdded.value : this.dateAdded,
    dateModified: dateModified.present ? dateModified.value : this.dateModified,
    relativePath: relativePath.present ? relativePath.value : this.relativePath,
    bucketDisplayName: bucketDisplayName.present
        ? bucketDisplayName.value
        : this.bucketDisplayName,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    albumArtist: albumArtist.present ? albumArtist.value : this.albumArtist,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
    discNumber: discNumber.present ? discNumber.value : this.discNumber,
    genre: genre.present ? genre.value : this.genre,
    screenshotScore: screenshotScore.present
        ? screenshotScore.value
        : this.screenshotScore,
    isScreenshot: isScreenshot.present ? isScreenshot.value : this.isScreenshot,
    relinkSignature: relinkSignature.present
        ? relinkSignature.value
        : this.relinkSignature,
    firstDiscoveredAt: firstDiscoveredAt ?? this.firstDiscoveredAt,
    lastDiscoveredAt: lastDiscoveredAt ?? this.lastDiscoveredAt,
    lastIndexedGeneration: lastIndexedGeneration.present
        ? lastIndexedGeneration.value
        : this.lastIndexedGeneration,
    metadataRevision: metadataRevision ?? this.metadataRevision,
    indexingStatus: indexingStatus ?? this.indexingStatus,
    lastSeenAccessScope: lastSeenAccessScope.present
        ? lastSeenAccessScope.value
        : this.lastSeenAccessScope,
  );
  MediaItem copyWithCompanion(MediaItemsCompanion data) {
    return MediaItem(
      stableKey: data.stableKey.present ? data.stableKey.value : this.stableKey,
      category: data.category.present ? data.category.value : this.category,
      volumeName: data.volumeName.present
          ? data.volumeName.value
          : this.volumeName,
      mediaStoreId: data.mediaStoreId.present
          ? data.mediaStoreId.value
          : this.mediaStoreId,
      contentUri: data.contentUri.present
          ? data.contentUri.value
          : this.contentUri,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      title: data.title.present ? data.title.value : this.title,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      dateModified: data.dateModified.present
          ? data.dateModified.value
          : this.dateModified,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      bucketDisplayName: data.bucketDisplayName.present
          ? data.bucketDisplayName.value
          : this.bucketDisplayName,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      albumArtist: data.albumArtist.present
          ? data.albumArtist.value
          : this.albumArtist,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
      discNumber: data.discNumber.present
          ? data.discNumber.value
          : this.discNumber,
      genre: data.genre.present ? data.genre.value : this.genre,
      screenshotScore: data.screenshotScore.present
          ? data.screenshotScore.value
          : this.screenshotScore,
      isScreenshot: data.isScreenshot.present
          ? data.isScreenshot.value
          : this.isScreenshot,
      relinkSignature: data.relinkSignature.present
          ? data.relinkSignature.value
          : this.relinkSignature,
      firstDiscoveredAt: data.firstDiscoveredAt.present
          ? data.firstDiscoveredAt.value
          : this.firstDiscoveredAt,
      lastDiscoveredAt: data.lastDiscoveredAt.present
          ? data.lastDiscoveredAt.value
          : this.lastDiscoveredAt,
      lastIndexedGeneration: data.lastIndexedGeneration.present
          ? data.lastIndexedGeneration.value
          : this.lastIndexedGeneration,
      metadataRevision: data.metadataRevision.present
          ? data.metadataRevision.value
          : this.metadataRevision,
      indexingStatus: data.indexingStatus.present
          ? data.indexingStatus.value
          : this.indexingStatus,
      lastSeenAccessScope: data.lastSeenAccessScope.present
          ? data.lastSeenAccessScope.value
          : this.lastSeenAccessScope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaItem(')
          ..write('stableKey: $stableKey, ')
          ..write('category: $category, ')
          ..write('volumeName: $volumeName, ')
          ..write('mediaStoreId: $mediaStoreId, ')
          ..write('contentUri: $contentUri, ')
          ..write('displayName: $displayName, ')
          ..write('title: $title, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('dateModified: $dateModified, ')
          ..write('relativePath: $relativePath, ')
          ..write('bucketDisplayName: $bucketDisplayName, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('genre: $genre, ')
          ..write('screenshotScore: $screenshotScore, ')
          ..write('isScreenshot: $isScreenshot, ')
          ..write('relinkSignature: $relinkSignature, ')
          ..write('firstDiscoveredAt: $firstDiscoveredAt, ')
          ..write('lastDiscoveredAt: $lastDiscoveredAt, ')
          ..write('lastIndexedGeneration: $lastIndexedGeneration, ')
          ..write('metadataRevision: $metadataRevision, ')
          ..write('indexingStatus: $indexingStatus, ')
          ..write('lastSeenAccessScope: $lastSeenAccessScope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    stableKey,
    category,
    volumeName,
    mediaStoreId,
    contentUri,
    displayName,
    title,
    mimeType,
    sizeBytes,
    dateAdded,
    dateModified,
    relativePath,
    bucketDisplayName,
    width,
    height,
    durationMs,
    artist,
    album,
    albumArtist,
    trackNumber,
    discNumber,
    genre,
    screenshotScore,
    isScreenshot,
    relinkSignature,
    firstDiscoveredAt,
    lastDiscoveredAt,
    lastIndexedGeneration,
    metadataRevision,
    indexingStatus,
    lastSeenAccessScope,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItem &&
          other.stableKey == this.stableKey &&
          other.category == this.category &&
          other.volumeName == this.volumeName &&
          other.mediaStoreId == this.mediaStoreId &&
          other.contentUri == this.contentUri &&
          other.displayName == this.displayName &&
          other.title == this.title &&
          other.mimeType == this.mimeType &&
          other.sizeBytes == this.sizeBytes &&
          other.dateAdded == this.dateAdded &&
          other.dateModified == this.dateModified &&
          other.relativePath == this.relativePath &&
          other.bucketDisplayName == this.bucketDisplayName &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.albumArtist == this.albumArtist &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.genre == this.genre &&
          other.screenshotScore == this.screenshotScore &&
          other.isScreenshot == this.isScreenshot &&
          other.relinkSignature == this.relinkSignature &&
          other.firstDiscoveredAt == this.firstDiscoveredAt &&
          other.lastDiscoveredAt == this.lastDiscoveredAt &&
          other.lastIndexedGeneration == this.lastIndexedGeneration &&
          other.metadataRevision == this.metadataRevision &&
          other.indexingStatus == this.indexingStatus &&
          other.lastSeenAccessScope == this.lastSeenAccessScope);
}

class MediaItemsCompanion extends UpdateCompanion<MediaItem> {
  final Value<String> stableKey;
  final Value<String> category;
  final Value<String> volumeName;
  final Value<int> mediaStoreId;
  final Value<String> contentUri;
  final Value<String> displayName;
  final Value<String?> title;
  final Value<String?> mimeType;
  final Value<int?> sizeBytes;
  final Value<int?> dateAdded;
  final Value<int?> dateModified;
  final Value<String?> relativePath;
  final Value<String?> bucketDisplayName;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<String?> albumArtist;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<String?> genre;
  final Value<int?> screenshotScore;
  final Value<bool?> isScreenshot;
  final Value<String?> relinkSignature;
  final Value<int> firstDiscoveredAt;
  final Value<int> lastDiscoveredAt;
  final Value<int?> lastIndexedGeneration;
  final Value<int> metadataRevision;
  final Value<IndexingStatus> indexingStatus;
  final Value<String?> lastSeenAccessScope;
  final Value<int> rowid;
  const MediaItemsCompanion({
    this.stableKey = const Value.absent(),
    this.category = const Value.absent(),
    this.volumeName = const Value.absent(),
    this.mediaStoreId = const Value.absent(),
    this.contentUri = const Value.absent(),
    this.displayName = const Value.absent(),
    this.title = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.dateModified = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.bucketDisplayName = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.genre = const Value.absent(),
    this.screenshotScore = const Value.absent(),
    this.isScreenshot = const Value.absent(),
    this.relinkSignature = const Value.absent(),
    this.firstDiscoveredAt = const Value.absent(),
    this.lastDiscoveredAt = const Value.absent(),
    this.lastIndexedGeneration = const Value.absent(),
    this.metadataRevision = const Value.absent(),
    this.indexingStatus = const Value.absent(),
    this.lastSeenAccessScope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    required String stableKey,
    required String category,
    required String volumeName,
    required int mediaStoreId,
    required String contentUri,
    required String displayName,
    this.title = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.dateModified = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.bucketDisplayName = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.genre = const Value.absent(),
    this.screenshotScore = const Value.absent(),
    this.isScreenshot = const Value.absent(),
    this.relinkSignature = const Value.absent(),
    required int firstDiscoveredAt,
    required int lastDiscoveredAt,
    this.lastIndexedGeneration = const Value.absent(),
    required int metadataRevision,
    required IndexingStatus indexingStatus,
    this.lastSeenAccessScope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : stableKey = Value(stableKey),
       category = Value(category),
       volumeName = Value(volumeName),
       mediaStoreId = Value(mediaStoreId),
       contentUri = Value(contentUri),
       displayName = Value(displayName),
       firstDiscoveredAt = Value(firstDiscoveredAt),
       lastDiscoveredAt = Value(lastDiscoveredAt),
       metadataRevision = Value(metadataRevision),
       indexingStatus = Value(indexingStatus);
  static Insertable<MediaItem> custom({
    Expression<String>? stableKey,
    Expression<String>? category,
    Expression<String>? volumeName,
    Expression<int>? mediaStoreId,
    Expression<String>? contentUri,
    Expression<String>? displayName,
    Expression<String>? title,
    Expression<String>? mimeType,
    Expression<int>? sizeBytes,
    Expression<int>? dateAdded,
    Expression<int>? dateModified,
    Expression<String>? relativePath,
    Expression<String>? bucketDisplayName,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? albumArtist,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<String>? genre,
    Expression<int>? screenshotScore,
    Expression<bool>? isScreenshot,
    Expression<String>? relinkSignature,
    Expression<int>? firstDiscoveredAt,
    Expression<int>? lastDiscoveredAt,
    Expression<int>? lastIndexedGeneration,
    Expression<int>? metadataRevision,
    Expression<String>? indexingStatus,
    Expression<String>? lastSeenAccessScope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stableKey != null) 'stable_key': stableKey,
      if (category != null) 'category': category,
      if (volumeName != null) 'volume_name': volumeName,
      if (mediaStoreId != null) 'media_store_id': mediaStoreId,
      if (contentUri != null) 'content_uri': contentUri,
      if (displayName != null) 'display_name': displayName,
      if (title != null) 'title': title,
      if (mimeType != null) 'mime_type': mimeType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (dateAdded != null) 'date_added': dateAdded,
      if (dateModified != null) 'date_modified': dateModified,
      if (relativePath != null) 'relative_path': relativePath,
      if (bucketDisplayName != null) 'bucket_display_name': bucketDisplayName,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (genre != null) 'genre': genre,
      if (screenshotScore != null) 'screenshot_score': screenshotScore,
      if (isScreenshot != null) 'is_screenshot': isScreenshot,
      if (relinkSignature != null) 'relink_signature': relinkSignature,
      if (firstDiscoveredAt != null) 'first_discovered_at': firstDiscoveredAt,
      if (lastDiscoveredAt != null) 'last_discovered_at': lastDiscoveredAt,
      if (lastIndexedGeneration != null)
        'last_indexed_generation': lastIndexedGeneration,
      if (metadataRevision != null) 'metadata_revision': metadataRevision,
      if (indexingStatus != null) 'indexing_status': indexingStatus,
      if (lastSeenAccessScope != null)
        'last_seen_access_scope': lastSeenAccessScope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaItemsCompanion copyWith({
    Value<String>? stableKey,
    Value<String>? category,
    Value<String>? volumeName,
    Value<int>? mediaStoreId,
    Value<String>? contentUri,
    Value<String>? displayName,
    Value<String?>? title,
    Value<String?>? mimeType,
    Value<int?>? sizeBytes,
    Value<int?>? dateAdded,
    Value<int?>? dateModified,
    Value<String?>? relativePath,
    Value<String?>? bucketDisplayName,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? durationMs,
    Value<String?>? artist,
    Value<String?>? album,
    Value<String?>? albumArtist,
    Value<int?>? trackNumber,
    Value<int?>? discNumber,
    Value<String?>? genre,
    Value<int?>? screenshotScore,
    Value<bool?>? isScreenshot,
    Value<String?>? relinkSignature,
    Value<int>? firstDiscoveredAt,
    Value<int>? lastDiscoveredAt,
    Value<int?>? lastIndexedGeneration,
    Value<int>? metadataRevision,
    Value<IndexingStatus>? indexingStatus,
    Value<String?>? lastSeenAccessScope,
    Value<int>? rowid,
  }) {
    return MediaItemsCompanion(
      stableKey: stableKey ?? this.stableKey,
      category: category ?? this.category,
      volumeName: volumeName ?? this.volumeName,
      mediaStoreId: mediaStoreId ?? this.mediaStoreId,
      contentUri: contentUri ?? this.contentUri,
      displayName: displayName ?? this.displayName,
      title: title ?? this.title,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      relativePath: relativePath ?? this.relativePath,
      bucketDisplayName: bucketDisplayName ?? this.bucketDisplayName,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      genre: genre ?? this.genre,
      screenshotScore: screenshotScore ?? this.screenshotScore,
      isScreenshot: isScreenshot ?? this.isScreenshot,
      relinkSignature: relinkSignature ?? this.relinkSignature,
      firstDiscoveredAt: firstDiscoveredAt ?? this.firstDiscoveredAt,
      lastDiscoveredAt: lastDiscoveredAt ?? this.lastDiscoveredAt,
      lastIndexedGeneration:
          lastIndexedGeneration ?? this.lastIndexedGeneration,
      metadataRevision: metadataRevision ?? this.metadataRevision,
      indexingStatus: indexingStatus ?? this.indexingStatus,
      lastSeenAccessScope: lastSeenAccessScope ?? this.lastSeenAccessScope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (stableKey.present) {
      map['stable_key'] = Variable<String>(stableKey.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (volumeName.present) {
      map['volume_name'] = Variable<String>(volumeName.value);
    }
    if (mediaStoreId.present) {
      map['media_store_id'] = Variable<int>(mediaStoreId.value);
    }
    if (contentUri.present) {
      map['content_uri'] = Variable<String>(contentUri.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<int>(dateAdded.value);
    }
    if (dateModified.present) {
      map['date_modified'] = Variable<int>(dateModified.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (bucketDisplayName.present) {
      map['bucket_display_name'] = Variable<String>(bucketDisplayName.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumArtist.present) {
      map['album_artist'] = Variable<String>(albumArtist.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (screenshotScore.present) {
      map['screenshot_score'] = Variable<int>(screenshotScore.value);
    }
    if (isScreenshot.present) {
      map['is_screenshot'] = Variable<bool>(isScreenshot.value);
    }
    if (relinkSignature.present) {
      map['relink_signature'] = Variable<String>(relinkSignature.value);
    }
    if (firstDiscoveredAt.present) {
      map['first_discovered_at'] = Variable<int>(firstDiscoveredAt.value);
    }
    if (lastDiscoveredAt.present) {
      map['last_discovered_at'] = Variable<int>(lastDiscoveredAt.value);
    }
    if (lastIndexedGeneration.present) {
      map['last_indexed_generation'] = Variable<int>(
        lastIndexedGeneration.value,
      );
    }
    if (metadataRevision.present) {
      map['metadata_revision'] = Variable<int>(metadataRevision.value);
    }
    if (indexingStatus.present) {
      map['indexing_status'] = Variable<String>(
        $MediaItemsTable.$converterindexingStatus.toSql(indexingStatus.value),
      );
    }
    if (lastSeenAccessScope.present) {
      map['last_seen_access_scope'] = Variable<String>(
        lastSeenAccessScope.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsCompanion(')
          ..write('stableKey: $stableKey, ')
          ..write('category: $category, ')
          ..write('volumeName: $volumeName, ')
          ..write('mediaStoreId: $mediaStoreId, ')
          ..write('contentUri: $contentUri, ')
          ..write('displayName: $displayName, ')
          ..write('title: $title, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('dateModified: $dateModified, ')
          ..write('relativePath: $relativePath, ')
          ..write('bucketDisplayName: $bucketDisplayName, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('genre: $genre, ')
          ..write('screenshotScore: $screenshotScore, ')
          ..write('isScreenshot: $isScreenshot, ')
          ..write('relinkSignature: $relinkSignature, ')
          ..write('firstDiscoveredAt: $firstDiscoveredAt, ')
          ..write('lastDiscoveredAt: $lastDiscoveredAt, ')
          ..write('lastIndexedGeneration: $lastIndexedGeneration, ')
          ..write('metadataRevision: $metadataRevision, ')
          ..write('indexingStatus: $indexingStatus, ')
          ..write('lastSeenAccessScope: $lastSeenAccessScope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MediaItemsTable mediaItems = $MediaItemsTable(this);
  late final Index idxMediaCategoryDateModified = Index(
    'idx_media_category_date_modified',
    'CREATE INDEX idx_media_category_date_modified ON media_items (category, date_modified)',
  );
  late final Index idxMediaVolumeMediaStoreId = Index(
    'idx_media_volume_media_store_id',
    'CREATE INDEX idx_media_volume_media_store_id ON media_items (volume_name, media_store_id)',
  );
  late final Index idxMediaMimeType = Index(
    'idx_media_mime_type',
    'CREATE INDEX idx_media_mime_type ON media_items (mime_type)',
  );
  late final Index idxMediaRelativePath = Index(
    'idx_media_relative_path',
    'CREATE INDEX idx_media_relative_path ON media_items (relative_path)',
  );
  late final Index idxMediaScreenshotCategory = Index(
    'idx_media_screenshot_category',
    'CREATE INDEX idx_media_screenshot_category ON media_items (is_screenshot, category)',
  );
  late final Index idxMediaLastDiscoveredAt = Index(
    'idx_media_last_discovered_at',
    'CREATE INDEX idx_media_last_discovered_at ON media_items (last_discovered_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    mediaItems,
    idxMediaCategoryDateModified,
    idxMediaVolumeMediaStoreId,
    idxMediaMimeType,
    idxMediaRelativePath,
    idxMediaScreenshotCategory,
    idxMediaLastDiscoveredAt,
  ];
}

typedef $$MediaItemsTableCreateCompanionBuilder = MediaItemsCompanion Function({
  required String stableKey,
  required String category,
  required String volumeName,
  required int mediaStoreId,
  required String contentUri,
  required String displayName,
  Value<String?> title,
  Value<String?> mimeType,
  Value<int?> sizeBytes,
  Value<int?> dateAdded,
  Value<int?> dateModified,
  Value<String?> relativePath,
  Value<String?> bucketDisplayName,
  Value<int?> width,
  Value<int?> height,
  Value<int?> durationMs,
  Value<String?> artist,
  Value<String?> album,
  Value<String?> albumArtist,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<String?> genre,
  Value<int?> screenshotScore,
  Value<bool?> isScreenshot,
  Value<String?> relinkSignature,
  required int firstDiscoveredAt,
  required int lastDiscoveredAt,
  Value<int?> lastIndexedGeneration,
  required int metadataRevision,
  required IndexingStatus indexingStatus,
  Value<String?> lastSeenAccessScope,
  Value<int> rowid,
});
typedef $$MediaItemsTableUpdateCompanionBuilder = MediaItemsCompanion Function({
  Value<String> stableKey,
  Value<String> category,
  Value<String> volumeName,
  Value<int> mediaStoreId,
  Value<String> contentUri,
  Value<String> displayName,
  Value<String?> title,
  Value<String?> mimeType,
  Value<int?> sizeBytes,
  Value<int?> dateAdded,
  Value<int?> dateModified,
  Value<String?> relativePath,
  Value<String?> bucketDisplayName,
  Value<int?> width,
  Value<int?> height,
  Value<int?> durationMs,
  Value<String?> artist,
  Value<String?> album,
  Value<String?> albumArtist,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<String?> genre,
  Value<int?> screenshotScore,
  Value<bool?> isScreenshot,
  Value<String?> relinkSignature,
  Value<int> firstDiscoveredAt,
  Value<int> lastDiscoveredAt,
  Value<int?> lastIndexedGeneration,
  Value<int> metadataRevision,
  Value<IndexingStatus> indexingStatus,
  Value<String?> lastSeenAccessScope,
  Value<int> rowid,
});

class $$MediaItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get stableKey => $composableBuilder(
    column: $table.stableKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get volumeName => $composableBuilder(
    column: $table.volumeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaStoreId => $composableBuilder(
    column: $table.mediaStoreId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentUri => $composableBuilder(
    column: $table.contentUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateModified => $composableBuilder(
    column: $table.dateModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bucketDisplayName => $composableBuilder(
    column: $table.bucketDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get screenshotScore => $composableBuilder(
    column: $table.screenshotScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isScreenshot => $composableBuilder(
    column: $table.isScreenshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relinkSignature => $composableBuilder(
    column: $table.relinkSignature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstDiscoveredAt => $composableBuilder(
    column: $table.firstDiscoveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastDiscoveredAt => $composableBuilder(
    column: $table.lastDiscoveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastIndexedGeneration => $composableBuilder(
    column: $table.lastIndexedGeneration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get metadataRevision => $composableBuilder(
    column: $table.metadataRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<IndexingStatus, IndexingStatus, String>
  get indexingStatus => $composableBuilder(
    column: $table.indexingStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get lastSeenAccessScope => $composableBuilder(
    column: $table.lastSeenAccessScope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get stableKey => $composableBuilder(
    column: $table.stableKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get volumeName => $composableBuilder(
    column: $table.volumeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaStoreId => $composableBuilder(
    column: $table.mediaStoreId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentUri => $composableBuilder(
    column: $table.contentUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateModified => $composableBuilder(
    column: $table.dateModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bucketDisplayName => $composableBuilder(
    column: $table.bucketDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get screenshotScore => $composableBuilder(
    column: $table.screenshotScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isScreenshot => $composableBuilder(
    column: $table.isScreenshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relinkSignature => $composableBuilder(
    column: $table.relinkSignature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstDiscoveredAt => $composableBuilder(
    column: $table.firstDiscoveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastDiscoveredAt => $composableBuilder(
    column: $table.lastDiscoveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastIndexedGeneration => $composableBuilder(
    column: $table.lastIndexedGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get metadataRevision => $composableBuilder(
    column: $table.metadataRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get indexingStatus => $composableBuilder(
    column: $table.indexingStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSeenAccessScope => $composableBuilder(
    column: $table.lastSeenAccessScope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get stableKey =>
      $composableBuilder(column: $table.stableKey, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get volumeName => $composableBuilder(
    column: $table.volumeName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mediaStoreId => $composableBuilder(
    column: $table.mediaStoreId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentUri => $composableBuilder(
    column: $table.contentUri,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<int> get dateModified => $composableBuilder(
    column: $table.dateModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bucketDisplayName => $composableBuilder(
    column: $table.bucketDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get screenshotScore => $composableBuilder(
    column: $table.screenshotScore,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isScreenshot => $composableBuilder(
    column: $table.isScreenshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relinkSignature => $composableBuilder(
    column: $table.relinkSignature,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstDiscoveredAt => $composableBuilder(
    column: $table.firstDiscoveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastDiscoveredAt => $composableBuilder(
    column: $table.lastDiscoveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastIndexedGeneration => $composableBuilder(
    column: $table.lastIndexedGeneration,
    builder: (column) => column,
  );

  GeneratedColumn<int> get metadataRevision => $composableBuilder(
    column: $table.metadataRevision,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<IndexingStatus, String> get indexingStatus =>
      $composableBuilder(
        column: $table.indexingStatus,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastSeenAccessScope => $composableBuilder(
    column: $table.lastSeenAccessScope,
    builder: (column) => column,
  );
}

class $$MediaItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaItemsTable,
          MediaItem,
          $$MediaItemsTableFilterComposer,
          $$MediaItemsTableOrderingComposer,
          $$MediaItemsTableAnnotationComposer,
          $$MediaItemsTableCreateCompanionBuilder,
          $$MediaItemsTableUpdateCompanionBuilder,
          (
            MediaItem,
            BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItem>,
          ),
          MediaItem,
          PrefetchHooks Function()
        > {
  $$MediaItemsTableTableManager(_$AppDatabase db, $MediaItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> stableKey = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> volumeName = const Value.absent(),
                Value<int> mediaStoreId = const Value.absent(),
                Value<String> contentUri = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<int?> dateAdded = const Value.absent(),
                Value<int?> dateModified = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String?> bucketDisplayName = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> albumArtist = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> screenshotScore = const Value.absent(),
                Value<bool?> isScreenshot = const Value.absent(),
                Value<String?> relinkSignature = const Value.absent(),
                Value<int> firstDiscoveredAt = const Value.absent(),
                Value<int> lastDiscoveredAt = const Value.absent(),
                Value<int?> lastIndexedGeneration = const Value.absent(),
                Value<int> metadataRevision = const Value.absent(),
                Value<IndexingStatus> indexingStatus = const Value.absent(),
                Value<String?> lastSeenAccessScope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaItemsCompanion(
                stableKey: stableKey,
                category: category,
                volumeName: volumeName,
                mediaStoreId: mediaStoreId,
                contentUri: contentUri,
                displayName: displayName,
                title: title,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                dateAdded: dateAdded,
                dateModified: dateModified,
                relativePath: relativePath,
                bucketDisplayName: bucketDisplayName,
                width: width,
                height: height,
                durationMs: durationMs,
                artist: artist,
                album: album,
                albumArtist: albumArtist,
                trackNumber: trackNumber,
                discNumber: discNumber,
                genre: genre,
                screenshotScore: screenshotScore,
                isScreenshot: isScreenshot,
                relinkSignature: relinkSignature,
                firstDiscoveredAt: firstDiscoveredAt,
                lastDiscoveredAt: lastDiscoveredAt,
                lastIndexedGeneration: lastIndexedGeneration,
                metadataRevision: metadataRevision,
                indexingStatus: indexingStatus,
                lastSeenAccessScope: lastSeenAccessScope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stableKey,
                required String category,
                required String volumeName,
                required int mediaStoreId,
                required String contentUri,
                required String displayName,
                Value<String?> title = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<int?> dateAdded = const Value.absent(),
                Value<int?> dateModified = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String?> bucketDisplayName = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> albumArtist = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> screenshotScore = const Value.absent(),
                Value<bool?> isScreenshot = const Value.absent(),
                Value<String?> relinkSignature = const Value.absent(),
                required int firstDiscoveredAt,
                required int lastDiscoveredAt,
                Value<int?> lastIndexedGeneration = const Value.absent(),
                required int metadataRevision,
                required IndexingStatus indexingStatus,
                Value<String?> lastSeenAccessScope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaItemsCompanion.insert(
                stableKey: stableKey,
                category: category,
                volumeName: volumeName,
                mediaStoreId: mediaStoreId,
                contentUri: contentUri,
                displayName: displayName,
                title: title,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                dateAdded: dateAdded,
                dateModified: dateModified,
                relativePath: relativePath,
                bucketDisplayName: bucketDisplayName,
                width: width,
                height: height,
                durationMs: durationMs,
                artist: artist,
                album: album,
                albumArtist: albumArtist,
                trackNumber: trackNumber,
                discNumber: discNumber,
                genre: genre,
                screenshotScore: screenshotScore,
                isScreenshot: isScreenshot,
                relinkSignature: relinkSignature,
                firstDiscoveredAt: firstDiscoveredAt,
                lastDiscoveredAt: lastDiscoveredAt,
                lastIndexedGeneration: lastIndexedGeneration,
                metadataRevision: metadataRevision,
                indexingStatus: indexingStatus,
                lastSeenAccessScope: lastSeenAccessScope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaItemsTable, MediaItem>(table),
                  BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItem>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaItemsTable,
      MediaItem,
      $$MediaItemsTableFilterComposer,
      $$MediaItemsTableOrderingComposer,
      $$MediaItemsTableAnnotationComposer,
      $$MediaItemsTableCreateCompanionBuilder,
      $$MediaItemsTableUpdateCompanionBuilder,
      (MediaItem, BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItem>),
      MediaItem,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MediaItemsTableTableManager get mediaItems =>
      $$MediaItemsTableTableManager(_db, _db.mediaItems);
}
