// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown'));
  static const VerificationMeta _coverPathMeta =
      const VerificationMeta('coverPath');
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
      'cover_path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _filePathsJsonMeta =
      const VerificationMeta('filePathsJson');
  @override
  late final GeneratedColumn<String> filePathsJson = GeneratedColumn<String>(
      'file_paths_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _totalDurationMsMeta =
      const VerificationMeta('totalDurationMs');
  @override
  late final GeneratedColumn<int> totalDurationMs = GeneratedColumn<int>(
      'total_duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _addedAtMsMeta =
      const VerificationMeta('addedAtMs');
  @override
  late final GeneratedColumn<int> addedAtMs = GeneratedColumn<int>(
      'added_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastPlayedAtMsMeta =
      const VerificationMeta('lastPlayedAtMs');
  @override
  late final GeneratedColumn<int> lastPlayedAtMs = GeneratedColumn<int>(
      'last_played_at_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastPositionFilePathMeta =
      const VerificationMeta('lastPositionFilePath');
  @override
  late final GeneratedColumn<String> lastPositionFilePath =
      GeneratedColumn<String>('last_position_file_path', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastPositionMsMeta =
      const VerificationMeta('lastPositionMs');
  @override
  late final GeneratedColumn<int> lastPositionMs = GeneratedColumn<int>(
      'last_position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalProgressMeta =
      const VerificationMeta('totalProgress');
  @override
  late final GeneratedColumn<double> totalProgress = GeneratedColumn<double>(
      'total_progress', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isFinishedMeta =
      const VerificationMeta('isFinished');
  @override
  late final GeneratedColumn<bool> isFinished = GeneratedColumn<bool>(
      'is_finished', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_finished" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        author,
        coverPath,
        filePathsJson,
        totalDurationMs,
        addedAtMs,
        lastPlayedAtMs,
        lastPositionFilePath,
        lastPositionMs,
        totalProgress,
        isFinished
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(Insertable<Book> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    if (data.containsKey('cover_path')) {
      context.handle(_coverPathMeta,
          coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta));
    }
    if (data.containsKey('file_paths_json')) {
      context.handle(
          _filePathsJsonMeta,
          filePathsJson.isAcceptableOrUnknown(
              data['file_paths_json']!, _filePathsJsonMeta));
    } else if (isInserting) {
      context.missing(_filePathsJsonMeta);
    }
    if (data.containsKey('total_duration_ms')) {
      context.handle(
          _totalDurationMsMeta,
          totalDurationMs.isAcceptableOrUnknown(
              data['total_duration_ms']!, _totalDurationMsMeta));
    }
    if (data.containsKey('added_at_ms')) {
      context.handle(
          _addedAtMsMeta,
          addedAtMs.isAcceptableOrUnknown(
              data['added_at_ms']!, _addedAtMsMeta));
    } else if (isInserting) {
      context.missing(_addedAtMsMeta);
    }
    if (data.containsKey('last_played_at_ms')) {
      context.handle(
          _lastPlayedAtMsMeta,
          lastPlayedAtMs.isAcceptableOrUnknown(
              data['last_played_at_ms']!, _lastPlayedAtMsMeta));
    }
    if (data.containsKey('last_position_file_path')) {
      context.handle(
          _lastPositionFilePathMeta,
          lastPositionFilePath.isAcceptableOrUnknown(
              data['last_position_file_path']!, _lastPositionFilePathMeta));
    }
    if (data.containsKey('last_position_ms')) {
      context.handle(
          _lastPositionMsMeta,
          lastPositionMs.isAcceptableOrUnknown(
              data['last_position_ms']!, _lastPositionMsMeta));
    }
    if (data.containsKey('total_progress')) {
      context.handle(
          _totalProgressMeta,
          totalProgress.isAcceptableOrUnknown(
              data['total_progress']!, _totalProgressMeta));
    }
    if (data.containsKey('is_finished')) {
      context.handle(
          _isFinishedMeta,
          isFinished.isAcceptableOrUnknown(
              data['is_finished']!, _isFinishedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author'])!,
      coverPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_path'])!,
      filePathsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}file_paths_json'])!,
      totalDurationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_duration_ms'])!,
      addedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}added_at_ms'])!,
      lastPlayedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_played_at_ms']),
      lastPositionFilePath: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_position_file_path']),
      lastPositionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_position_ms'])!,
      totalProgress: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total_progress'])!,
      isFinished: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_finished'])!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class Book extends DataClass implements Insertable<Book> {
  final String id;
  final String title;
  final String author;
  final String coverPath;
  final String filePathsJson;
  final int totalDurationMs;
  final int addedAtMs;
  final int? lastPlayedAtMs;
  final String? lastPositionFilePath;
  final int lastPositionMs;
  final double totalProgress;
  final bool isFinished;
  const Book(
      {required this.id,
      required this.title,
      required this.author,
      required this.coverPath,
      required this.filePathsJson,
      required this.totalDurationMs,
      required this.addedAtMs,
      this.lastPlayedAtMs,
      this.lastPositionFilePath,
      required this.lastPositionMs,
      required this.totalProgress,
      required this.isFinished});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['author'] = Variable<String>(author);
    map['cover_path'] = Variable<String>(coverPath);
    map['file_paths_json'] = Variable<String>(filePathsJson);
    map['total_duration_ms'] = Variable<int>(totalDurationMs);
    map['added_at_ms'] = Variable<int>(addedAtMs);
    if (!nullToAbsent || lastPlayedAtMs != null) {
      map['last_played_at_ms'] = Variable<int>(lastPlayedAtMs);
    }
    if (!nullToAbsent || lastPositionFilePath != null) {
      map['last_position_file_path'] = Variable<String>(lastPositionFilePath);
    }
    map['last_position_ms'] = Variable<int>(lastPositionMs);
    map['total_progress'] = Variable<double>(totalProgress);
    map['is_finished'] = Variable<bool>(isFinished);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: Value(author),
      coverPath: Value(coverPath),
      filePathsJson: Value(filePathsJson),
      totalDurationMs: Value(totalDurationMs),
      addedAtMs: Value(addedAtMs),
      lastPlayedAtMs: lastPlayedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAtMs),
      lastPositionFilePath: lastPositionFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPositionFilePath),
      lastPositionMs: Value(lastPositionMs),
      totalProgress: Value(totalProgress),
      isFinished: Value(isFinished),
    );
  }

  factory Book.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Book(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String>(json['author']),
      coverPath: serializer.fromJson<String>(json['coverPath']),
      filePathsJson: serializer.fromJson<String>(json['filePathsJson']),
      totalDurationMs: serializer.fromJson<int>(json['totalDurationMs']),
      addedAtMs: serializer.fromJson<int>(json['addedAtMs']),
      lastPlayedAtMs: serializer.fromJson<int?>(json['lastPlayedAtMs']),
      lastPositionFilePath:
          serializer.fromJson<String?>(json['lastPositionFilePath']),
      lastPositionMs: serializer.fromJson<int>(json['lastPositionMs']),
      totalProgress: serializer.fromJson<double>(json['totalProgress']),
      isFinished: serializer.fromJson<bool>(json['isFinished']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String>(author),
      'coverPath': serializer.toJson<String>(coverPath),
      'filePathsJson': serializer.toJson<String>(filePathsJson),
      'totalDurationMs': serializer.toJson<int>(totalDurationMs),
      'addedAtMs': serializer.toJson<int>(addedAtMs),
      'lastPlayedAtMs': serializer.toJson<int?>(lastPlayedAtMs),
      'lastPositionFilePath': serializer.toJson<String?>(lastPositionFilePath),
      'lastPositionMs': serializer.toJson<int>(lastPositionMs),
      'totalProgress': serializer.toJson<double>(totalProgress),
      'isFinished': serializer.toJson<bool>(isFinished),
    };
  }

  Book copyWith(
          {String? id,
          String? title,
          String? author,
          String? coverPath,
          String? filePathsJson,
          int? totalDurationMs,
          int? addedAtMs,
          Value<int?> lastPlayedAtMs = const Value.absent(),
          Value<String?> lastPositionFilePath = const Value.absent(),
          int? lastPositionMs,
          double? totalProgress,
          bool? isFinished}) =>
      Book(
        id: id ?? this.id,
        title: title ?? this.title,
        author: author ?? this.author,
        coverPath: coverPath ?? this.coverPath,
        filePathsJson: filePathsJson ?? this.filePathsJson,
        totalDurationMs: totalDurationMs ?? this.totalDurationMs,
        addedAtMs: addedAtMs ?? this.addedAtMs,
        lastPlayedAtMs:
            lastPlayedAtMs.present ? lastPlayedAtMs.value : this.lastPlayedAtMs,
        lastPositionFilePath: lastPositionFilePath.present
            ? lastPositionFilePath.value
            : this.lastPositionFilePath,
        lastPositionMs: lastPositionMs ?? this.lastPositionMs,
        totalProgress: totalProgress ?? this.totalProgress,
        isFinished: isFinished ?? this.isFinished,
      );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      filePathsJson: data.filePathsJson.present
          ? data.filePathsJson.value
          : this.filePathsJson,
      totalDurationMs: data.totalDurationMs.present
          ? data.totalDurationMs.value
          : this.totalDurationMs,
      addedAtMs: data.addedAtMs.present ? data.addedAtMs.value : this.addedAtMs,
      lastPlayedAtMs: data.lastPlayedAtMs.present
          ? data.lastPlayedAtMs.value
          : this.lastPlayedAtMs,
      lastPositionFilePath: data.lastPositionFilePath.present
          ? data.lastPositionFilePath.value
          : this.lastPositionFilePath,
      lastPositionMs: data.lastPositionMs.present
          ? data.lastPositionMs.value
          : this.lastPositionMs,
      totalProgress: data.totalProgress.present
          ? data.totalProgress.value
          : this.totalProgress,
      isFinished:
          data.isFinished.present ? data.isFinished.value : this.isFinished,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('coverPath: $coverPath, ')
          ..write('filePathsJson: $filePathsJson, ')
          ..write('totalDurationMs: $totalDurationMs, ')
          ..write('addedAtMs: $addedAtMs, ')
          ..write('lastPlayedAtMs: $lastPlayedAtMs, ')
          ..write('lastPositionFilePath: $lastPositionFilePath, ')
          ..write('lastPositionMs: $lastPositionMs, ')
          ..write('totalProgress: $totalProgress, ')
          ..write('isFinished: $isFinished')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      author,
      coverPath,
      filePathsJson,
      totalDurationMs,
      addedAtMs,
      lastPlayedAtMs,
      lastPositionFilePath,
      lastPositionMs,
      totalProgress,
      isFinished);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.coverPath == this.coverPath &&
          other.filePathsJson == this.filePathsJson &&
          other.totalDurationMs == this.totalDurationMs &&
          other.addedAtMs == this.addedAtMs &&
          other.lastPlayedAtMs == this.lastPlayedAtMs &&
          other.lastPositionFilePath == this.lastPositionFilePath &&
          other.lastPositionMs == this.lastPositionMs &&
          other.totalProgress == this.totalProgress &&
          other.isFinished == this.isFinished);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> author;
  final Value<String> coverPath;
  final Value<String> filePathsJson;
  final Value<int> totalDurationMs;
  final Value<int> addedAtMs;
  final Value<int?> lastPlayedAtMs;
  final Value<String?> lastPositionFilePath;
  final Value<int> lastPositionMs;
  final Value<double> totalProgress;
  final Value<bool> isFinished;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.filePathsJson = const Value.absent(),
    this.totalDurationMs = const Value.absent(),
    this.addedAtMs = const Value.absent(),
    this.lastPlayedAtMs = const Value.absent(),
    this.lastPositionFilePath = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.totalProgress = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    this.author = const Value.absent(),
    this.coverPath = const Value.absent(),
    required String filePathsJson,
    this.totalDurationMs = const Value.absent(),
    required int addedAtMs,
    this.lastPlayedAtMs = const Value.absent(),
    this.lastPositionFilePath = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.totalProgress = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        filePathsJson = Value(filePathsJson),
        addedAtMs = Value(addedAtMs);
  static Insertable<Book> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? coverPath,
    Expression<String>? filePathsJson,
    Expression<int>? totalDurationMs,
    Expression<int>? addedAtMs,
    Expression<int>? lastPlayedAtMs,
    Expression<String>? lastPositionFilePath,
    Expression<int>? lastPositionMs,
    Expression<double>? totalProgress,
    Expression<bool>? isFinished,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (coverPath != null) 'cover_path': coverPath,
      if (filePathsJson != null) 'file_paths_json': filePathsJson,
      if (totalDurationMs != null) 'total_duration_ms': totalDurationMs,
      if (addedAtMs != null) 'added_at_ms': addedAtMs,
      if (lastPlayedAtMs != null) 'last_played_at_ms': lastPlayedAtMs,
      if (lastPositionFilePath != null)
        'last_position_file_path': lastPositionFilePath,
      if (lastPositionMs != null) 'last_position_ms': lastPositionMs,
      if (totalProgress != null) 'total_progress': totalProgress,
      if (isFinished != null) 'is_finished': isFinished,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? author,
      Value<String>? coverPath,
      Value<String>? filePathsJson,
      Value<int>? totalDurationMs,
      Value<int>? addedAtMs,
      Value<int?>? lastPlayedAtMs,
      Value<String?>? lastPositionFilePath,
      Value<int>? lastPositionMs,
      Value<double>? totalProgress,
      Value<bool>? isFinished,
      Value<int>? rowid}) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      filePathsJson: filePathsJson ?? this.filePathsJson,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      addedAtMs: addedAtMs ?? this.addedAtMs,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
      lastPositionFilePath: lastPositionFilePath ?? this.lastPositionFilePath,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      totalProgress: totalProgress ?? this.totalProgress,
      isFinished: isFinished ?? this.isFinished,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (filePathsJson.present) {
      map['file_paths_json'] = Variable<String>(filePathsJson.value);
    }
    if (totalDurationMs.present) {
      map['total_duration_ms'] = Variable<int>(totalDurationMs.value);
    }
    if (addedAtMs.present) {
      map['added_at_ms'] = Variable<int>(addedAtMs.value);
    }
    if (lastPlayedAtMs.present) {
      map['last_played_at_ms'] = Variable<int>(lastPlayedAtMs.value);
    }
    if (lastPositionFilePath.present) {
      map['last_position_file_path'] =
          Variable<String>(lastPositionFilePath.value);
    }
    if (lastPositionMs.present) {
      map['last_position_ms'] = Variable<int>(lastPositionMs.value);
    }
    if (totalProgress.present) {
      map['total_progress'] = Variable<double>(totalProgress.value);
    }
    if (isFinished.present) {
      map['is_finished'] = Variable<bool>(isFinished.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('coverPath: $coverPath, ')
          ..write('filePathsJson: $filePathsJson, ')
          ..write('totalDurationMs: $totalDurationMs, ')
          ..write('addedAtMs: $addedAtMs, ')
          ..write('lastPlayedAtMs: $lastPlayedAtMs, ')
          ..write('lastPositionFilePath: $lastPositionFilePath, ')
          ..write('lastPositionMs: $lastPositionMs, ')
          ..write('totalProgress: $totalProgress, ')
          ..write('isFinished: $isFinished, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookTracksTable extends BookTracks
    with TableInfo<$BookTracksTable, BookTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
      'book_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL REFERENCES books(id) ON DELETE CASCADE');
  static const VerificationMeta _trackIndexMeta =
      const VerificationMeta('trackIndex');
  @override
  late final GeneratedColumn<int> trackIndex = GeneratedColumn<int>(
      'track_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [bookId, trackIndex, filePath, durationMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_tracks';
  @override
  VerificationContext validateIntegrity(Insertable<BookTrack> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(_bookIdMeta,
          bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta));
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('track_index')) {
      context.handle(
          _trackIndexMeta,
          trackIndex.isAcceptableOrUnknown(
              data['track_index']!, _trackIndexMeta));
    } else if (isInserting) {
      context.missing(_trackIndexMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, trackIndex};
  @override
  BookTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookTrack(
      bookId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}book_id'])!,
      trackIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_index'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
    );
  }

  @override
  $BookTracksTable createAlias(String alias) {
    return $BookTracksTable(attachedDatabase, alias);
  }
}

class BookTrack extends DataClass implements Insertable<BookTrack> {
  final String bookId;
  final int trackIndex;
  final String filePath;
  final int? durationMs;
  const BookTrack(
      {required this.bookId,
      required this.trackIndex,
      required this.filePath,
      this.durationMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['track_index'] = Variable<int>(trackIndex);
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    return map;
  }

  BookTracksCompanion toCompanion(bool nullToAbsent) {
    return BookTracksCompanion(
      bookId: Value(bookId),
      trackIndex: Value(trackIndex),
      filePath: Value(filePath),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
    );
  }

  factory BookTrack.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookTrack(
      bookId: serializer.fromJson<String>(json['bookId']),
      trackIndex: serializer.fromJson<int>(json['trackIndex']),
      filePath: serializer.fromJson<String>(json['filePath']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'trackIndex': serializer.toJson<int>(trackIndex),
      'filePath': serializer.toJson<String>(filePath),
      'durationMs': serializer.toJson<int?>(durationMs),
    };
  }

  BookTrack copyWith(
          {String? bookId,
          int? trackIndex,
          String? filePath,
          Value<int?> durationMs = const Value.absent()}) =>
      BookTrack(
        bookId: bookId ?? this.bookId,
        trackIndex: trackIndex ?? this.trackIndex,
        filePath: filePath ?? this.filePath,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
      );
  BookTrack copyWithCompanion(BookTracksCompanion data) {
    return BookTrack(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      trackIndex:
          data.trackIndex.present ? data.trackIndex.value : this.trackIndex,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookTrack(')
          ..write('bookId: $bookId, ')
          ..write('trackIndex: $trackIndex, ')
          ..write('filePath: $filePath, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, trackIndex, filePath, durationMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookTrack &&
          other.bookId == this.bookId &&
          other.trackIndex == this.trackIndex &&
          other.filePath == this.filePath &&
          other.durationMs == this.durationMs);
}

class BookTracksCompanion extends UpdateCompanion<BookTrack> {
  final Value<String> bookId;
  final Value<int> trackIndex;
  final Value<String> filePath;
  final Value<int?> durationMs;
  final Value<int> rowid;
  const BookTracksCompanion({
    this.bookId = const Value.absent(),
    this.trackIndex = const Value.absent(),
    this.filePath = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookTracksCompanion.insert({
    required String bookId,
    required int trackIndex,
    required String filePath,
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : bookId = Value(bookId),
        trackIndex = Value(trackIndex),
        filePath = Value(filePath);
  static Insertable<BookTrack> custom({
    Expression<String>? bookId,
    Expression<int>? trackIndex,
    Expression<String>? filePath,
    Expression<int>? durationMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (trackIndex != null) 'track_index': trackIndex,
      if (filePath != null) 'file_path': filePath,
      if (durationMs != null) 'duration_ms': durationMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookTracksCompanion copyWith(
      {Value<String>? bookId,
      Value<int>? trackIndex,
      Value<String>? filePath,
      Value<int?>? durationMs,
      Value<int>? rowid}) {
    return BookTracksCompanion(
      bookId: bookId ?? this.bookId,
      trackIndex: trackIndex ?? this.trackIndex,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (trackIndex.present) {
      map['track_index'] = Variable<int>(trackIndex.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookTracksCompanion(')
          ..write('bookId: $bookId, ')
          ..write('trackIndex: $trackIndex, ')
          ..write('filePath: $filePath, ')
          ..write('durationMs: $durationMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters with TableInfo<$ChaptersTable, Chapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
      'book_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'REFERENCES books(id) ON DELETE CASCADE');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startMsMeta =
      const VerificationMeta('startMs');
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
      'start_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endMsMeta = const VerificationMeta('endMs');
  @override
  late final GeneratedColumn<int> endMs = GeneratedColumn<int>(
      'end_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _trackIndexMeta =
      const VerificationMeta('trackIndex');
  @override
  late final GeneratedColumn<int> trackIndex = GeneratedColumn<int>(
      'track_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, bookId, title, startMs, endMs, filePath, trackIndex];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(Insertable<Chapter> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(_bookIdMeta,
          bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta));
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('start_ms')) {
      context.handle(_startMsMeta,
          startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta));
    } else if (isInserting) {
      context.missing(_startMsMeta);
    }
    if (data.containsKey('end_ms')) {
      context.handle(
          _endMsMeta, endMs.isAcceptableOrUnknown(data['end_ms']!, _endMsMeta));
    } else if (isInserting) {
      context.missing(_endMsMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    }
    if (data.containsKey('track_index')) {
      context.handle(
          _trackIndexMeta,
          trackIndex.isAcceptableOrUnknown(
              data['track_index']!, _trackIndexMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chapter(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      bookId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}book_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      startMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_ms'])!,
      endMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_ms'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path']),
      trackIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_index'])!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class Chapter extends DataClass implements Insertable<Chapter> {
  final String id;
  final String bookId;
  final String title;
  final int startMs;
  final int endMs;
  final String? filePath;
  final int trackIndex;
  const Chapter(
      {required this.id,
      required this.bookId,
      required this.title,
      required this.startMs,
      required this.endMs,
      this.filePath,
      required this.trackIndex});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['title'] = Variable<String>(title);
    map['start_ms'] = Variable<int>(startMs);
    map['end_ms'] = Variable<int>(endMs);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    map['track_index'] = Variable<int>(trackIndex);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      bookId: Value(bookId),
      title: Value(title),
      startMs: Value(startMs),
      endMs: Value(endMs),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      trackIndex: Value(trackIndex),
    );
  }

  factory Chapter.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chapter(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      title: serializer.fromJson<String>(json['title']),
      startMs: serializer.fromJson<int>(json['startMs']),
      endMs: serializer.fromJson<int>(json['endMs']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      trackIndex: serializer.fromJson<int>(json['trackIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'title': serializer.toJson<String>(title),
      'startMs': serializer.toJson<int>(startMs),
      'endMs': serializer.toJson<int>(endMs),
      'filePath': serializer.toJson<String?>(filePath),
      'trackIndex': serializer.toJson<int>(trackIndex),
    };
  }

  Chapter copyWith(
          {String? id,
          String? bookId,
          String? title,
          int? startMs,
          int? endMs,
          Value<String?> filePath = const Value.absent(),
          int? trackIndex}) =>
      Chapter(
        id: id ?? this.id,
        bookId: bookId ?? this.bookId,
        title: title ?? this.title,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        filePath: filePath.present ? filePath.value : this.filePath,
        trackIndex: trackIndex ?? this.trackIndex,
      );
  Chapter copyWithCompanion(ChaptersCompanion data) {
    return Chapter(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      title: data.title.present ? data.title.value : this.title,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      trackIndex:
          data.trackIndex.present ? data.trackIndex.value : this.trackIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chapter(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('title: $title, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('filePath: $filePath, ')
          ..write('trackIndex: $trackIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bookId, title, startMs, endMs, filePath, trackIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.title == this.title &&
          other.startMs == this.startMs &&
          other.endMs == this.endMs &&
          other.filePath == this.filePath &&
          other.trackIndex == this.trackIndex);
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> title;
  final Value<int> startMs;
  final Value<int> endMs;
  final Value<String?> filePath;
  final Value<int> trackIndex;
  final Value<int> rowid;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.title = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.filePath = const Value.absent(),
    this.trackIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String id,
    required String bookId,
    required String title,
    required int startMs,
    required int endMs,
    this.filePath = const Value.absent(),
    this.trackIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        bookId = Value(bookId),
        title = Value(title),
        startMs = Value(startMs),
        endMs = Value(endMs);
  static Insertable<Chapter> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? title,
    Expression<int>? startMs,
    Expression<int>? endMs,
    Expression<String>? filePath,
    Expression<int>? trackIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (title != null) 'title': title,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (filePath != null) 'file_path': filePath,
      if (trackIndex != null) 'track_index': trackIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChaptersCompanion copyWith(
      {Value<String>? id,
      Value<String>? bookId,
      Value<String>? title,
      Value<int>? startMs,
      Value<int>? endMs,
      Value<String?>? filePath,
      Value<int>? trackIndex,
      Value<int>? rowid}) {
    return ChaptersCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      title: title ?? this.title,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      filePath: filePath ?? this.filePath,
      trackIndex: trackIndex ?? this.trackIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (endMs.present) {
      map['end_ms'] = Variable<int>(endMs.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (trackIndex.present) {
      map['track_index'] = Variable<int>(trackIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('title: $title, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('filePath: $filePath, ')
          ..write('trackIndex: $trackIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
      'book_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'REFERENCES books(id) ON DELETE CASCADE');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('manual'));
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _bookPositionMsMeta =
      const VerificationMeta('bookPositionMs');
  @override
  late final GeneratedColumn<int> bookPositionMs = GeneratedColumn<int>(
      'book_position_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMsMeta =
      const VerificationMeta('createdAtMs');
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
      'created_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _chapterIndexMeta =
      const VerificationMeta('chapterIndex');
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
      'chapter_index', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        bookId,
        title,
        note,
        kind,
        filePath,
        positionMs,
        bookPositionMs,
        createdAtMs,
        chapterIndex
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(Insertable<Bookmark> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(_bookIdMeta,
          bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta));
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
          _positionMsMeta,
          positionMs.isAcceptableOrUnknown(
              data['position_ms']!, _positionMsMeta));
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('book_position_ms')) {
      context.handle(
          _bookPositionMsMeta,
          bookPositionMs.isAcceptableOrUnknown(
              data['book_position_ms']!, _bookPositionMsMeta));
    } else if (isInserting) {
      context.missing(_bookPositionMsMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
          _createdAtMsMeta,
          createdAtMs.isAcceptableOrUnknown(
              data['created_at_ms']!, _createdAtMsMeta));
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
          _chapterIndexMeta,
          chapterIndex.isAcceptableOrUnknown(
              data['chapter_index']!, _chapterIndexMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      bookId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}book_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
      bookPositionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}book_position_ms'])!,
      createdAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at_ms'])!,
      chapterIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chapter_index']),
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class Bookmark extends DataClass implements Insertable<Bookmark> {
  final String id;
  final String bookId;
  final String title;
  final String? note;
  final String kind;
  final String filePath;
  final int positionMs;
  final int bookPositionMs;
  final int createdAtMs;
  final int? chapterIndex;
  const Bookmark(
      {required this.id,
      required this.bookId,
      required this.title,
      this.note,
      required this.kind,
      required this.filePath,
      required this.positionMs,
      required this.bookPositionMs,
      required this.createdAtMs,
      this.chapterIndex});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['kind'] = Variable<String>(kind);
    map['file_path'] = Variable<String>(filePath);
    map['position_ms'] = Variable<int>(positionMs);
    map['book_position_ms'] = Variable<int>(bookPositionMs);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || chapterIndex != null) {
      map['chapter_index'] = Variable<int>(chapterIndex);
    }
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      bookId: Value(bookId),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      kind: Value(kind),
      filePath: Value(filePath),
      positionMs: Value(positionMs),
      bookPositionMs: Value(bookPositionMs),
      createdAtMs: Value(createdAtMs),
      chapterIndex: chapterIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterIndex),
    );
  }

  factory Bookmark.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bookmark(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      kind: serializer.fromJson<String>(json['kind']),
      filePath: serializer.fromJson<String>(json['filePath']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      bookPositionMs: serializer.fromJson<int>(json['bookPositionMs']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      chapterIndex: serializer.fromJson<int?>(json['chapterIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'kind': serializer.toJson<String>(kind),
      'filePath': serializer.toJson<String>(filePath),
      'positionMs': serializer.toJson<int>(positionMs),
      'bookPositionMs': serializer.toJson<int>(bookPositionMs),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'chapterIndex': serializer.toJson<int?>(chapterIndex),
    };
  }

  Bookmark copyWith(
          {String? id,
          String? bookId,
          String? title,
          Value<String?> note = const Value.absent(),
          String? kind,
          String? filePath,
          int? positionMs,
          int? bookPositionMs,
          int? createdAtMs,
          Value<int?> chapterIndex = const Value.absent()}) =>
      Bookmark(
        id: id ?? this.id,
        bookId: bookId ?? this.bookId,
        title: title ?? this.title,
        note: note.present ? note.value : this.note,
        kind: kind ?? this.kind,
        filePath: filePath ?? this.filePath,
        positionMs: positionMs ?? this.positionMs,
        bookPositionMs: bookPositionMs ?? this.bookPositionMs,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        chapterIndex:
            chapterIndex.present ? chapterIndex.value : this.chapterIndex,
      );
  Bookmark copyWithCompanion(BookmarksCompanion data) {
    return Bookmark(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      kind: data.kind.present ? data.kind.value : this.kind,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      positionMs:
          data.positionMs.present ? data.positionMs.value : this.positionMs,
      bookPositionMs: data.bookPositionMs.present
          ? data.bookPositionMs.value
          : this.bookPositionMs,
      createdAtMs:
          data.createdAtMs.present ? data.createdAtMs.value : this.createdAtMs,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Bookmark(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('kind: $kind, ')
          ..write('filePath: $filePath, ')
          ..write('positionMs: $positionMs, ')
          ..write('bookPositionMs: $bookPositionMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('chapterIndex: $chapterIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, bookId, title, note, kind, filePath,
      positionMs, bookPositionMs, createdAtMs, chapterIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bookmark &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.title == this.title &&
          other.note == this.note &&
          other.kind == this.kind &&
          other.filePath == this.filePath &&
          other.positionMs == this.positionMs &&
          other.bookPositionMs == this.bookPositionMs &&
          other.createdAtMs == this.createdAtMs &&
          other.chapterIndex == this.chapterIndex);
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> title;
  final Value<String?> note;
  final Value<String> kind;
  final Value<String> filePath;
  final Value<int> positionMs;
  final Value<int> bookPositionMs;
  final Value<int> createdAtMs;
  final Value<int?> chapterIndex;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.kind = const Value.absent(),
    this.filePath = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.bookPositionMs = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String bookId,
    required String title,
    this.note = const Value.absent(),
    this.kind = const Value.absent(),
    required String filePath,
    required int positionMs,
    required int bookPositionMs,
    required int createdAtMs,
    this.chapterIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        bookId = Value(bookId),
        title = Value(title),
        filePath = Value(filePath),
        positionMs = Value(positionMs),
        bookPositionMs = Value(bookPositionMs),
        createdAtMs = Value(createdAtMs);
  static Insertable<Bookmark> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? kind,
    Expression<String>? filePath,
    Expression<int>? positionMs,
    Expression<int>? bookPositionMs,
    Expression<int>? createdAtMs,
    Expression<int>? chapterIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (kind != null) 'kind': kind,
      if (filePath != null) 'file_path': filePath,
      if (positionMs != null) 'position_ms': positionMs,
      if (bookPositionMs != null) 'book_position_ms': bookPositionMs,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith(
      {Value<String>? id,
      Value<String>? bookId,
      Value<String>? title,
      Value<String?>? note,
      Value<String>? kind,
      Value<String>? filePath,
      Value<int>? positionMs,
      Value<int>? bookPositionMs,
      Value<int>? createdAtMs,
      Value<int?>? chapterIndex,
      Value<int>? rowid}) {
    return BookmarksCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      title: title ?? this.title,
      note: note ?? this.note,
      kind: kind ?? this.kind,
      filePath: filePath ?? this.filePath,
      positionMs: positionMs ?? this.positionMs,
      bookPositionMs: bookPositionMs ?? this.bookPositionMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (bookPositionMs.present) {
      map['book_position_ms'] = Variable<int>(bookPositionMs.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('kind: $kind, ')
          ..write('filePath: $filePath, ')
          ..write('positionMs: $positionMs, ')
          ..write('bookPositionMs: $bookPositionMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ListeningHistoryTable extends ListeningHistory
    with TableInfo<$ListeningHistoryTable, ListeningHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListeningHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
      'book_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'REFERENCES books(id) ON DELETE CASCADE');
  static const VerificationMeta _startedAtMsMeta =
      const VerificationMeta('startedAtMs');
  @override
  late final GeneratedColumn<int> startedAtMs = GeneratedColumn<int>(
      'started_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endedAtMsMeta =
      const VerificationMeta('endedAtMs');
  @override
  late final GeneratedColumn<int> endedAtMs = GeneratedColumn<int>(
      'ended_at_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _startMsMeta =
      const VerificationMeta('startMs');
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
      'start_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _endMsMeta = const VerificationMeta('endMs');
  @override
  late final GeneratedColumn<int> endMs = GeneratedColumn<int>(
      'end_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _listenedMsMeta =
      const VerificationMeta('listenedMs');
  @override
  late final GeneratedColumn<int> listenedMs = GeneratedColumn<int>(
      'listened_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
      'speed', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(1.0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, bookId, startedAtMs, endedAtMs, startMs, endMs, listenedMs, speed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'listening_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<ListeningHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(_bookIdMeta,
          bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta));
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('started_at_ms')) {
      context.handle(
          _startedAtMsMeta,
          startedAtMs.isAcceptableOrUnknown(
              data['started_at_ms']!, _startedAtMsMeta));
    } else if (isInserting) {
      context.missing(_startedAtMsMeta);
    }
    if (data.containsKey('ended_at_ms')) {
      context.handle(
          _endedAtMsMeta,
          endedAtMs.isAcceptableOrUnknown(
              data['ended_at_ms']!, _endedAtMsMeta));
    }
    if (data.containsKey('start_ms')) {
      context.handle(_startMsMeta,
          startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta));
    }
    if (data.containsKey('end_ms')) {
      context.handle(
          _endMsMeta, endMs.isAcceptableOrUnknown(data['end_ms']!, _endMsMeta));
    }
    if (data.containsKey('listened_ms')) {
      context.handle(
          _listenedMsMeta,
          listenedMs.isAcceptableOrUnknown(
              data['listened_ms']!, _listenedMsMeta));
    }
    if (data.containsKey('speed')) {
      context.handle(
          _speedMeta, speed.isAcceptableOrUnknown(data['speed']!, _speedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ListeningHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListeningHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      bookId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}book_id'])!,
      startedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}started_at_ms'])!,
      endedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ended_at_ms']),
      startMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_ms'])!,
      endMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_ms'])!,
      listenedMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}listened_ms'])!,
      speed: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}speed'])!,
    );
  }

  @override
  $ListeningHistoryTable createAlias(String alias) {
    return $ListeningHistoryTable(attachedDatabase, alias);
  }
}

class ListeningHistoryData extends DataClass
    implements Insertable<ListeningHistoryData> {
  final String id;
  final String bookId;
  final int startedAtMs;
  final int? endedAtMs;
  final int startMs;
  final int endMs;
  final int listenedMs;
  final double speed;
  const ListeningHistoryData(
      {required this.id,
      required this.bookId,
      required this.startedAtMs,
      this.endedAtMs,
      required this.startMs,
      required this.endMs,
      required this.listenedMs,
      required this.speed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['started_at_ms'] = Variable<int>(startedAtMs);
    if (!nullToAbsent || endedAtMs != null) {
      map['ended_at_ms'] = Variable<int>(endedAtMs);
    }
    map['start_ms'] = Variable<int>(startMs);
    map['end_ms'] = Variable<int>(endMs);
    map['listened_ms'] = Variable<int>(listenedMs);
    map['speed'] = Variable<double>(speed);
    return map;
  }

  ListeningHistoryCompanion toCompanion(bool nullToAbsent) {
    return ListeningHistoryCompanion(
      id: Value(id),
      bookId: Value(bookId),
      startedAtMs: Value(startedAtMs),
      endedAtMs: endedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtMs),
      startMs: Value(startMs),
      endMs: Value(endMs),
      listenedMs: Value(listenedMs),
      speed: Value(speed),
    );
  }

  factory ListeningHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ListeningHistoryData(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      startedAtMs: serializer.fromJson<int>(json['startedAtMs']),
      endedAtMs: serializer.fromJson<int?>(json['endedAtMs']),
      startMs: serializer.fromJson<int>(json['startMs']),
      endMs: serializer.fromJson<int>(json['endMs']),
      listenedMs: serializer.fromJson<int>(json['listenedMs']),
      speed: serializer.fromJson<double>(json['speed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'startedAtMs': serializer.toJson<int>(startedAtMs),
      'endedAtMs': serializer.toJson<int?>(endedAtMs),
      'startMs': serializer.toJson<int>(startMs),
      'endMs': serializer.toJson<int>(endMs),
      'listenedMs': serializer.toJson<int>(listenedMs),
      'speed': serializer.toJson<double>(speed),
    };
  }

  ListeningHistoryData copyWith(
          {String? id,
          String? bookId,
          int? startedAtMs,
          Value<int?> endedAtMs = const Value.absent(),
          int? startMs,
          int? endMs,
          int? listenedMs,
          double? speed}) =>
      ListeningHistoryData(
        id: id ?? this.id,
        bookId: bookId ?? this.bookId,
        startedAtMs: startedAtMs ?? this.startedAtMs,
        endedAtMs: endedAtMs.present ? endedAtMs.value : this.endedAtMs,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        listenedMs: listenedMs ?? this.listenedMs,
        speed: speed ?? this.speed,
      );
  ListeningHistoryData copyWithCompanion(ListeningHistoryCompanion data) {
    return ListeningHistoryData(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      startedAtMs:
          data.startedAtMs.present ? data.startedAtMs.value : this.startedAtMs,
      endedAtMs: data.endedAtMs.present ? data.endedAtMs.value : this.endedAtMs,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      listenedMs:
          data.listenedMs.present ? data.listenedMs.value : this.listenedMs,
      speed: data.speed.present ? data.speed.value : this.speed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ListeningHistoryData(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('listenedMs: $listenedMs, ')
          ..write('speed: $speed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, bookId, startedAtMs, endedAtMs, startMs, endMs, listenedMs, speed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListeningHistoryData &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.startedAtMs == this.startedAtMs &&
          other.endedAtMs == this.endedAtMs &&
          other.startMs == this.startMs &&
          other.endMs == this.endMs &&
          other.listenedMs == this.listenedMs &&
          other.speed == this.speed);
}

class ListeningHistoryCompanion extends UpdateCompanion<ListeningHistoryData> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<int> startedAtMs;
  final Value<int?> endedAtMs;
  final Value<int> startMs;
  final Value<int> endMs;
  final Value<int> listenedMs;
  final Value<double> speed;
  final Value<int> rowid;
  const ListeningHistoryCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.startedAtMs = const Value.absent(),
    this.endedAtMs = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.listenedMs = const Value.absent(),
    this.speed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ListeningHistoryCompanion.insert({
    required String id,
    required String bookId,
    required int startedAtMs,
    this.endedAtMs = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.listenedMs = const Value.absent(),
    this.speed = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        bookId = Value(bookId),
        startedAtMs = Value(startedAtMs);
  static Insertable<ListeningHistoryData> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<int>? startedAtMs,
    Expression<int>? endedAtMs,
    Expression<int>? startMs,
    Expression<int>? endMs,
    Expression<int>? listenedMs,
    Expression<double>? speed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (startedAtMs != null) 'started_at_ms': startedAtMs,
      if (endedAtMs != null) 'ended_at_ms': endedAtMs,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (listenedMs != null) 'listened_ms': listenedMs,
      if (speed != null) 'speed': speed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ListeningHistoryCompanion copyWith(
      {Value<String>? id,
      Value<String>? bookId,
      Value<int>? startedAtMs,
      Value<int?>? endedAtMs,
      Value<int>? startMs,
      Value<int>? endMs,
      Value<int>? listenedMs,
      Value<double>? speed,
      Value<int>? rowid}) {
    return ListeningHistoryCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      startedAtMs: startedAtMs ?? this.startedAtMs,
      endedAtMs: endedAtMs ?? this.endedAtMs,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      listenedMs: listenedMs ?? this.listenedMs,
      speed: speed ?? this.speed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (startedAtMs.present) {
      map['started_at_ms'] = Variable<int>(startedAtMs.value);
    }
    if (endedAtMs.present) {
      map['ended_at_ms'] = Variable<int>(endedAtMs.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (endMs.present) {
      map['end_ms'] = Variable<int>(endMs.value);
    }
    if (listenedMs.present) {
      map['listened_ms'] = Variable<int>(listenedMs.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListeningHistoryCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('listenedMs: $listenedMs, ')
          ..write('speed: $speed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $BookTracksTable bookTracks = $BookTracksTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $ListeningHistoryTable listeningHistory =
      $ListeningHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [books, bookTracks, chapters, bookmarks, listeningHistory];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('books',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('book_tracks', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('books',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('chapters', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('books',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('bookmarks', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('books',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('listening_history', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$BooksTableCreateCompanionBuilder = BooksCompanion Function({
  required String id,
  required String title,
  Value<String> author,
  Value<String> coverPath,
  required String filePathsJson,
  Value<int> totalDurationMs,
  required int addedAtMs,
  Value<int?> lastPlayedAtMs,
  Value<String?> lastPositionFilePath,
  Value<int> lastPositionMs,
  Value<double> totalProgress,
  Value<bool> isFinished,
  Value<int> rowid,
});
typedef $$BooksTableUpdateCompanionBuilder = BooksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> author,
  Value<String> coverPath,
  Value<String> filePathsJson,
  Value<int> totalDurationMs,
  Value<int> addedAtMs,
  Value<int?> lastPlayedAtMs,
  Value<String?> lastPositionFilePath,
  Value<int> lastPositionMs,
  Value<double> totalProgress,
  Value<bool> isFinished,
  Value<int> rowid,
});

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookTracksTable, List<BookTrack>>
      _bookTracksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.bookTracks,
          aliasName: $_aliasNameGenerator(db.books.id, db.bookTracks.bookId));

  $$BookTracksTableProcessedTableManager get bookTracksRefs {
    final manager = $$BookTracksTableTableManager($_db, $_db.bookTracks)
        .filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookTracksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$ChaptersTable, List<Chapter>> _chaptersRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.chapters,
          aliasName: $_aliasNameGenerator(db.books.id, db.chapters.bookId));

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager($_db, $_db.chapters)
        .filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
      _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.bookmarks,
          aliasName: $_aliasNameGenerator(db.books.id, db.bookmarks.bookId));

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager($_db, $_db.bookmarks)
        .filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$ListeningHistoryTable, List<ListeningHistoryData>>
      _listeningHistoryRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.listeningHistory,
              aliasName: $_aliasNameGenerator(
                  db.books.id, db.listeningHistory.bookId));

  $$ListeningHistoryTableProcessedTableManager get listeningHistoryRefs {
    final manager =
        $$ListeningHistoryTableTableManager($_db, $_db.listeningHistory)
            .filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_listeningHistoryRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverPath => $composableBuilder(
      column: $table.coverPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePathsJson => $composableBuilder(
      column: $table.filePathsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalDurationMs => $composableBuilder(
      column: $table.totalDurationMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get addedAtMs => $composableBuilder(
      column: $table.addedAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPlayedAtMs => $composableBuilder(
      column: $table.lastPlayedAtMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastPositionFilePath => $composableBuilder(
      column: $table.lastPositionFilePath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get totalProgress => $composableBuilder(
      column: $table.totalProgress, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFinished => $composableBuilder(
      column: $table.isFinished, builder: (column) => ColumnFilters(column));

  Expression<bool> bookTracksRefs(
      Expression<bool> Function($$BookTracksTableFilterComposer f) f) {
    final $$BookTracksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.bookTracks,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookTracksTableFilterComposer(
              $db: $db,
              $table: $db.bookTracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> chaptersRefs(
      Expression<bool> Function($$ChaptersTableFilterComposer f) f) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.chapters,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChaptersTableFilterComposer(
              $db: $db,
              $table: $db.chapters,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
      Expression<bool> Function($$BookmarksTableFilterComposer f) f) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.bookmarks,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookmarksTableFilterComposer(
              $db: $db,
              $table: $db.bookmarks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> listeningHistoryRefs(
      Expression<bool> Function($$ListeningHistoryTableFilterComposer f) f) {
    final $$ListeningHistoryTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.listeningHistory,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ListeningHistoryTableFilterComposer(
              $db: $db,
              $table: $db.listeningHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverPath => $composableBuilder(
      column: $table.coverPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePathsJson => $composableBuilder(
      column: $table.filePathsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalDurationMs => $composableBuilder(
      column: $table.totalDurationMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get addedAtMs => $composableBuilder(
      column: $table.addedAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPlayedAtMs => $composableBuilder(
      column: $table.lastPlayedAtMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastPositionFilePath => $composableBuilder(
      column: $table.lastPositionFilePath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get totalProgress => $composableBuilder(
      column: $table.totalProgress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFinished => $composableBuilder(
      column: $table.isFinished, builder: (column) => ColumnOrderings(column));
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get filePathsJson => $composableBuilder(
      column: $table.filePathsJson, builder: (column) => column);

  GeneratedColumn<int> get totalDurationMs => $composableBuilder(
      column: $table.totalDurationMs, builder: (column) => column);

  GeneratedColumn<int> get addedAtMs =>
      $composableBuilder(column: $table.addedAtMs, builder: (column) => column);

  GeneratedColumn<int> get lastPlayedAtMs => $composableBuilder(
      column: $table.lastPlayedAtMs, builder: (column) => column);

  GeneratedColumn<String> get lastPositionFilePath => $composableBuilder(
      column: $table.lastPositionFilePath, builder: (column) => column);

  GeneratedColumn<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs, builder: (column) => column);

  GeneratedColumn<double> get totalProgress => $composableBuilder(
      column: $table.totalProgress, builder: (column) => column);

  GeneratedColumn<bool> get isFinished => $composableBuilder(
      column: $table.isFinished, builder: (column) => column);

  Expression<T> bookTracksRefs<T extends Object>(
      Expression<T> Function($$BookTracksTableAnnotationComposer a) f) {
    final $$BookTracksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.bookTracks,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookTracksTableAnnotationComposer(
              $db: $db,
              $table: $db.bookTracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> chaptersRefs<T extends Object>(
      Expression<T> Function($$ChaptersTableAnnotationComposer a) f) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.chapters,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChaptersTableAnnotationComposer(
              $db: $db,
              $table: $db.chapters,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
      Expression<T> Function($$BookmarksTableAnnotationComposer a) f) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.bookmarks,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookmarksTableAnnotationComposer(
              $db: $db,
              $table: $db.bookmarks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> listeningHistoryRefs<T extends Object>(
      Expression<T> Function($$ListeningHistoryTableAnnotationComposer a) f) {
    final $$ListeningHistoryTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.listeningHistory,
        getReferencedColumn: (t) => t.bookId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ListeningHistoryTableAnnotationComposer(
              $db: $db,
              $table: $db.listeningHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$BooksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BooksTable,
    Book,
    $$BooksTableFilterComposer,
    $$BooksTableOrderingComposer,
    $$BooksTableAnnotationComposer,
    $$BooksTableCreateCompanionBuilder,
    $$BooksTableUpdateCompanionBuilder,
    (Book, $$BooksTableReferences),
    Book,
    PrefetchHooks Function(
        {bool bookTracksRefs,
        bool chaptersRefs,
        bool bookmarksRefs,
        bool listeningHistoryRefs})> {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> author = const Value.absent(),
            Value<String> coverPath = const Value.absent(),
            Value<String> filePathsJson = const Value.absent(),
            Value<int> totalDurationMs = const Value.absent(),
            Value<int> addedAtMs = const Value.absent(),
            Value<int?> lastPlayedAtMs = const Value.absent(),
            Value<String?> lastPositionFilePath = const Value.absent(),
            Value<int> lastPositionMs = const Value.absent(),
            Value<double> totalProgress = const Value.absent(),
            Value<bool> isFinished = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BooksCompanion(
            id: id,
            title: title,
            author: author,
            coverPath: coverPath,
            filePathsJson: filePathsJson,
            totalDurationMs: totalDurationMs,
            addedAtMs: addedAtMs,
            lastPlayedAtMs: lastPlayedAtMs,
            lastPositionFilePath: lastPositionFilePath,
            lastPositionMs: lastPositionMs,
            totalProgress: totalProgress,
            isFinished: isFinished,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            Value<String> author = const Value.absent(),
            Value<String> coverPath = const Value.absent(),
            required String filePathsJson,
            Value<int> totalDurationMs = const Value.absent(),
            required int addedAtMs,
            Value<int?> lastPlayedAtMs = const Value.absent(),
            Value<String?> lastPositionFilePath = const Value.absent(),
            Value<int> lastPositionMs = const Value.absent(),
            Value<double> totalProgress = const Value.absent(),
            Value<bool> isFinished = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BooksCompanion.insert(
            id: id,
            title: title,
            author: author,
            coverPath: coverPath,
            filePathsJson: filePathsJson,
            totalDurationMs: totalDurationMs,
            addedAtMs: addedAtMs,
            lastPlayedAtMs: lastPlayedAtMs,
            lastPositionFilePath: lastPositionFilePath,
            lastPositionMs: lastPositionMs,
            totalProgress: totalProgress,
            isFinished: isFinished,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$BooksTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {bookTracksRefs = false,
              chaptersRefs = false,
              bookmarksRefs = false,
              listeningHistoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (bookTracksRefs) db.bookTracks,
                if (chaptersRefs) db.chapters,
                if (bookmarksRefs) db.bookmarks,
                if (listeningHistoryRefs) db.listeningHistory
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookTracksRefs)
                    await $_getPrefetchedData<Book, $BooksTable, BookTrack>(
                        currentTable: table,
                        referencedTable:
                            $$BooksTableReferences._bookTracksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$BooksTableReferences(db, table, p0)
                                .bookTracksRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.bookId == item.id),
                        typedResults: items),
                  if (chaptersRefs)
                    await $_getPrefetchedData<Book, $BooksTable, Chapter>(
                        currentTable: table,
                        referencedTable:
                            $$BooksTableReferences._chaptersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$BooksTableReferences(db, table, p0).chaptersRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.bookId == item.id),
                        typedResults: items),
                  if (bookmarksRefs)
                    await $_getPrefetchedData<Book, $BooksTable, Bookmark>(
                        currentTable: table,
                        referencedTable:
                            $$BooksTableReferences._bookmarksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$BooksTableReferences(db, table, p0).bookmarksRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.bookId == item.id),
                        typedResults: items),
                  if (listeningHistoryRefs)
                    await $_getPrefetchedData<Book, $BooksTable,
                            ListeningHistoryData>(
                        currentTable: table,
                        referencedTable: $$BooksTableReferences
                            ._listeningHistoryRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$BooksTableReferences(db, table, p0)
                                .listeningHistoryRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.bookId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$BooksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BooksTable,
    Book,
    $$BooksTableFilterComposer,
    $$BooksTableOrderingComposer,
    $$BooksTableAnnotationComposer,
    $$BooksTableCreateCompanionBuilder,
    $$BooksTableUpdateCompanionBuilder,
    (Book, $$BooksTableReferences),
    Book,
    PrefetchHooks Function(
        {bool bookTracksRefs,
        bool chaptersRefs,
        bool bookmarksRefs,
        bool listeningHistoryRefs})>;
typedef $$BookTracksTableCreateCompanionBuilder = BookTracksCompanion Function({
  required String bookId,
  required int trackIndex,
  required String filePath,
  Value<int?> durationMs,
  Value<int> rowid,
});
typedef $$BookTracksTableUpdateCompanionBuilder = BookTracksCompanion Function({
  Value<String> bookId,
  Value<int> trackIndex,
  Value<String> filePath,
  Value<int?> durationMs,
  Value<int> rowid,
});

final class $$BookTracksTableReferences
    extends BaseReferences<_$AppDatabase, $BookTracksTable, BookTrack> {
  $$BookTracksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) => db.books
      .createAlias($_aliasNameGenerator(db.bookTracks.bookId, db.books.id));

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager($_db, $_db.books)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$BookTracksTableFilterComposer
    extends Composer<_$AppDatabase, $BookTracksTable> {
  $$BookTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get trackIndex => $composableBuilder(
      column: $table.trackIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableFilterComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookTracksTable> {
  $$BookTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get trackIndex => $composableBuilder(
      column: $table.trackIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableOrderingComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookTracksTable> {
  $$BookTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get trackIndex => $composableBuilder(
      column: $table.trackIndex, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableAnnotationComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookTracksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BookTracksTable,
    BookTrack,
    $$BookTracksTableFilterComposer,
    $$BookTracksTableOrderingComposer,
    $$BookTracksTableAnnotationComposer,
    $$BookTracksTableCreateCompanionBuilder,
    $$BookTracksTableUpdateCompanionBuilder,
    (BookTrack, $$BookTracksTableReferences),
    BookTrack,
    PrefetchHooks Function({bool bookId})> {
  $$BookTracksTableTableManager(_$AppDatabase db, $BookTracksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> bookId = const Value.absent(),
            Value<int> trackIndex = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BookTracksCompanion(
            bookId: bookId,
            trackIndex: trackIndex,
            filePath: filePath,
            durationMs: durationMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String bookId,
            required int trackIndex,
            required String filePath,
            Value<int?> durationMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BookTracksCompanion.insert(
            bookId: bookId,
            trackIndex: trackIndex,
            filePath: filePath,
            durationMs: durationMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$BookTracksTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (bookId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.bookId,
                    referencedTable:
                        $$BookTracksTableReferences._bookIdTable(db),
                    referencedColumn:
                        $$BookTracksTableReferences._bookIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$BookTracksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BookTracksTable,
    BookTrack,
    $$BookTracksTableFilterComposer,
    $$BookTracksTableOrderingComposer,
    $$BookTracksTableAnnotationComposer,
    $$BookTracksTableCreateCompanionBuilder,
    $$BookTracksTableUpdateCompanionBuilder,
    (BookTrack, $$BookTracksTableReferences),
    BookTrack,
    PrefetchHooks Function({bool bookId})>;
typedef $$ChaptersTableCreateCompanionBuilder = ChaptersCompanion Function({
  required String id,
  required String bookId,
  required String title,
  required int startMs,
  required int endMs,
  Value<String?> filePath,
  Value<int> trackIndex,
  Value<int> rowid,
});
typedef $$ChaptersTableUpdateCompanionBuilder = ChaptersCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<String> title,
  Value<int> startMs,
  Value<int> endMs,
  Value<String?> filePath,
  Value<int> trackIndex,
  Value<int> rowid,
});

final class $$ChaptersTableReferences
    extends BaseReferences<_$AppDatabase, $ChaptersTable, Chapter> {
  $$ChaptersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) => db.books
      .createAlias($_aliasNameGenerator(db.chapters.bookId, db.books.id));

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager($_db, $_db.books)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get trackIndex => $composableBuilder(
      column: $table.trackIndex, builder: (column) => ColumnFilters(column));

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableFilterComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get trackIndex => $composableBuilder(
      column: $table.trackIndex, builder: (column) => ColumnOrderings(column));

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableOrderingComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get endMs =>
      $composableBuilder(column: $table.endMs, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get trackIndex => $composableBuilder(
      column: $table.trackIndex, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableAnnotationComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChaptersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChaptersTable,
    Chapter,
    $$ChaptersTableFilterComposer,
    $$ChaptersTableOrderingComposer,
    $$ChaptersTableAnnotationComposer,
    $$ChaptersTableCreateCompanionBuilder,
    $$ChaptersTableUpdateCompanionBuilder,
    (Chapter, $$ChaptersTableReferences),
    Chapter,
    PrefetchHooks Function({bool bookId})> {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> bookId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> startMs = const Value.absent(),
            Value<int> endMs = const Value.absent(),
            Value<String?> filePath = const Value.absent(),
            Value<int> trackIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChaptersCompanion(
            id: id,
            bookId: bookId,
            title: title,
            startMs: startMs,
            endMs: endMs,
            filePath: filePath,
            trackIndex: trackIndex,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String bookId,
            required String title,
            required int startMs,
            required int endMs,
            Value<String?> filePath = const Value.absent(),
            Value<int> trackIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChaptersCompanion.insert(
            id: id,
            bookId: bookId,
            title: title,
            startMs: startMs,
            endMs: endMs,
            filePath: filePath,
            trackIndex: trackIndex,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ChaptersTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (bookId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.bookId,
                    referencedTable: $$ChaptersTableReferences._bookIdTable(db),
                    referencedColumn:
                        $$ChaptersTableReferences._bookIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ChaptersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChaptersTable,
    Chapter,
    $$ChaptersTableFilterComposer,
    $$ChaptersTableOrderingComposer,
    $$ChaptersTableAnnotationComposer,
    $$ChaptersTableCreateCompanionBuilder,
    $$ChaptersTableUpdateCompanionBuilder,
    (Chapter, $$ChaptersTableReferences),
    Chapter,
    PrefetchHooks Function({bool bookId})>;
typedef $$BookmarksTableCreateCompanionBuilder = BookmarksCompanion Function({
  required String id,
  required String bookId,
  required String title,
  Value<String?> note,
  Value<String> kind,
  required String filePath,
  required int positionMs,
  required int bookPositionMs,
  required int createdAtMs,
  Value<int?> chapterIndex,
  Value<int> rowid,
});
typedef $$BookmarksTableUpdateCompanionBuilder = BookmarksCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<String> title,
  Value<String?> note,
  Value<String> kind,
  Value<String> filePath,
  Value<int> positionMs,
  Value<int> bookPositionMs,
  Value<int> createdAtMs,
  Value<int?> chapterIndex,
  Value<int> rowid,
});

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) => db.books
      .createAlias($_aliasNameGenerator(db.bookmarks.bookId, db.books.id));

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager($_db, $_db.books)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bookPositionMs => $composableBuilder(
      column: $table.bookPositionMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chapterIndex => $composableBuilder(
      column: $table.chapterIndex, builder: (column) => ColumnFilters(column));

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableFilterComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bookPositionMs => $composableBuilder(
      column: $table.bookPositionMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
      column: $table.chapterIndex,
      builder: (column) => ColumnOrderings(column));

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableOrderingComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => column);

  GeneratedColumn<int> get bookPositionMs => $composableBuilder(
      column: $table.bookPositionMs, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
      column: $table.chapterIndex, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableAnnotationComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookmarksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BookmarksTable,
    Bookmark,
    $$BookmarksTableFilterComposer,
    $$BookmarksTableOrderingComposer,
    $$BookmarksTableAnnotationComposer,
    $$BookmarksTableCreateCompanionBuilder,
    $$BookmarksTableUpdateCompanionBuilder,
    (Bookmark, $$BookmarksTableReferences),
    Bookmark,
    PrefetchHooks Function({bool bookId})> {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> bookId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<int> positionMs = const Value.absent(),
            Value<int> bookPositionMs = const Value.absent(),
            Value<int> createdAtMs = const Value.absent(),
            Value<int?> chapterIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BookmarksCompanion(
            id: id,
            bookId: bookId,
            title: title,
            note: note,
            kind: kind,
            filePath: filePath,
            positionMs: positionMs,
            bookPositionMs: bookPositionMs,
            createdAtMs: createdAtMs,
            chapterIndex: chapterIndex,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String bookId,
            required String title,
            Value<String?> note = const Value.absent(),
            Value<String> kind = const Value.absent(),
            required String filePath,
            required int positionMs,
            required int bookPositionMs,
            required int createdAtMs,
            Value<int?> chapterIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BookmarksCompanion.insert(
            id: id,
            bookId: bookId,
            title: title,
            note: note,
            kind: kind,
            filePath: filePath,
            positionMs: positionMs,
            bookPositionMs: bookPositionMs,
            createdAtMs: createdAtMs,
            chapterIndex: chapterIndex,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$BookmarksTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (bookId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.bookId,
                    referencedTable:
                        $$BookmarksTableReferences._bookIdTable(db),
                    referencedColumn:
                        $$BookmarksTableReferences._bookIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$BookmarksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BookmarksTable,
    Bookmark,
    $$BookmarksTableFilterComposer,
    $$BookmarksTableOrderingComposer,
    $$BookmarksTableAnnotationComposer,
    $$BookmarksTableCreateCompanionBuilder,
    $$BookmarksTableUpdateCompanionBuilder,
    (Bookmark, $$BookmarksTableReferences),
    Bookmark,
    PrefetchHooks Function({bool bookId})>;
typedef $$ListeningHistoryTableCreateCompanionBuilder
    = ListeningHistoryCompanion Function({
  required String id,
  required String bookId,
  required int startedAtMs,
  Value<int?> endedAtMs,
  Value<int> startMs,
  Value<int> endMs,
  Value<int> listenedMs,
  Value<double> speed,
  Value<int> rowid,
});
typedef $$ListeningHistoryTableUpdateCompanionBuilder
    = ListeningHistoryCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<int> startedAtMs,
  Value<int?> endedAtMs,
  Value<int> startMs,
  Value<int> endMs,
  Value<int> listenedMs,
  Value<double> speed,
  Value<int> rowid,
});

final class $$ListeningHistoryTableReferences extends BaseReferences<
    _$AppDatabase, $ListeningHistoryTable, ListeningHistoryData> {
  $$ListeningHistoryTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) => db.books.createAlias(
      $_aliasNameGenerator(db.listeningHistory.bookId, db.books.id));

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager($_db, $_db.books)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ListeningHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $ListeningHistoryTable> {
  $$ListeningHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startedAtMs => $composableBuilder(
      column: $table.startedAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endedAtMs => $composableBuilder(
      column: $table.endedAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get listenedMs => $composableBuilder(
      column: $table.listenedMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get speed => $composableBuilder(
      column: $table.speed, builder: (column) => ColumnFilters(column));

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableFilterComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ListeningHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ListeningHistoryTable> {
  $$ListeningHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startedAtMs => $composableBuilder(
      column: $table.startedAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endedAtMs => $composableBuilder(
      column: $table.endedAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get listenedMs => $composableBuilder(
      column: $table.listenedMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get speed => $composableBuilder(
      column: $table.speed, builder: (column) => ColumnOrderings(column));

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableOrderingComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ListeningHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ListeningHistoryTable> {
  $$ListeningHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startedAtMs => $composableBuilder(
      column: $table.startedAtMs, builder: (column) => column);

  GeneratedColumn<int> get endedAtMs =>
      $composableBuilder(column: $table.endedAtMs, builder: (column) => column);

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get endMs =>
      $composableBuilder(column: $table.endMs, builder: (column) => column);

  GeneratedColumn<int> get listenedMs => $composableBuilder(
      column: $table.listenedMs, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookId,
        referencedTable: $db.books,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BooksTableAnnotationComposer(
              $db: $db,
              $table: $db.books,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ListeningHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ListeningHistoryTable,
    ListeningHistoryData,
    $$ListeningHistoryTableFilterComposer,
    $$ListeningHistoryTableOrderingComposer,
    $$ListeningHistoryTableAnnotationComposer,
    $$ListeningHistoryTableCreateCompanionBuilder,
    $$ListeningHistoryTableUpdateCompanionBuilder,
    (ListeningHistoryData, $$ListeningHistoryTableReferences),
    ListeningHistoryData,
    PrefetchHooks Function({bool bookId})> {
  $$ListeningHistoryTableTableManager(
      _$AppDatabase db, $ListeningHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ListeningHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ListeningHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ListeningHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> bookId = const Value.absent(),
            Value<int> startedAtMs = const Value.absent(),
            Value<int?> endedAtMs = const Value.absent(),
            Value<int> startMs = const Value.absent(),
            Value<int> endMs = const Value.absent(),
            Value<int> listenedMs = const Value.absent(),
            Value<double> speed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ListeningHistoryCompanion(
            id: id,
            bookId: bookId,
            startedAtMs: startedAtMs,
            endedAtMs: endedAtMs,
            startMs: startMs,
            endMs: endMs,
            listenedMs: listenedMs,
            speed: speed,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String bookId,
            required int startedAtMs,
            Value<int?> endedAtMs = const Value.absent(),
            Value<int> startMs = const Value.absent(),
            Value<int> endMs = const Value.absent(),
            Value<int> listenedMs = const Value.absent(),
            Value<double> speed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ListeningHistoryCompanion.insert(
            id: id,
            bookId: bookId,
            startedAtMs: startedAtMs,
            endedAtMs: endedAtMs,
            startMs: startMs,
            endMs: endMs,
            listenedMs: listenedMs,
            speed: speed,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ListeningHistoryTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (bookId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.bookId,
                    referencedTable:
                        $$ListeningHistoryTableReferences._bookIdTable(db),
                    referencedColumn:
                        $$ListeningHistoryTableReferences._bookIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ListeningHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ListeningHistoryTable,
    ListeningHistoryData,
    $$ListeningHistoryTableFilterComposer,
    $$ListeningHistoryTableOrderingComposer,
    $$ListeningHistoryTableAnnotationComposer,
    $$ListeningHistoryTableCreateCompanionBuilder,
    $$ListeningHistoryTableUpdateCompanionBuilder,
    (ListeningHistoryData, $$ListeningHistoryTableReferences),
    ListeningHistoryData,
    PrefetchHooks Function({bool bookId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$BookTracksTableTableManager get bookTracks =>
      $$BookTracksTableTableManager(_db, _db.bookTracks);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$ListeningHistoryTableTableManager get listeningHistory =>
      $$ListeningHistoryTableTableManager(_db, _db.listeningHistory);
}
