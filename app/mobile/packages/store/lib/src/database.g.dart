// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DecksTable extends Decks with TableInfo<$DecksTable, Deck> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DecksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _licenseMeta = const VerificationMeta(
    'license',
  );
  @override
  late final GeneratedColumn<String> license = GeneratedColumn<String>(
    'license',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('own'),
  );
  static const VerificationMeta _sourceDeckIdMeta = const VerificationMeta(
    'sourceDeckId',
  );
  @override
  late final GeneratedColumn<String> sourceDeckId = GeneratedColumn<String>(
    'source_deck_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<int> archivedAt = GeneratedColumn<int>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    name,
    description,
    version,
    author,
    license,
    origin,
    sourceDeckId,
    archivedAt,
    updatedAt,
    deletedAt,
    deviceId,
    serverSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'decks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Deck> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('license')) {
      context.handle(
        _licenseMeta,
        license.isAcceptableOrUnknown(data['license']!, _licenseMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('source_deck_id')) {
      context.handle(
        _sourceDeckIdMeta,
        sourceDeckId.isAcceptableOrUnknown(
          data['source_deck_id']!,
          _sourceDeckIdMeta,
        ),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Deck map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Deck(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      license: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      sourceDeckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_deck_id'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
    );
  }

  @override
  $DecksTable createAlias(String alias) {
    return $DecksTable(attachedDatabase, alias);
  }
}

class Deck extends DataClass implements Insertable<Deck> {
  final String id;
  final String? parentId;
  final String name;
  final String? description;

  /// Reserved and unused in v1; §7 needs shared decks not to force a migration.
  final int version;
  final String? author;
  final String? license;
  final String origin;
  final String? sourceDeckId;
  final int? archivedAt;
  final int updatedAt;
  final int? deletedAt;
  final String deviceId;

  /// Null while the row still sits in the outbox (§6.2).
  final int? serverSeq;
  const Deck({
    required this.id,
    this.parentId,
    required this.name,
    this.description,
    required this.version,
    this.author,
    this.license,
    required this.origin,
    this.sourceDeckId,
    this.archivedAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    this.serverSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || license != null) {
      map['license'] = Variable<String>(license);
    }
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || sourceDeckId != null) {
      map['source_deck_id'] = Variable<String>(sourceDeckId);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<int>(archivedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    return map;
  }

  DecksCompanion toCompanion(bool nullToAbsent) {
    return DecksCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      version: Value(version),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      license: license == null && nullToAbsent
          ? const Value.absent()
          : Value(license),
      origin: Value(origin),
      sourceDeckId: sourceDeckId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDeckId),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
    );
  }

  factory Deck.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Deck(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      version: serializer.fromJson<int>(json['version']),
      author: serializer.fromJson<String?>(json['author']),
      license: serializer.fromJson<String?>(json['license']),
      origin: serializer.fromJson<String>(json['origin']),
      sourceDeckId: serializer.fromJson<String?>(json['sourceDeckId']),
      archivedAt: serializer.fromJson<int?>(json['archivedAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'version': serializer.toJson<int>(version),
      'author': serializer.toJson<String?>(author),
      'license': serializer.toJson<String?>(license),
      'origin': serializer.toJson<String>(origin),
      'sourceDeckId': serializer.toJson<String?>(sourceDeckId),
      'archivedAt': serializer.toJson<int?>(archivedAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
    };
  }

  Deck copyWith({
    String? id,
    Value<String?> parentId = const Value.absent(),
    String? name,
    Value<String?> description = const Value.absent(),
    int? version,
    Value<String?> author = const Value.absent(),
    Value<String?> license = const Value.absent(),
    String? origin,
    Value<String?> sourceDeckId = const Value.absent(),
    Value<int?> archivedAt = const Value.absent(),
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
  }) => Deck(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    version: version ?? this.version,
    author: author.present ? author.value : this.author,
    license: license.present ? license.value : this.license,
    origin: origin ?? this.origin,
    sourceDeckId: sourceDeckId.present ? sourceDeckId.value : this.sourceDeckId,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
  );
  Deck copyWithCompanion(DecksCompanion data) {
    return Deck(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      version: data.version.present ? data.version.value : this.version,
      author: data.author.present ? data.author.value : this.author,
      license: data.license.present ? data.license.value : this.license,
      origin: data.origin.present ? data.origin.value : this.origin,
      sourceDeckId: data.sourceDeckId.present
          ? data.sourceDeckId.value
          : this.sourceDeckId,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Deck(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('version: $version, ')
          ..write('author: $author, ')
          ..write('license: $license, ')
          ..write('origin: $origin, ')
          ..write('sourceDeckId: $sourceDeckId, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    parentId,
    name,
    description,
    version,
    author,
    license,
    origin,
    sourceDeckId,
    archivedAt,
    updatedAt,
    deletedAt,
    deviceId,
    serverSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Deck &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.description == this.description &&
          other.version == this.version &&
          other.author == this.author &&
          other.license == this.license &&
          other.origin == this.origin &&
          other.sourceDeckId == this.sourceDeckId &&
          other.archivedAt == this.archivedAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq);
}

class DecksCompanion extends UpdateCompanion<Deck> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String?> description;
  final Value<int> version;
  final Value<String?> author;
  final Value<String?> license;
  final Value<String> origin;
  final Value<String?> sourceDeckId;
  final Value<int?> archivedAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int> rowid;
  const DecksCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.version = const Value.absent(),
    this.author = const Value.absent(),
    this.license = const Value.absent(),
    this.origin = const Value.absent(),
    this.sourceDeckId = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DecksCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.version = const Value.absent(),
    this.author = const Value.absent(),
    this.license = const Value.absent(),
    this.origin = const Value.absent(),
    this.sourceDeckId = const Value.absent(),
    this.archivedAt = const Value.absent(),
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       updatedAt = Value(updatedAt),
       deviceId = Value(deviceId);
  static Insertable<Deck> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? version,
    Expression<String>? author,
    Expression<String>? license,
    Expression<String>? origin,
    Expression<String>? sourceDeckId,
    Expression<int>? archivedAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (version != null) 'version': version,
      if (author != null) 'author': author,
      if (license != null) 'license': license,
      if (origin != null) 'origin': origin,
      if (sourceDeckId != null) 'source_deck_id': sourceDeckId,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DecksCompanion copyWith({
    Value<String>? id,
    Value<String?>? parentId,
    Value<String>? name,
    Value<String?>? description,
    Value<int>? version,
    Value<String?>? author,
    Value<String?>? license,
    Value<String>? origin,
    Value<String?>? sourceDeckId,
    Value<int?>? archivedAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int>? rowid,
  }) {
    return DecksCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      license: license ?? this.license,
      origin: origin ?? this.origin,
      sourceDeckId: sourceDeckId ?? this.sourceDeckId,
      archivedAt: archivedAt ?? this.archivedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (license.present) {
      map['license'] = Variable<String>(license.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (sourceDeckId.present) {
      map['source_deck_id'] = Variable<String>(sourceDeckId.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<int>(archivedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DecksCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('version: $version, ')
          ..write('author: $author, ')
          ..write('license: $license, ')
          ..write('origin: $origin, ')
          ..write('sourceDeckId: $sourceDeckId, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardsTable extends Cards with TableInfo<$CardsTable, Card> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deckIdMeta = const VerificationMeta('deckId');
  @override
  late final GeneratedColumn<String> deckId = GeneratedColumn<String>(
    'deck_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frontMeta = const VerificationMeta('front');
  @override
  late final GeneratedColumn<String> front = GeneratedColumn<String>(
    'front',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backMeta = const VerificationMeta('back');
  @override
  late final GeneratedColumn<String> back = GeneratedColumn<String>(
    'back',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deckId,
    front,
    back,
    tags,
    updatedAt,
    deletedAt,
    deviceId,
    serverSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<Card> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('deck_id')) {
      context.handle(
        _deckIdMeta,
        deckId.isAcceptableOrUnknown(data['deck_id']!, _deckIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deckIdMeta);
    }
    if (data.containsKey('front')) {
      context.handle(
        _frontMeta,
        front.isAcceptableOrUnknown(data['front']!, _frontMeta),
      );
    } else if (isInserting) {
      context.missing(_frontMeta);
    }
    if (data.containsKey('back')) {
      context.handle(
        _backMeta,
        back.isAcceptableOrUnknown(data['back']!, _backMeta),
      );
    } else if (isInserting) {
      context.missing(_backMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Card map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Card(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deck_id'],
      )!,
      front: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}front'],
      )!,
      back: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}back'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
    );
  }

  @override
  $CardsTable createAlias(String alias) {
    return $CardsTable(attachedDatabase, alias);
  }
}

class Card extends DataClass implements Insertable<Card> {
  final String id;
  final String deckId;
  final String front;
  final String back;

  /// A value of the card, not a join table (§5.1): a join table has nowhere to
  /// put a tombstone, so a tag removed offline reappears on sync. Stored as a
  /// JSON array.
  final String tags;
  final int updatedAt;
  final int? deletedAt;
  final String deviceId;
  final int? serverSeq;
  const Card({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.tags,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    this.serverSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['deck_id'] = Variable<String>(deckId);
    map['front'] = Variable<String>(front);
    map['back'] = Variable<String>(back);
    map['tags'] = Variable<String>(tags);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    return map;
  }

  CardsCompanion toCompanion(bool nullToAbsent) {
    return CardsCompanion(
      id: Value(id),
      deckId: Value(deckId),
      front: Value(front),
      back: Value(back),
      tags: Value(tags),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
    );
  }

  factory Card.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Card(
      id: serializer.fromJson<String>(json['id']),
      deckId: serializer.fromJson<String>(json['deckId']),
      front: serializer.fromJson<String>(json['front']),
      back: serializer.fromJson<String>(json['back']),
      tags: serializer.fromJson<String>(json['tags']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deckId': serializer.toJson<String>(deckId),
      'front': serializer.toJson<String>(front),
      'back': serializer.toJson<String>(back),
      'tags': serializer.toJson<String>(tags),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
    };
  }

  Card copyWith({
    String? id,
    String? deckId,
    String? front,
    String? back,
    String? tags,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
  }) => Card(
    id: id ?? this.id,
    deckId: deckId ?? this.deckId,
    front: front ?? this.front,
    back: back ?? this.back,
    tags: tags ?? this.tags,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
  );
  Card copyWithCompanion(CardsCompanion data) {
    return Card(
      id: data.id.present ? data.id.value : this.id,
      deckId: data.deckId.present ? data.deckId.value : this.deckId,
      front: data.front.present ? data.front.value : this.front,
      back: data.back.present ? data.back.value : this.back,
      tags: data.tags.present ? data.tags.value : this.tags,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Card(')
          ..write('id: $id, ')
          ..write('deckId: $deckId, ')
          ..write('front: $front, ')
          ..write('back: $back, ')
          ..write('tags: $tags, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deckId,
    front,
    back,
    tags,
    updatedAt,
    deletedAt,
    deviceId,
    serverSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Card &&
          other.id == this.id &&
          other.deckId == this.deckId &&
          other.front == this.front &&
          other.back == this.back &&
          other.tags == this.tags &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq);
}

class CardsCompanion extends UpdateCompanion<Card> {
  final Value<String> id;
  final Value<String> deckId;
  final Value<String> front;
  final Value<String> back;
  final Value<String> tags;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int> rowid;
  const CardsCompanion({
    this.id = const Value.absent(),
    this.deckId = const Value.absent(),
    this.front = const Value.absent(),
    this.back = const Value.absent(),
    this.tags = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardsCompanion.insert({
    required String id,
    required String deckId,
    required String front,
    required String back,
    this.tags = const Value.absent(),
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deckId = Value(deckId),
       front = Value(front),
       back = Value(back),
       updatedAt = Value(updatedAt),
       deviceId = Value(deviceId);
  static Insertable<Card> custom({
    Expression<String>? id,
    Expression<String>? deckId,
    Expression<String>? front,
    Expression<String>? back,
    Expression<String>? tags,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deckId != null) 'deck_id': deckId,
      if (front != null) 'front': front,
      if (back != null) 'back': back,
      if (tags != null) 'tags': tags,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardsCompanion copyWith({
    Value<String>? id,
    Value<String>? deckId,
    Value<String>? front,
    Value<String>? back,
    Value<String>? tags,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int>? rowid,
  }) {
    return CardsCompanion(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      front: front ?? this.front,
      back: back ?? this.back,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deckId.present) {
      map['deck_id'] = Variable<String>(deckId.value);
    }
    if (front.present) {
      map['front'] = Variable<String>(front.value);
    }
    if (back.present) {
      map['back'] = Variable<String>(back.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardsCompanion(')
          ..write('id: $id, ')
          ..write('deckId: $deckId, ')
          ..write('front: $front, ')
          ..write('back: $back, ')
          ..write('tags: $tags, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardFlagsTable extends CardFlags
    with TableInfo<$CardFlagsTable, CardFlag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardFlagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _buriedUntilMeta = const VerificationMeta(
    'buriedUntil',
  );
  @override
  late final GeneratedColumn<int> buriedUntil = GeneratedColumn<int>(
    'buried_until',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    cardId,
    status,
    buriedUntil,
    updatedAt,
    deviceId,
    serverSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_flags';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardFlag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('buried_until')) {
      context.handle(
        _buriedUntilMeta,
        buriedUntil.isAcceptableOrUnknown(
          data['buried_until']!,
          _buriedUntilMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cardId};
  @override
  CardFlag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardFlag(
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      buriedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}buried_until'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
    );
  }

  @override
  $CardFlagsTable createAlias(String alias) {
    return $CardFlagsTable(attachedDatabase, alias);
  }
}

class CardFlag extends DataClass implements Insertable<CardFlag> {
  final String cardId;
  final String status;
  final int? buriedUntil;
  final int updatedAt;
  final String deviceId;
  final int? serverSeq;
  const CardFlag({
    required this.cardId,
    required this.status,
    this.buriedUntil,
    required this.updatedAt,
    required this.deviceId,
    this.serverSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['card_id'] = Variable<String>(cardId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || buriedUntil != null) {
      map['buried_until'] = Variable<int>(buriedUntil);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    return map;
  }

  CardFlagsCompanion toCompanion(bool nullToAbsent) {
    return CardFlagsCompanion(
      cardId: Value(cardId),
      status: Value(status),
      buriedUntil: buriedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(buriedUntil),
      updatedAt: Value(updatedAt),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
    );
  }

  factory CardFlag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardFlag(
      cardId: serializer.fromJson<String>(json['cardId']),
      status: serializer.fromJson<String>(json['status']),
      buriedUntil: serializer.fromJson<int?>(json['buriedUntil']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cardId': serializer.toJson<String>(cardId),
      'status': serializer.toJson<String>(status),
      'buriedUntil': serializer.toJson<int?>(buriedUntil),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
    };
  }

  CardFlag copyWith({
    String? cardId,
    String? status,
    Value<int?> buriedUntil = const Value.absent(),
    int? updatedAt,
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
  }) => CardFlag(
    cardId: cardId ?? this.cardId,
    status: status ?? this.status,
    buriedUntil: buriedUntil.present ? buriedUntil.value : this.buriedUntil,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
  );
  CardFlag copyWithCompanion(CardFlagsCompanion data) {
    return CardFlag(
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      status: data.status.present ? data.status.value : this.status,
      buriedUntil: data.buriedUntil.present
          ? data.buriedUntil.value
          : this.buriedUntil,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardFlag(')
          ..write('cardId: $cardId, ')
          ..write('status: $status, ')
          ..write('buriedUntil: $buriedUntil, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cardId, status, buriedUntil, updatedAt, deviceId, serverSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardFlag &&
          other.cardId == this.cardId &&
          other.status == this.status &&
          other.buriedUntil == this.buriedUntil &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq);
}

class CardFlagsCompanion extends UpdateCompanion<CardFlag> {
  final Value<String> cardId;
  final Value<String> status;
  final Value<int?> buriedUntil;
  final Value<int> updatedAt;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int> rowid;
  const CardFlagsCompanion({
    this.cardId = const Value.absent(),
    this.status = const Value.absent(),
    this.buriedUntil = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardFlagsCompanion.insert({
    required String cardId,
    this.status = const Value.absent(),
    this.buriedUntil = const Value.absent(),
    required int updatedAt,
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : cardId = Value(cardId),
       updatedAt = Value(updatedAt),
       deviceId = Value(deviceId);
  static Insertable<CardFlag> custom({
    Expression<String>? cardId,
    Expression<String>? status,
    Expression<int>? buriedUntil,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cardId != null) 'card_id': cardId,
      if (status != null) 'status': status,
      if (buriedUntil != null) 'buried_until': buriedUntil,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardFlagsCompanion copyWith({
    Value<String>? cardId,
    Value<String>? status,
    Value<int?>? buriedUntil,
    Value<int>? updatedAt,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int>? rowid,
  }) {
    return CardFlagsCompanion(
      cardId: cardId ?? this.cardId,
      status: status ?? this.status,
      buriedUntil: buriedUntil ?? this.buriedUntil,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (buriedUntil.present) {
      map['buried_until'] = Variable<int>(buriedUntil.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardFlagsCompanion(')
          ..write('cardId: $cardId, ')
          ..write('status: $status, ')
          ..write('buriedUntil: $buriedUntil, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewsTable extends Reviews with TableInfo<$ReviewsTable, Review> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<int> reviewedAt = GeneratedColumn<int>(
    'reviewed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gradeMeta = const VerificationMeta('grade');
  @override
  late final GeneratedColumn<int> grade = GeneratedColumn<int>(
    'grade',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _elapsedMsMeta = const VerificationMeta(
    'elapsedMs',
  );
  @override
  late final GeneratedColumn<int> elapsedMs = GeneratedColumn<int>(
    'elapsed_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intervalDaysAfterMeta = const VerificationMeta(
    'intervalDaysAfter',
  );
  @override
  late final GeneratedColumn<int> intervalDaysAfter = GeneratedColumn<int>(
    'interval_days_after',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stabilityAfterMeta = const VerificationMeta(
    'stabilityAfter',
  );
  @override
  late final GeneratedColumn<double> stabilityAfter = GeneratedColumn<double>(
    'stability_after',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _difficultyAfterMeta = const VerificationMeta(
    'difficultyAfter',
  );
  @override
  late final GeneratedColumn<double> difficultyAfter = GeneratedColumn<double>(
    'difficulty_after',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _schedulerVersionMeta = const VerificationMeta(
    'schedulerVersion',
  );
  @override
  late final GeneratedColumn<int> schedulerVersion = GeneratedColumn<int>(
    'scheduler_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cardId,
    reviewedAt,
    grade,
    source,
    elapsedMs,
    deviceId,
    serverSeq,
    intervalDaysAfter,
    stabilityAfter,
    difficultyAfter,
    schedulerVersion,
    appVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reviews';
  @override
  VerificationContext validateIntegrity(
    Insertable<Review> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewedAtMeta);
    }
    if (data.containsKey('grade')) {
      context.handle(
        _gradeMeta,
        grade.isAcceptableOrUnknown(data['grade']!, _gradeMeta),
      );
    } else if (isInserting) {
      context.missing(_gradeMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('elapsed_ms')) {
      context.handle(
        _elapsedMsMeta,
        elapsedMs.isAcceptableOrUnknown(data['elapsed_ms']!, _elapsedMsMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    if (data.containsKey('interval_days_after')) {
      context.handle(
        _intervalDaysAfterMeta,
        intervalDaysAfter.isAcceptableOrUnknown(
          data['interval_days_after']!,
          _intervalDaysAfterMeta,
        ),
      );
    }
    if (data.containsKey('stability_after')) {
      context.handle(
        _stabilityAfterMeta,
        stabilityAfter.isAcceptableOrUnknown(
          data['stability_after']!,
          _stabilityAfterMeta,
        ),
      );
    }
    if (data.containsKey('difficulty_after')) {
      context.handle(
        _difficultyAfterMeta,
        difficultyAfter.isAcceptableOrUnknown(
          data['difficulty_after']!,
          _difficultyAfterMeta,
        ),
      );
    }
    if (data.containsKey('scheduler_version')) {
      context.handle(
        _schedulerVersionMeta,
        schedulerVersion.isAcceptableOrUnknown(
          data['scheduler_version']!,
          _schedulerVersionMeta,
        ),
      );
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Review map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Review(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reviewed_at'],
      )!,
      grade: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}grade'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      elapsedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_ms'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
      intervalDaysAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_days_after'],
      ),
      stabilityAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stability_after'],
      ),
      difficultyAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty_after'],
      ),
      schedulerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduler_version'],
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      ),
    );
  }

  @override
  $ReviewsTable createAlias(String alias) {
    return $ReviewsTable(attachedDatabase, alias);
  }
}

class Review extends DataClass implements Insertable<Review> {
  final String id;
  final String cardId;
  final int reviewedAt;
  final int grade;
  final String source;
  final int? elapsedMs;
  final String deviceId;
  final int? serverSeq;

  /// Written once, advisory, never authoritative (§5.2).
  final int? intervalDaysAfter;
  final double? stabilityAfter;
  final double? difficultyAfter;

  /// §5.2 — what the app actually did at the time, so an algorithm change
  /// later can be reasoned about. Present on the server since the first
  /// migration; the client was missing them, which is how a pull of another
  /// device's reviews came to fail on an unknown column.
  final int? schedulerVersion;
  final String? appVersion;
  const Review({
    required this.id,
    required this.cardId,
    required this.reviewedAt,
    required this.grade,
    required this.source,
    this.elapsedMs,
    required this.deviceId,
    this.serverSeq,
    this.intervalDaysAfter,
    this.stabilityAfter,
    this.difficultyAfter,
    this.schedulerVersion,
    this.appVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_id'] = Variable<String>(cardId);
    map['reviewed_at'] = Variable<int>(reviewedAt);
    map['grade'] = Variable<int>(grade);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || elapsedMs != null) {
      map['elapsed_ms'] = Variable<int>(elapsedMs);
    }
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    if (!nullToAbsent || intervalDaysAfter != null) {
      map['interval_days_after'] = Variable<int>(intervalDaysAfter);
    }
    if (!nullToAbsent || stabilityAfter != null) {
      map['stability_after'] = Variable<double>(stabilityAfter);
    }
    if (!nullToAbsent || difficultyAfter != null) {
      map['difficulty_after'] = Variable<double>(difficultyAfter);
    }
    if (!nullToAbsent || schedulerVersion != null) {
      map['scheduler_version'] = Variable<int>(schedulerVersion);
    }
    if (!nullToAbsent || appVersion != null) {
      map['app_version'] = Variable<String>(appVersion);
    }
    return map;
  }

  ReviewsCompanion toCompanion(bool nullToAbsent) {
    return ReviewsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      reviewedAt: Value(reviewedAt),
      grade: Value(grade),
      source: Value(source),
      elapsedMs: elapsedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(elapsedMs),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
      intervalDaysAfter: intervalDaysAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(intervalDaysAfter),
      stabilityAfter: stabilityAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(stabilityAfter),
      difficultyAfter: difficultyAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(difficultyAfter),
      schedulerVersion: schedulerVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(schedulerVersion),
      appVersion: appVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(appVersion),
    );
  }

  factory Review.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Review(
      id: serializer.fromJson<String>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      reviewedAt: serializer.fromJson<int>(json['reviewedAt']),
      grade: serializer.fromJson<int>(json['grade']),
      source: serializer.fromJson<String>(json['source']),
      elapsedMs: serializer.fromJson<int?>(json['elapsedMs']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
      intervalDaysAfter: serializer.fromJson<int?>(json['intervalDaysAfter']),
      stabilityAfter: serializer.fromJson<double?>(json['stabilityAfter']),
      difficultyAfter: serializer.fromJson<double?>(json['difficultyAfter']),
      schedulerVersion: serializer.fromJson<int?>(json['schedulerVersion']),
      appVersion: serializer.fromJson<String?>(json['appVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardId': serializer.toJson<String>(cardId),
      'reviewedAt': serializer.toJson<int>(reviewedAt),
      'grade': serializer.toJson<int>(grade),
      'source': serializer.toJson<String>(source),
      'elapsedMs': serializer.toJson<int?>(elapsedMs),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
      'intervalDaysAfter': serializer.toJson<int?>(intervalDaysAfter),
      'stabilityAfter': serializer.toJson<double?>(stabilityAfter),
      'difficultyAfter': serializer.toJson<double?>(difficultyAfter),
      'schedulerVersion': serializer.toJson<int?>(schedulerVersion),
      'appVersion': serializer.toJson<String?>(appVersion),
    };
  }

  Review copyWith({
    String? id,
    String? cardId,
    int? reviewedAt,
    int? grade,
    String? source,
    Value<int?> elapsedMs = const Value.absent(),
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
    Value<int?> intervalDaysAfter = const Value.absent(),
    Value<double?> stabilityAfter = const Value.absent(),
    Value<double?> difficultyAfter = const Value.absent(),
    Value<int?> schedulerVersion = const Value.absent(),
    Value<String?> appVersion = const Value.absent(),
  }) => Review(
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    grade: grade ?? this.grade,
    source: source ?? this.source,
    elapsedMs: elapsedMs.present ? elapsedMs.value : this.elapsedMs,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
    intervalDaysAfter: intervalDaysAfter.present
        ? intervalDaysAfter.value
        : this.intervalDaysAfter,
    stabilityAfter: stabilityAfter.present
        ? stabilityAfter.value
        : this.stabilityAfter,
    difficultyAfter: difficultyAfter.present
        ? difficultyAfter.value
        : this.difficultyAfter,
    schedulerVersion: schedulerVersion.present
        ? schedulerVersion.value
        : this.schedulerVersion,
    appVersion: appVersion.present ? appVersion.value : this.appVersion,
  );
  Review copyWithCompanion(ReviewsCompanion data) {
    return Review(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
      grade: data.grade.present ? data.grade.value : this.grade,
      source: data.source.present ? data.source.value : this.source,
      elapsedMs: data.elapsedMs.present ? data.elapsedMs.value : this.elapsedMs,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
      intervalDaysAfter: data.intervalDaysAfter.present
          ? data.intervalDaysAfter.value
          : this.intervalDaysAfter,
      stabilityAfter: data.stabilityAfter.present
          ? data.stabilityAfter.value
          : this.stabilityAfter,
      difficultyAfter: data.difficultyAfter.present
          ? data.difficultyAfter.value
          : this.difficultyAfter,
      schedulerVersion: data.schedulerVersion.present
          ? data.schedulerVersion.value
          : this.schedulerVersion,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Review(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('grade: $grade, ')
          ..write('source: $source, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('intervalDaysAfter: $intervalDaysAfter, ')
          ..write('stabilityAfter: $stabilityAfter, ')
          ..write('difficultyAfter: $difficultyAfter, ')
          ..write('schedulerVersion: $schedulerVersion, ')
          ..write('appVersion: $appVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cardId,
    reviewedAt,
    grade,
    source,
    elapsedMs,
    deviceId,
    serverSeq,
    intervalDaysAfter,
    stabilityAfter,
    difficultyAfter,
    schedulerVersion,
    appVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Review &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.reviewedAt == this.reviewedAt &&
          other.grade == this.grade &&
          other.source == this.source &&
          other.elapsedMs == this.elapsedMs &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq &&
          other.intervalDaysAfter == this.intervalDaysAfter &&
          other.stabilityAfter == this.stabilityAfter &&
          other.difficultyAfter == this.difficultyAfter &&
          other.schedulerVersion == this.schedulerVersion &&
          other.appVersion == this.appVersion);
}

class ReviewsCompanion extends UpdateCompanion<Review> {
  final Value<String> id;
  final Value<String> cardId;
  final Value<int> reviewedAt;
  final Value<int> grade;
  final Value<String> source;
  final Value<int?> elapsedMs;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int?> intervalDaysAfter;
  final Value<double?> stabilityAfter;
  final Value<double?> difficultyAfter;
  final Value<int?> schedulerVersion;
  final Value<String?> appVersion;
  final Value<int> rowid;
  const ReviewsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.grade = const Value.absent(),
    this.source = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.intervalDaysAfter = const Value.absent(),
    this.stabilityAfter = const Value.absent(),
    this.difficultyAfter = const Value.absent(),
    this.schedulerVersion = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewsCompanion.insert({
    required String id,
    required String cardId,
    required int reviewedAt,
    required int grade,
    required String source,
    this.elapsedMs = const Value.absent(),
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.intervalDaysAfter = const Value.absent(),
    this.stabilityAfter = const Value.absent(),
    this.difficultyAfter = const Value.absent(),
    this.schedulerVersion = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cardId = Value(cardId),
       reviewedAt = Value(reviewedAt),
       grade = Value(grade),
       source = Value(source),
       deviceId = Value(deviceId);
  static Insertable<Review> custom({
    Expression<String>? id,
    Expression<String>? cardId,
    Expression<int>? reviewedAt,
    Expression<int>? grade,
    Expression<String>? source,
    Expression<int>? elapsedMs,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? intervalDaysAfter,
    Expression<double>? stabilityAfter,
    Expression<double>? difficultyAfter,
    Expression<int>? schedulerVersion,
    Expression<String>? appVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (grade != null) 'grade': grade,
      if (source != null) 'source': source,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (intervalDaysAfter != null) 'interval_days_after': intervalDaysAfter,
      if (stabilityAfter != null) 'stability_after': stabilityAfter,
      if (difficultyAfter != null) 'difficulty_after': difficultyAfter,
      if (schedulerVersion != null) 'scheduler_version': schedulerVersion,
      if (appVersion != null) 'app_version': appVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewsCompanion copyWith({
    Value<String>? id,
    Value<String>? cardId,
    Value<int>? reviewedAt,
    Value<int>? grade,
    Value<String>? source,
    Value<int?>? elapsedMs,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int?>? intervalDaysAfter,
    Value<double?>? stabilityAfter,
    Value<double?>? difficultyAfter,
    Value<int?>? schedulerVersion,
    Value<String?>? appVersion,
    Value<int>? rowid,
  }) {
    return ReviewsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      grade: grade ?? this.grade,
      source: source ?? this.source,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      intervalDaysAfter: intervalDaysAfter ?? this.intervalDaysAfter,
      stabilityAfter: stabilityAfter ?? this.stabilityAfter,
      difficultyAfter: difficultyAfter ?? this.difficultyAfter,
      schedulerVersion: schedulerVersion ?? this.schedulerVersion,
      appVersion: appVersion ?? this.appVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<int>(reviewedAt.value);
    }
    if (grade.present) {
      map['grade'] = Variable<int>(grade.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (elapsedMs.present) {
      map['elapsed_ms'] = Variable<int>(elapsedMs.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (intervalDaysAfter.present) {
      map['interval_days_after'] = Variable<int>(intervalDaysAfter.value);
    }
    if (stabilityAfter.present) {
      map['stability_after'] = Variable<double>(stabilityAfter.value);
    }
    if (difficultyAfter.present) {
      map['difficulty_after'] = Variable<double>(difficultyAfter.value);
    }
    if (schedulerVersion.present) {
      map['scheduler_version'] = Variable<int>(schedulerVersion.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('grade: $grade, ')
          ..write('source: $source, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('intervalDaysAfter: $intervalDaysAfter, ')
          ..write('stabilityAfter: $stabilityAfter, ')
          ..write('difficultyAfter: $difficultyAfter, ')
          ..write('schedulerVersion: $schedulerVersion, ')
          ..write('appVersion: $appVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressResetsTable extends ProgressResets
    with TableInfo<$ProgressResetsTable, ProgressReset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressResetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resetAtMeta = const VerificationMeta(
    'resetAt',
  );
  @override
  late final GeneratedColumn<int> resetAt = GeneratedColumn<int>(
    'reset_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cardId,
    resetAt,
    deviceId,
    serverSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_resets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressReset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('reset_at')) {
      context.handle(
        _resetAtMeta,
        resetAt.isAcceptableOrUnknown(data['reset_at']!, _resetAtMeta),
      );
    } else if (isInserting) {
      context.missing(_resetAtMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgressReset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressReset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      resetAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reset_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
    );
  }

  @override
  $ProgressResetsTable createAlias(String alias) {
    return $ProgressResetsTable(attachedDatabase, alias);
  }
}

class ProgressReset extends DataClass implements Insertable<ProgressReset> {
  final String id;
  final String cardId;
  final int resetAt;
  final String deviceId;
  final int? serverSeq;
  const ProgressReset({
    required this.id,
    required this.cardId,
    required this.resetAt,
    required this.deviceId,
    this.serverSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_id'] = Variable<String>(cardId);
    map['reset_at'] = Variable<int>(resetAt);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    return map;
  }

  ProgressResetsCompanion toCompanion(bool nullToAbsent) {
    return ProgressResetsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      resetAt: Value(resetAt),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
    );
  }

  factory ProgressReset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressReset(
      id: serializer.fromJson<String>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      resetAt: serializer.fromJson<int>(json['resetAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardId': serializer.toJson<String>(cardId),
      'resetAt': serializer.toJson<int>(resetAt),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
    };
  }

  ProgressReset copyWith({
    String? id,
    String? cardId,
    int? resetAt,
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
  }) => ProgressReset(
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    resetAt: resetAt ?? this.resetAt,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
  );
  ProgressReset copyWithCompanion(ProgressResetsCompanion data) {
    return ProgressReset(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      resetAt: data.resetAt.present ? data.resetAt.value : this.resetAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressReset(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('resetAt: $resetAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cardId, resetAt, deviceId, serverSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressReset &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.resetAt == this.resetAt &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq);
}

class ProgressResetsCompanion extends UpdateCompanion<ProgressReset> {
  final Value<String> id;
  final Value<String> cardId;
  final Value<int> resetAt;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int> rowid;
  const ProgressResetsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.resetAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressResetsCompanion.insert({
    required String id,
    required String cardId,
    required int resetAt,
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cardId = Value(cardId),
       resetAt = Value(resetAt),
       deviceId = Value(deviceId);
  static Insertable<ProgressReset> custom({
    Expression<String>? id,
    Expression<String>? cardId,
    Expression<int>? resetAt,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (resetAt != null) 'reset_at': resetAt,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressResetsCompanion copyWith({
    Value<String>? id,
    Value<String>? cardId,
    Value<int>? resetAt,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int>? rowid,
  }) {
    return ProgressResetsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      resetAt: resetAt ?? this.resetAt,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (resetAt.present) {
      map['reset_at'] = Variable<int>(resetAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressResetsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('resetAt: $resetAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoalHistoryTable extends GoalHistory
    with TableInfo<$GoalHistoryTable, GoalHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectiveFromLocalDateMeta =
      const VerificationMeta('effectiveFromLocalDate');
  @override
  late final GeneratedColumn<String> effectiveFromLocalDate =
      GeneratedColumn<String>(
        'effective_from_local_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _dailyGoalMeta = const VerificationMeta(
    'dailyGoal',
  );
  @override
  late final GeneratedColumn<int> dailyGoal = GeneratedColumn<int>(
    'daily_goal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    effectiveFromLocalDate,
    dailyGoal,
    createdAt,
    deviceId,
    serverSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goal_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoalHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('effective_from_local_date')) {
      context.handle(
        _effectiveFromLocalDateMeta,
        effectiveFromLocalDate.isAcceptableOrUnknown(
          data['effective_from_local_date']!,
          _effectiveFromLocalDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveFromLocalDateMeta);
    }
    if (data.containsKey('daily_goal')) {
      context.handle(
        _dailyGoalMeta,
        dailyGoal.isAcceptableOrUnknown(data['daily_goal']!, _dailyGoalMeta),
      );
    } else if (isInserting) {
      context.missing(_dailyGoalMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GoalHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoalHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      effectiveFromLocalDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_from_local_date'],
      )!,
      dailyGoal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_goal'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
    );
  }

  @override
  $GoalHistoryTable createAlias(String alias) {
    return $GoalHistoryTable(attachedDatabase, alias);
  }
}

class GoalHistoryData extends DataClass implements Insertable<GoalHistoryData> {
  final String id;

  /// Local date as `YYYY-MM-DD`, already bucketed by the day-cutoff rule.
  final String effectiveFromLocalDate;
  final int dailyGoal;
  final int createdAt;
  final String deviceId;
  final int? serverSeq;
  const GoalHistoryData({
    required this.id,
    required this.effectiveFromLocalDate,
    required this.dailyGoal,
    required this.createdAt,
    required this.deviceId,
    this.serverSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['effective_from_local_date'] = Variable<String>(effectiveFromLocalDate);
    map['daily_goal'] = Variable<int>(dailyGoal);
    map['created_at'] = Variable<int>(createdAt);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    return map;
  }

  GoalHistoryCompanion toCompanion(bool nullToAbsent) {
    return GoalHistoryCompanion(
      id: Value(id),
      effectiveFromLocalDate: Value(effectiveFromLocalDate),
      dailyGoal: Value(dailyGoal),
      createdAt: Value(createdAt),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
    );
  }

  factory GoalHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoalHistoryData(
      id: serializer.fromJson<String>(json['id']),
      effectiveFromLocalDate: serializer.fromJson<String>(
        json['effectiveFromLocalDate'],
      ),
      dailyGoal: serializer.fromJson<int>(json['dailyGoal']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'effectiveFromLocalDate': serializer.toJson<String>(
        effectiveFromLocalDate,
      ),
      'dailyGoal': serializer.toJson<int>(dailyGoal),
      'createdAt': serializer.toJson<int>(createdAt),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
    };
  }

  GoalHistoryData copyWith({
    String? id,
    String? effectiveFromLocalDate,
    int? dailyGoal,
    int? createdAt,
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
  }) => GoalHistoryData(
    id: id ?? this.id,
    effectiveFromLocalDate:
        effectiveFromLocalDate ?? this.effectiveFromLocalDate,
    dailyGoal: dailyGoal ?? this.dailyGoal,
    createdAt: createdAt ?? this.createdAt,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
  );
  GoalHistoryData copyWithCompanion(GoalHistoryCompanion data) {
    return GoalHistoryData(
      id: data.id.present ? data.id.value : this.id,
      effectiveFromLocalDate: data.effectiveFromLocalDate.present
          ? data.effectiveFromLocalDate.value
          : this.effectiveFromLocalDate,
      dailyGoal: data.dailyGoal.present ? data.dailyGoal.value : this.dailyGoal,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoalHistoryData(')
          ..write('id: $id, ')
          ..write('effectiveFromLocalDate: $effectiveFromLocalDate, ')
          ..write('dailyGoal: $dailyGoal, ')
          ..write('createdAt: $createdAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    effectiveFromLocalDate,
    dailyGoal,
    createdAt,
    deviceId,
    serverSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoalHistoryData &&
          other.id == this.id &&
          other.effectiveFromLocalDate == this.effectiveFromLocalDate &&
          other.dailyGoal == this.dailyGoal &&
          other.createdAt == this.createdAt &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq);
}

class GoalHistoryCompanion extends UpdateCompanion<GoalHistoryData> {
  final Value<String> id;
  final Value<String> effectiveFromLocalDate;
  final Value<int> dailyGoal;
  final Value<int> createdAt;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int> rowid;
  const GoalHistoryCompanion({
    this.id = const Value.absent(),
    this.effectiveFromLocalDate = const Value.absent(),
    this.dailyGoal = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoalHistoryCompanion.insert({
    required String id,
    required String effectiveFromLocalDate,
    required int dailyGoal,
    required int createdAt,
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       effectiveFromLocalDate = Value(effectiveFromLocalDate),
       dailyGoal = Value(dailyGoal),
       createdAt = Value(createdAt),
       deviceId = Value(deviceId);
  static Insertable<GoalHistoryData> custom({
    Expression<String>? id,
    Expression<String>? effectiveFromLocalDate,
    Expression<int>? dailyGoal,
    Expression<int>? createdAt,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (effectiveFromLocalDate != null)
        'effective_from_local_date': effectiveFromLocalDate,
      if (dailyGoal != null) 'daily_goal': dailyGoal,
      if (createdAt != null) 'created_at': createdAt,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoalHistoryCompanion copyWith({
    Value<String>? id,
    Value<String>? effectiveFromLocalDate,
    Value<int>? dailyGoal,
    Value<int>? createdAt,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int>? rowid,
  }) {
    return GoalHistoryCompanion(
      id: id ?? this.id,
      effectiveFromLocalDate:
          effectiveFromLocalDate ?? this.effectiveFromLocalDate,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      createdAt: createdAt ?? this.createdAt,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (effectiveFromLocalDate.present) {
      map['effective_from_local_date'] = Variable<String>(
        effectiveFromLocalDate.value,
      );
    }
    if (dailyGoal.present) {
      map['daily_goal'] = Variable<int>(dailyGoal.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalHistoryCompanion(')
          ..write('id: $id, ')
          ..write('effectiveFromLocalDate: $effectiveFromLocalDate, ')
          ..write('dailyGoal: $dailyGoal, ')
          ..write('createdAt: $createdAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardStatesTable extends CardStates
    with TableInfo<$CardStatesTable, CardState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stabilityMeta = const VerificationMeta(
    'stability',
  );
  @override
  late final GeneratedColumn<double> stability = GeneratedColumn<double>(
    'stability',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _difficultyMeta = const VerificationMeta(
    'difficulty',
  );
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
    'difficulty',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReviewAtMeta = const VerificationMeta(
    'lastReviewAt',
  );
  @override
  late final GeneratedColumn<int> lastReviewAt = GeneratedColumn<int>(
    'last_review_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
    'reps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
    'lapses',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('newCard'),
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<int> step = GeneratedColumn<int>(
    'step',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _computedThroughReviewedAtMeta =
      const VerificationMeta('computedThroughReviewedAt');
  @override
  late final GeneratedColumn<int> computedThroughReviewedAt =
      GeneratedColumn<int>(
        'computed_through_reviewed_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _computedThroughReviewIdMeta =
      const VerificationMeta('computedThroughReviewId');
  @override
  late final GeneratedColumn<String> computedThroughReviewId =
      GeneratedColumn<String>(
        'computed_through_review_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _fsrsParamsVersionMeta = const VerificationMeta(
    'fsrsParamsVersion',
  );
  @override
  late final GeneratedColumn<int> fsrsParamsVersion = GeneratedColumn<int>(
    'fsrs_params_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    cardId,
    stability,
    difficulty,
    dueAt,
    lastReviewAt,
    reps,
    lapses,
    phase,
    step,
    computedThroughReviewedAt,
    computedThroughReviewId,
    dirty,
    fsrsParamsVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('stability')) {
      context.handle(
        _stabilityMeta,
        stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta),
      );
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('last_review_at')) {
      context.handle(
        _lastReviewAtMeta,
        lastReviewAt.isAcceptableOrUnknown(
          data['last_review_at']!,
          _lastReviewAtMeta,
        ),
      );
    }
    if (data.containsKey('reps')) {
      context.handle(
        _repsMeta,
        reps.isAcceptableOrUnknown(data['reps']!, _repsMeta),
      );
    }
    if (data.containsKey('lapses')) {
      context.handle(
        _lapsesMeta,
        lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta),
      );
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    }
    if (data.containsKey('computed_through_reviewed_at')) {
      context.handle(
        _computedThroughReviewedAtMeta,
        computedThroughReviewedAt.isAcceptableOrUnknown(
          data['computed_through_reviewed_at']!,
          _computedThroughReviewedAtMeta,
        ),
      );
    }
    if (data.containsKey('computed_through_review_id')) {
      context.handle(
        _computedThroughReviewIdMeta,
        computedThroughReviewId.isAcceptableOrUnknown(
          data['computed_through_review_id']!,
          _computedThroughReviewIdMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('fsrs_params_version')) {
      context.handle(
        _fsrsParamsVersionMeta,
        fsrsParamsVersion.isAcceptableOrUnknown(
          data['fsrs_params_version']!,
          _fsrsParamsVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cardId};
  @override
  CardState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardState(
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      stability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stability'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_at'],
      ),
      lastReviewAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_review_at'],
      ),
      reps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reps'],
      )!,
      lapses: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lapses'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step'],
      ),
      computedThroughReviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_through_reviewed_at'],
      ),
      computedThroughReviewId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}computed_through_review_id'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      fsrsParamsVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fsrs_params_version'],
      )!,
    );
  }

  @override
  $CardStatesTable createAlias(String alias) {
    return $CardStatesTable(attachedDatabase, alias);
  }
}

class CardState extends DataClass implements Insertable<CardState> {
  final String cardId;
  final double stability;
  final double difficulty;
  final int? dueAt;
  final int? lastReviewAt;
  final int reps;
  final int lapses;
  final String phase;
  final int? step;

  /// Incremental-replay watermark as a `(reviewedAt, id)` pair (§5.3).
  ///
  /// A single review id is not enough: with two-way history sync a review can
  /// arrive **out of order**, and incremental replay would silently skip it.
  final int? computedThroughReviewedAt;
  final String? computedThroughReviewId;

  /// Set when an out-of-order review lands below the watermark, or when the
  /// FSRS parameters change. A background pass fully replays these cards.
  final bool dirty;
  final int fsrsParamsVersion;
  const CardState({
    required this.cardId,
    required this.stability,
    required this.difficulty,
    this.dueAt,
    this.lastReviewAt,
    required this.reps,
    required this.lapses,
    required this.phase,
    this.step,
    this.computedThroughReviewedAt,
    this.computedThroughReviewId,
    required this.dirty,
    required this.fsrsParamsVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['card_id'] = Variable<String>(cardId);
    map['stability'] = Variable<double>(stability);
    map['difficulty'] = Variable<double>(difficulty);
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<int>(dueAt);
    }
    if (!nullToAbsent || lastReviewAt != null) {
      map['last_review_at'] = Variable<int>(lastReviewAt);
    }
    map['reps'] = Variable<int>(reps);
    map['lapses'] = Variable<int>(lapses);
    map['phase'] = Variable<String>(phase);
    if (!nullToAbsent || step != null) {
      map['step'] = Variable<int>(step);
    }
    if (!nullToAbsent || computedThroughReviewedAt != null) {
      map['computed_through_reviewed_at'] = Variable<int>(
        computedThroughReviewedAt,
      );
    }
    if (!nullToAbsent || computedThroughReviewId != null) {
      map['computed_through_review_id'] = Variable<String>(
        computedThroughReviewId,
      );
    }
    map['dirty'] = Variable<bool>(dirty);
    map['fsrs_params_version'] = Variable<int>(fsrsParamsVersion);
    return map;
  }

  CardStatesCompanion toCompanion(bool nullToAbsent) {
    return CardStatesCompanion(
      cardId: Value(cardId),
      stability: Value(stability),
      difficulty: Value(difficulty),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      lastReviewAt: lastReviewAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewAt),
      reps: Value(reps),
      lapses: Value(lapses),
      phase: Value(phase),
      step: step == null && nullToAbsent ? const Value.absent() : Value(step),
      computedThroughReviewedAt:
          computedThroughReviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(computedThroughReviewedAt),
      computedThroughReviewId: computedThroughReviewId == null && nullToAbsent
          ? const Value.absent()
          : Value(computedThroughReviewId),
      dirty: Value(dirty),
      fsrsParamsVersion: Value(fsrsParamsVersion),
    );
  }

  factory CardState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardState(
      cardId: serializer.fromJson<String>(json['cardId']),
      stability: serializer.fromJson<double>(json['stability']),
      difficulty: serializer.fromJson<double>(json['difficulty']),
      dueAt: serializer.fromJson<int?>(json['dueAt']),
      lastReviewAt: serializer.fromJson<int?>(json['lastReviewAt']),
      reps: serializer.fromJson<int>(json['reps']),
      lapses: serializer.fromJson<int>(json['lapses']),
      phase: serializer.fromJson<String>(json['phase']),
      step: serializer.fromJson<int?>(json['step']),
      computedThroughReviewedAt: serializer.fromJson<int?>(
        json['computedThroughReviewedAt'],
      ),
      computedThroughReviewId: serializer.fromJson<String?>(
        json['computedThroughReviewId'],
      ),
      dirty: serializer.fromJson<bool>(json['dirty']),
      fsrsParamsVersion: serializer.fromJson<int>(json['fsrsParamsVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cardId': serializer.toJson<String>(cardId),
      'stability': serializer.toJson<double>(stability),
      'difficulty': serializer.toJson<double>(difficulty),
      'dueAt': serializer.toJson<int?>(dueAt),
      'lastReviewAt': serializer.toJson<int?>(lastReviewAt),
      'reps': serializer.toJson<int>(reps),
      'lapses': serializer.toJson<int>(lapses),
      'phase': serializer.toJson<String>(phase),
      'step': serializer.toJson<int?>(step),
      'computedThroughReviewedAt': serializer.toJson<int?>(
        computedThroughReviewedAt,
      ),
      'computedThroughReviewId': serializer.toJson<String?>(
        computedThroughReviewId,
      ),
      'dirty': serializer.toJson<bool>(dirty),
      'fsrsParamsVersion': serializer.toJson<int>(fsrsParamsVersion),
    };
  }

  CardState copyWith({
    String? cardId,
    double? stability,
    double? difficulty,
    Value<int?> dueAt = const Value.absent(),
    Value<int?> lastReviewAt = const Value.absent(),
    int? reps,
    int? lapses,
    String? phase,
    Value<int?> step = const Value.absent(),
    Value<int?> computedThroughReviewedAt = const Value.absent(),
    Value<String?> computedThroughReviewId = const Value.absent(),
    bool? dirty,
    int? fsrsParamsVersion,
  }) => CardState(
    cardId: cardId ?? this.cardId,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    lastReviewAt: lastReviewAt.present ? lastReviewAt.value : this.lastReviewAt,
    reps: reps ?? this.reps,
    lapses: lapses ?? this.lapses,
    phase: phase ?? this.phase,
    step: step.present ? step.value : this.step,
    computedThroughReviewedAt: computedThroughReviewedAt.present
        ? computedThroughReviewedAt.value
        : this.computedThroughReviewedAt,
    computedThroughReviewId: computedThroughReviewId.present
        ? computedThroughReviewId.value
        : this.computedThroughReviewId,
    dirty: dirty ?? this.dirty,
    fsrsParamsVersion: fsrsParamsVersion ?? this.fsrsParamsVersion,
  );
  CardState copyWithCompanion(CardStatesCompanion data) {
    return CardState(
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      lastReviewAt: data.lastReviewAt.present
          ? data.lastReviewAt.value
          : this.lastReviewAt,
      reps: data.reps.present ? data.reps.value : this.reps,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      phase: data.phase.present ? data.phase.value : this.phase,
      step: data.step.present ? data.step.value : this.step,
      computedThroughReviewedAt: data.computedThroughReviewedAt.present
          ? data.computedThroughReviewedAt.value
          : this.computedThroughReviewedAt,
      computedThroughReviewId: data.computedThroughReviewId.present
          ? data.computedThroughReviewId.value
          : this.computedThroughReviewId,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      fsrsParamsVersion: data.fsrsParamsVersion.present
          ? data.fsrsParamsVersion.value
          : this.fsrsParamsVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardState(')
          ..write('cardId: $cardId, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('dueAt: $dueAt, ')
          ..write('lastReviewAt: $lastReviewAt, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('phase: $phase, ')
          ..write('step: $step, ')
          ..write('computedThroughReviewedAt: $computedThroughReviewedAt, ')
          ..write('computedThroughReviewId: $computedThroughReviewId, ')
          ..write('dirty: $dirty, ')
          ..write('fsrsParamsVersion: $fsrsParamsVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    cardId,
    stability,
    difficulty,
    dueAt,
    lastReviewAt,
    reps,
    lapses,
    phase,
    step,
    computedThroughReviewedAt,
    computedThroughReviewId,
    dirty,
    fsrsParamsVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardState &&
          other.cardId == this.cardId &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.dueAt == this.dueAt &&
          other.lastReviewAt == this.lastReviewAt &&
          other.reps == this.reps &&
          other.lapses == this.lapses &&
          other.phase == this.phase &&
          other.step == this.step &&
          other.computedThroughReviewedAt == this.computedThroughReviewedAt &&
          other.computedThroughReviewId == this.computedThroughReviewId &&
          other.dirty == this.dirty &&
          other.fsrsParamsVersion == this.fsrsParamsVersion);
}

class CardStatesCompanion extends UpdateCompanion<CardState> {
  final Value<String> cardId;
  final Value<double> stability;
  final Value<double> difficulty;
  final Value<int?> dueAt;
  final Value<int?> lastReviewAt;
  final Value<int> reps;
  final Value<int> lapses;
  final Value<String> phase;
  final Value<int?> step;
  final Value<int?> computedThroughReviewedAt;
  final Value<String?> computedThroughReviewId;
  final Value<bool> dirty;
  final Value<int> fsrsParamsVersion;
  final Value<int> rowid;
  const CardStatesCompanion({
    this.cardId = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.lastReviewAt = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.phase = const Value.absent(),
    this.step = const Value.absent(),
    this.computedThroughReviewedAt = const Value.absent(),
    this.computedThroughReviewId = const Value.absent(),
    this.dirty = const Value.absent(),
    this.fsrsParamsVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardStatesCompanion.insert({
    required String cardId,
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.lastReviewAt = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.phase = const Value.absent(),
    this.step = const Value.absent(),
    this.computedThroughReviewedAt = const Value.absent(),
    this.computedThroughReviewId = const Value.absent(),
    this.dirty = const Value.absent(),
    this.fsrsParamsVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : cardId = Value(cardId);
  static Insertable<CardState> custom({
    Expression<String>? cardId,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<int>? dueAt,
    Expression<int>? lastReviewAt,
    Expression<int>? reps,
    Expression<int>? lapses,
    Expression<String>? phase,
    Expression<int>? step,
    Expression<int>? computedThroughReviewedAt,
    Expression<String>? computedThroughReviewId,
    Expression<bool>? dirty,
    Expression<int>? fsrsParamsVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cardId != null) 'card_id': cardId,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (dueAt != null) 'due_at': dueAt,
      if (lastReviewAt != null) 'last_review_at': lastReviewAt,
      if (reps != null) 'reps': reps,
      if (lapses != null) 'lapses': lapses,
      if (phase != null) 'phase': phase,
      if (step != null) 'step': step,
      if (computedThroughReviewedAt != null)
        'computed_through_reviewed_at': computedThroughReviewedAt,
      if (computedThroughReviewId != null)
        'computed_through_review_id': computedThroughReviewId,
      if (dirty != null) 'dirty': dirty,
      if (fsrsParamsVersion != null) 'fsrs_params_version': fsrsParamsVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardStatesCompanion copyWith({
    Value<String>? cardId,
    Value<double>? stability,
    Value<double>? difficulty,
    Value<int?>? dueAt,
    Value<int?>? lastReviewAt,
    Value<int>? reps,
    Value<int>? lapses,
    Value<String>? phase,
    Value<int?>? step,
    Value<int?>? computedThroughReviewedAt,
    Value<String?>? computedThroughReviewId,
    Value<bool>? dirty,
    Value<int>? fsrsParamsVersion,
    Value<int>? rowid,
  }) {
    return CardStatesCompanion(
      cardId: cardId ?? this.cardId,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      dueAt: dueAt ?? this.dueAt,
      lastReviewAt: lastReviewAt ?? this.lastReviewAt,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      phase: phase ?? this.phase,
      step: step ?? this.step,
      computedThroughReviewedAt:
          computedThroughReviewedAt ?? this.computedThroughReviewedAt,
      computedThroughReviewId:
          computedThroughReviewId ?? this.computedThroughReviewId,
      dirty: dirty ?? this.dirty,
      fsrsParamsVersion: fsrsParamsVersion ?? this.fsrsParamsVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (lastReviewAt.present) {
      map['last_review_at'] = Variable<int>(lastReviewAt.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (step.present) {
      map['step'] = Variable<int>(step.value);
    }
    if (computedThroughReviewedAt.present) {
      map['computed_through_reviewed_at'] = Variable<int>(
        computedThroughReviewedAt.value,
      );
    }
    if (computedThroughReviewId.present) {
      map['computed_through_review_id'] = Variable<String>(
        computedThroughReviewId.value,
      );
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (fsrsParamsVersion.present) {
      map['fsrs_params_version'] = Variable<int>(fsrsParamsVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardStatesCompanion(')
          ..write('cardId: $cardId, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('dueAt: $dueAt, ')
          ..write('lastReviewAt: $lastReviewAt, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('phase: $phase, ')
          ..write('step: $step, ')
          ..write('computedThroughReviewedAt: $computedThroughReviewedAt, ')
          ..write('computedThroughReviewId: $computedThroughReviewId, ')
          ..write('dirty: $dirty, ')
          ..write('fsrsParamsVersion: $fsrsParamsVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, UserSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    value,
    updatedAt,
    deviceId,
    serverSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  UserSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
    );
  }

  @override
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
  }
}

class UserSetting extends DataClass implements Insertable<UserSetting> {
  final String key;
  final String value;
  final int updatedAt;
  final String deviceId;
  final int? serverSeq;
  const UserSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
    required this.deviceId,
    this.serverSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    return map;
  }

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
      deviceId: Value(deviceId),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
    );
  }

  factory UserSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverSeq': serializer.toJson<int?>(serverSeq),
    };
  }

  UserSetting copyWith({
    String? key,
    String? value,
    int? updatedAt,
    String? deviceId,
    Value<int?> serverSeq = const Value.absent(),
  }) => UserSetting(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId ?? this.deviceId,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
  );
  UserSetting copyWithCompanion(UserSettingsCompanion data) {
    return UserSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt, deviceId, serverSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId &&
          other.serverSeq == this.serverSeq);
}

class UserSettingsCompanion extends UpdateCompanion<UserSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<String> deviceId;
  final Value<int?> serverSeq;
  final Value<int> rowid;
  const UserSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserSettingsCompanion.insert({
    required String key,
    required String value,
    required int updatedAt,
    required String deviceId,
    this.serverSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt),
       deviceId = Value(deviceId);
  static Insertable<UserSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<int>? serverSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAt,
    Value<String>? deviceId,
    Value<int?>? serverSeq,
    Value<int>? rowid,
  }) {
    return UserSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      serverSeq: serverSeq ?? this.serverSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSettingsTable extends LocalSettings
    with TableInfo<$LocalSettingsTable, LocalSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LocalSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $LocalSettingsTable createAlias(String alias) {
    return $LocalSettingsTable(attachedDatabase, alias);
  }
}

class LocalSetting extends DataClass implements Insertable<LocalSetting> {
  final String key;
  final String value;
  const LocalSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LocalSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory LocalSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  LocalSetting copyWith({String? key, String? value}) =>
      LocalSetting(key: key ?? this.key, value: value ?? this.value);
  LocalSetting copyWithCompanion(LocalSettingsCompanion data) {
    return LocalSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class LocalSettingsCompanion extends UpdateCompanion<LocalSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const LocalSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<LocalSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return LocalSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPulledSeqMeta = const VerificationMeta(
    'lastPulledSeq',
  );
  @override
  late final GeneratedColumn<int> lastPulledSeq = GeneratedColumn<int>(
    'last_pulled_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [entity, lastPulledSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('last_pulled_seq')) {
      context.handle(
        _lastPulledSeqMeta,
        lastPulledSeq.isAcceptableOrUnknown(
          data['last_pulled_seq']!,
          _lastPulledSeqMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      lastPulledSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_pulled_seq'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  /// Not `tableName`: drift's own `Table.tableName` occupies that name, and
  /// declaring a column with it fails to compile with a confusing override
  /// error rather than a naming one.
  final String entity;
  final int lastPulledSeq;
  const SyncStateData({required this.entity, required this.lastPulledSeq});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['last_pulled_seq'] = Variable<int>(lastPulledSeq);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      entity: Value(entity),
      lastPulledSeq: Value(lastPulledSeq),
    );
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      entity: serializer.fromJson<String>(json['entity']),
      lastPulledSeq: serializer.fromJson<int>(json['lastPulledSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'lastPulledSeq': serializer.toJson<int>(lastPulledSeq),
    };
  }

  SyncStateData copyWith({String? entity, int? lastPulledSeq}) => SyncStateData(
    entity: entity ?? this.entity,
    lastPulledSeq: lastPulledSeq ?? this.lastPulledSeq,
  );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      entity: data.entity.present ? data.entity.value : this.entity,
      lastPulledSeq: data.lastPulledSeq.present
          ? data.lastPulledSeq.value
          : this.lastPulledSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('entity: $entity, ')
          ..write('lastPulledSeq: $lastPulledSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entity, lastPulledSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.entity == this.entity &&
          other.lastPulledSeq == this.lastPulledSeq);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> entity;
  final Value<int> lastPulledSeq;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.entity = const Value.absent(),
    this.lastPulledSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String entity,
    this.lastPulledSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entity = Value(entity);
  static Insertable<SyncStateData> custom({
    Expression<String>? entity,
    Expression<int>? lastPulledSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (lastPulledSeq != null) 'last_pulled_seq': lastPulledSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? entity,
    Value<int>? lastPulledSeq,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      entity: entity ?? this.entity,
      lastPulledSeq: lastPulledSeq ?? this.lastPulledSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (lastPulledSeq.present) {
      map['last_pulled_seq'] = Variable<int>(lastPulledSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('entity: $entity, ')
          ..write('lastPulledSeq: $lastPulledSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingCardsTable extends PendingCards
    with TableInfo<$PendingCardsTable, PendingCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deckIdMeta = const VerificationMeta('deckId');
  @override
  late final GeneratedColumn<String> deckId = GeneratedColumn<String>(
    'deck_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frontMeta = const VerificationMeta('front');
  @override
  late final GeneratedColumn<String> front = GeneratedColumn<String>(
    'front',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backMeta = const VerificationMeta('back');
  @override
  late final GeneratedColumn<String> back = GeneratedColumn<String>(
    'back',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _decisionMeta = const VerificationMeta(
    'decision',
  );
  @override
  late final GeneratedColumn<String> decision = GeneratedColumn<String>(
    'decision',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _decidedAtMeta = const VerificationMeta(
    'decidedAt',
  );
  @override
  late final GeneratedColumn<int> decidedAt = GeneratedColumn<int>(
    'decided_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    jobId,
    deckId,
    front,
    back,
    tags,
    position,
    decision,
    decidedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingCard> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('deck_id')) {
      context.handle(
        _deckIdMeta,
        deckId.isAcceptableOrUnknown(data['deck_id']!, _deckIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deckIdMeta);
    }
    if (data.containsKey('front')) {
      context.handle(
        _frontMeta,
        front.isAcceptableOrUnknown(data['front']!, _frontMeta),
      );
    } else if (isInserting) {
      context.missing(_frontMeta);
    }
    if (data.containsKey('back')) {
      context.handle(
        _backMeta,
        back.isAcceptableOrUnknown(data['back']!, _backMeta),
      );
    } else if (isInserting) {
      context.missing(_backMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('decision')) {
      context.handle(
        _decisionMeta,
        decision.isAcceptableOrUnknown(data['decision']!, _decisionMeta),
      );
    }
    if (data.containsKey('decided_at')) {
      context.handle(
        _decidedAtMeta,
        decidedAt.isAcceptableOrUnknown(data['decided_at']!, _decidedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingCard(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      deckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deck_id'],
      )!,
      front: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}front'],
      )!,
      back: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}back'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      decision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decision'],
      ),
      decidedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decided_at'],
      ),
    );
  }

  @override
  $PendingCardsTable createAlias(String alias) {
    return $PendingCardsTable(attachedDatabase, alias);
  }
}

class PendingCard extends DataClass implements Insertable<PendingCard> {
  final String id;
  final String jobId;
  final String deckId;
  final String front;
  final String back;
  final String tags;
  final int position;

  /// The one column the client writes; it pushes back like any mutation.
  final String? decision;
  final int? decidedAt;
  const PendingCard({
    required this.id,
    required this.jobId,
    required this.deckId,
    required this.front,
    required this.back,
    required this.tags,
    required this.position,
    this.decision,
    this.decidedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['job_id'] = Variable<String>(jobId);
    map['deck_id'] = Variable<String>(deckId);
    map['front'] = Variable<String>(front);
    map['back'] = Variable<String>(back);
    map['tags'] = Variable<String>(tags);
    map['position'] = Variable<int>(position);
    if (!nullToAbsent || decision != null) {
      map['decision'] = Variable<String>(decision);
    }
    if (!nullToAbsent || decidedAt != null) {
      map['decided_at'] = Variable<int>(decidedAt);
    }
    return map;
  }

  PendingCardsCompanion toCompanion(bool nullToAbsent) {
    return PendingCardsCompanion(
      id: Value(id),
      jobId: Value(jobId),
      deckId: Value(deckId),
      front: Value(front),
      back: Value(back),
      tags: Value(tags),
      position: Value(position),
      decision: decision == null && nullToAbsent
          ? const Value.absent()
          : Value(decision),
      decidedAt: decidedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(decidedAt),
    );
  }

  factory PendingCard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingCard(
      id: serializer.fromJson<String>(json['id']),
      jobId: serializer.fromJson<String>(json['jobId']),
      deckId: serializer.fromJson<String>(json['deckId']),
      front: serializer.fromJson<String>(json['front']),
      back: serializer.fromJson<String>(json['back']),
      tags: serializer.fromJson<String>(json['tags']),
      position: serializer.fromJson<int>(json['position']),
      decision: serializer.fromJson<String?>(json['decision']),
      decidedAt: serializer.fromJson<int?>(json['decidedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'jobId': serializer.toJson<String>(jobId),
      'deckId': serializer.toJson<String>(deckId),
      'front': serializer.toJson<String>(front),
      'back': serializer.toJson<String>(back),
      'tags': serializer.toJson<String>(tags),
      'position': serializer.toJson<int>(position),
      'decision': serializer.toJson<String?>(decision),
      'decidedAt': serializer.toJson<int?>(decidedAt),
    };
  }

  PendingCard copyWith({
    String? id,
    String? jobId,
    String? deckId,
    String? front,
    String? back,
    String? tags,
    int? position,
    Value<String?> decision = const Value.absent(),
    Value<int?> decidedAt = const Value.absent(),
  }) => PendingCard(
    id: id ?? this.id,
    jobId: jobId ?? this.jobId,
    deckId: deckId ?? this.deckId,
    front: front ?? this.front,
    back: back ?? this.back,
    tags: tags ?? this.tags,
    position: position ?? this.position,
    decision: decision.present ? decision.value : this.decision,
    decidedAt: decidedAt.present ? decidedAt.value : this.decidedAt,
  );
  PendingCard copyWithCompanion(PendingCardsCompanion data) {
    return PendingCard(
      id: data.id.present ? data.id.value : this.id,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      deckId: data.deckId.present ? data.deckId.value : this.deckId,
      front: data.front.present ? data.front.value : this.front,
      back: data.back.present ? data.back.value : this.back,
      tags: data.tags.present ? data.tags.value : this.tags,
      position: data.position.present ? data.position.value : this.position,
      decision: data.decision.present ? data.decision.value : this.decision,
      decidedAt: data.decidedAt.present ? data.decidedAt.value : this.decidedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingCard(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('deckId: $deckId, ')
          ..write('front: $front, ')
          ..write('back: $back, ')
          ..write('tags: $tags, ')
          ..write('position: $position, ')
          ..write('decision: $decision, ')
          ..write('decidedAt: $decidedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    jobId,
    deckId,
    front,
    back,
    tags,
    position,
    decision,
    decidedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingCard &&
          other.id == this.id &&
          other.jobId == this.jobId &&
          other.deckId == this.deckId &&
          other.front == this.front &&
          other.back == this.back &&
          other.tags == this.tags &&
          other.position == this.position &&
          other.decision == this.decision &&
          other.decidedAt == this.decidedAt);
}

class PendingCardsCompanion extends UpdateCompanion<PendingCard> {
  final Value<String> id;
  final Value<String> jobId;
  final Value<String> deckId;
  final Value<String> front;
  final Value<String> back;
  final Value<String> tags;
  final Value<int> position;
  final Value<String?> decision;
  final Value<int?> decidedAt;
  final Value<int> rowid;
  const PendingCardsCompanion({
    this.id = const Value.absent(),
    this.jobId = const Value.absent(),
    this.deckId = const Value.absent(),
    this.front = const Value.absent(),
    this.back = const Value.absent(),
    this.tags = const Value.absent(),
    this.position = const Value.absent(),
    this.decision = const Value.absent(),
    this.decidedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingCardsCompanion.insert({
    required String id,
    required String jobId,
    required String deckId,
    required String front,
    required String back,
    this.tags = const Value.absent(),
    this.position = const Value.absent(),
    this.decision = const Value.absent(),
    this.decidedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       jobId = Value(jobId),
       deckId = Value(deckId),
       front = Value(front),
       back = Value(back);
  static Insertable<PendingCard> custom({
    Expression<String>? id,
    Expression<String>? jobId,
    Expression<String>? deckId,
    Expression<String>? front,
    Expression<String>? back,
    Expression<String>? tags,
    Expression<int>? position,
    Expression<String>? decision,
    Expression<int>? decidedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jobId != null) 'job_id': jobId,
      if (deckId != null) 'deck_id': deckId,
      if (front != null) 'front': front,
      if (back != null) 'back': back,
      if (tags != null) 'tags': tags,
      if (position != null) 'position': position,
      if (decision != null) 'decision': decision,
      if (decidedAt != null) 'decided_at': decidedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingCardsCompanion copyWith({
    Value<String>? id,
    Value<String>? jobId,
    Value<String>? deckId,
    Value<String>? front,
    Value<String>? back,
    Value<String>? tags,
    Value<int>? position,
    Value<String?>? decision,
    Value<int?>? decidedAt,
    Value<int>? rowid,
  }) {
    return PendingCardsCompanion(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      deckId: deckId ?? this.deckId,
      front: front ?? this.front,
      back: back ?? this.back,
      tags: tags ?? this.tags,
      position: position ?? this.position,
      decision: decision ?? this.decision,
      decidedAt: decidedAt ?? this.decidedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (deckId.present) {
      map['deck_id'] = Variable<String>(deckId.value);
    }
    if (front.present) {
      map['front'] = Variable<String>(front.value);
    }
    if (back.present) {
      map['back'] = Variable<String>(back.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (decision.present) {
      map['decision'] = Variable<String>(decision.value);
    }
    if (decidedAt.present) {
      map['decided_at'] = Variable<int>(decidedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingCardsCompanion(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('deckId: $deckId, ')
          ..write('front: $front, ')
          ..write('back: $back, ')
          ..write('tags: $tags, ')
          ..write('position: $position, ')
          ..write('decision: $decision, ')
          ..write('decidedAt: $decidedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DecksTable decks = $DecksTable(this);
  late final $CardsTable cards = $CardsTable(this);
  late final $CardFlagsTable cardFlags = $CardFlagsTable(this);
  late final $ReviewsTable reviews = $ReviewsTable(this);
  late final $ProgressResetsTable progressResets = $ProgressResetsTable(this);
  late final $GoalHistoryTable goalHistory = $GoalHistoryTable(this);
  late final $CardStatesTable cardStates = $CardStatesTable(this);
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  late final $LocalSettingsTable localSettings = $LocalSettingsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $PendingCardsTable pendingCards = $PendingCardsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    decks,
    cards,
    cardFlags,
    reviews,
    progressResets,
    goalHistory,
    cardStates,
    userSettings,
    localSettings,
    syncState,
    pendingCards,
  ];
}

typedef $$DecksTableCreateCompanionBuilder =
    DecksCompanion Function({
      required String id,
      Value<String?> parentId,
      required String name,
      Value<String?> description,
      Value<int> version,
      Value<String?> author,
      Value<String?> license,
      Value<String> origin,
      Value<String?> sourceDeckId,
      Value<int?> archivedAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });
typedef $$DecksTableUpdateCompanionBuilder =
    DecksCompanion Function({
      Value<String> id,
      Value<String?> parentId,
      Value<String> name,
      Value<String?> description,
      Value<int> version,
      Value<String?> author,
      Value<String?> license,
      Value<String> origin,
      Value<String?> sourceDeckId,
      Value<int?> archivedAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });

class $$DecksTableFilterComposer extends Composer<_$AppDatabase, $DecksTable> {
  $$DecksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDeckId => $composableBuilder(
    column: $table.sourceDeckId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DecksTableOrderingComposer
    extends Composer<_$AppDatabase, $DecksTable> {
  $$DecksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDeckId => $composableBuilder(
    column: $table.sourceDeckId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DecksTableAnnotationComposer
    extends Composer<_$AppDatabase, $DecksTable> {
  $$DecksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get license =>
      $composableBuilder(column: $table.license, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get sourceDeckId => $composableBuilder(
    column: $table.sourceDeckId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);
}

class $$DecksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DecksTable,
          Deck,
          $$DecksTableFilterComposer,
          $$DecksTableOrderingComposer,
          $$DecksTableAnnotationComposer,
          $$DecksTableCreateCompanionBuilder,
          $$DecksTableUpdateCompanionBuilder,
          (Deck, BaseReferences<_$AppDatabase, $DecksTable, Deck>),
          Deck,
          PrefetchHooks Function()
        > {
  $$DecksTableTableManager(_$AppDatabase db, $DecksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DecksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DecksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DecksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> license = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> sourceDeckId = const Value.absent(),
                Value<int?> archivedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DecksCompanion(
                id: id,
                parentId: parentId,
                name: name,
                description: description,
                version: version,
                author: author,
                license: license,
                origin: origin,
                sourceDeckId: sourceDeckId,
                archivedAt: archivedAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> parentId = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> license = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> sourceDeckId = const Value.absent(),
                Value<int?> archivedAt = const Value.absent(),
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DecksCompanion.insert(
                id: id,
                parentId: parentId,
                name: name,
                description: description,
                version: version,
                author: author,
                license: license,
                origin: origin,
                sourceDeckId: sourceDeckId,
                archivedAt: archivedAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DecksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DecksTable,
      Deck,
      $$DecksTableFilterComposer,
      $$DecksTableOrderingComposer,
      $$DecksTableAnnotationComposer,
      $$DecksTableCreateCompanionBuilder,
      $$DecksTableUpdateCompanionBuilder,
      (Deck, BaseReferences<_$AppDatabase, $DecksTable, Deck>),
      Deck,
      PrefetchHooks Function()
    >;
typedef $$CardsTableCreateCompanionBuilder =
    CardsCompanion Function({
      required String id,
      required String deckId,
      required String front,
      required String back,
      Value<String> tags,
      required int updatedAt,
      Value<int?> deletedAt,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });
typedef $$CardsTableUpdateCompanionBuilder =
    CardsCompanion Function({
      Value<String> id,
      Value<String> deckId,
      Value<String> front,
      Value<String> back,
      Value<String> tags,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });

class $$CardsTableFilterComposer extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get front => $composableBuilder(
    column: $table.front,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get back => $composableBuilder(
    column: $table.back,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CardsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get front => $composableBuilder(
    column: $table.front,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get back => $composableBuilder(
    column: $table.back,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deckId =>
      $composableBuilder(column: $table.deckId, builder: (column) => column);

  GeneratedColumn<String> get front =>
      $composableBuilder(column: $table.front, builder: (column) => column);

  GeneratedColumn<String> get back =>
      $composableBuilder(column: $table.back, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);
}

class $$CardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardsTable,
          Card,
          $$CardsTableFilterComposer,
          $$CardsTableOrderingComposer,
          $$CardsTableAnnotationComposer,
          $$CardsTableCreateCompanionBuilder,
          $$CardsTableUpdateCompanionBuilder,
          (Card, BaseReferences<_$AppDatabase, $CardsTable, Card>),
          Card,
          PrefetchHooks Function()
        > {
  $$CardsTableTableManager(_$AppDatabase db, $CardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deckId = const Value.absent(),
                Value<String> front = const Value.absent(),
                Value<String> back = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion(
                id: id,
                deckId: deckId,
                front: front,
                back: back,
                tags: tags,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deckId,
                required String front,
                required String back,
                Value<String> tags = const Value.absent(),
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion.insert(
                id: id,
                deckId: deckId,
                front: front,
                back: back,
                tags: tags,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardsTable,
      Card,
      $$CardsTableFilterComposer,
      $$CardsTableOrderingComposer,
      $$CardsTableAnnotationComposer,
      $$CardsTableCreateCompanionBuilder,
      $$CardsTableUpdateCompanionBuilder,
      (Card, BaseReferences<_$AppDatabase, $CardsTable, Card>),
      Card,
      PrefetchHooks Function()
    >;
typedef $$CardFlagsTableCreateCompanionBuilder =
    CardFlagsCompanion Function({
      required String cardId,
      Value<String> status,
      Value<int?> buriedUntil,
      required int updatedAt,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });
typedef $$CardFlagsTableUpdateCompanionBuilder =
    CardFlagsCompanion Function({
      Value<String> cardId,
      Value<String> status,
      Value<int?> buriedUntil,
      Value<int> updatedAt,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });

class $$CardFlagsTableFilterComposer
    extends Composer<_$AppDatabase, $CardFlagsTable> {
  $$CardFlagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get buriedUntil => $composableBuilder(
    column: $table.buriedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CardFlagsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardFlagsTable> {
  $$CardFlagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get buriedUntil => $composableBuilder(
    column: $table.buriedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardFlagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardFlagsTable> {
  $$CardFlagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get buriedUntil => $composableBuilder(
    column: $table.buriedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);
}

class $$CardFlagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardFlagsTable,
          CardFlag,
          $$CardFlagsTableFilterComposer,
          $$CardFlagsTableOrderingComposer,
          $$CardFlagsTableAnnotationComposer,
          $$CardFlagsTableCreateCompanionBuilder,
          $$CardFlagsTableUpdateCompanionBuilder,
          (CardFlag, BaseReferences<_$AppDatabase, $CardFlagsTable, CardFlag>),
          CardFlag,
          PrefetchHooks Function()
        > {
  $$CardFlagsTableTableManager(_$AppDatabase db, $CardFlagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardFlagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardFlagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardFlagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cardId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> buriedUntil = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardFlagsCompanion(
                cardId: cardId,
                status: status,
                buriedUntil: buriedUntil,
                updatedAt: updatedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cardId,
                Value<String> status = const Value.absent(),
                Value<int?> buriedUntil = const Value.absent(),
                required int updatedAt,
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardFlagsCompanion.insert(
                cardId: cardId,
                status: status,
                buriedUntil: buriedUntil,
                updatedAt: updatedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CardFlagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardFlagsTable,
      CardFlag,
      $$CardFlagsTableFilterComposer,
      $$CardFlagsTableOrderingComposer,
      $$CardFlagsTableAnnotationComposer,
      $$CardFlagsTableCreateCompanionBuilder,
      $$CardFlagsTableUpdateCompanionBuilder,
      (CardFlag, BaseReferences<_$AppDatabase, $CardFlagsTable, CardFlag>),
      CardFlag,
      PrefetchHooks Function()
    >;
typedef $$ReviewsTableCreateCompanionBuilder =
    ReviewsCompanion Function({
      required String id,
      required String cardId,
      required int reviewedAt,
      required int grade,
      required String source,
      Value<int?> elapsedMs,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int?> intervalDaysAfter,
      Value<double?> stabilityAfter,
      Value<double?> difficultyAfter,
      Value<int?> schedulerVersion,
      Value<String?> appVersion,
      Value<int> rowid,
    });
typedef $$ReviewsTableUpdateCompanionBuilder =
    ReviewsCompanion Function({
      Value<String> id,
      Value<String> cardId,
      Value<int> reviewedAt,
      Value<int> grade,
      Value<String> source,
      Value<int?> elapsedMs,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int?> intervalDaysAfter,
      Value<double?> stabilityAfter,
      Value<double?> difficultyAfter,
      Value<int?> schedulerVersion,
      Value<String?> appVersion,
      Value<int> rowid,
    });

class $$ReviewsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewsTable> {
  $$ReviewsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get grade => $composableBuilder(
    column: $table.grade,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalDaysAfter => $composableBuilder(
    column: $table.intervalDaysAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stabilityAfter => $composableBuilder(
    column: $table.stabilityAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get difficultyAfter => $composableBuilder(
    column: $table.difficultyAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schedulerVersion => $composableBuilder(
    column: $table.schedulerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewsTable> {
  $$ReviewsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get grade => $composableBuilder(
    column: $table.grade,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalDaysAfter => $composableBuilder(
    column: $table.intervalDaysAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stabilityAfter => $composableBuilder(
    column: $table.stabilityAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get difficultyAfter => $composableBuilder(
    column: $table.difficultyAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schedulerVersion => $composableBuilder(
    column: $table.schedulerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewsTable> {
  $$ReviewsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get grade =>
      $composableBuilder(column: $table.grade, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get elapsedMs =>
      $composableBuilder(column: $table.elapsedMs, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);

  GeneratedColumn<int> get intervalDaysAfter => $composableBuilder(
    column: $table.intervalDaysAfter,
    builder: (column) => column,
  );

  GeneratedColumn<double> get stabilityAfter => $composableBuilder(
    column: $table.stabilityAfter,
    builder: (column) => column,
  );

  GeneratedColumn<double> get difficultyAfter => $composableBuilder(
    column: $table.difficultyAfter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schedulerVersion => $composableBuilder(
    column: $table.schedulerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );
}

class $$ReviewsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewsTable,
          Review,
          $$ReviewsTableFilterComposer,
          $$ReviewsTableOrderingComposer,
          $$ReviewsTableAnnotationComposer,
          $$ReviewsTableCreateCompanionBuilder,
          $$ReviewsTableUpdateCompanionBuilder,
          (Review, BaseReferences<_$AppDatabase, $ReviewsTable, Review>),
          Review,
          PrefetchHooks Function()
        > {
  $$ReviewsTableTableManager(_$AppDatabase db, $ReviewsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> reviewedAt = const Value.absent(),
                Value<int> grade = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int?> elapsedMs = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int?> intervalDaysAfter = const Value.absent(),
                Value<double?> stabilityAfter = const Value.absent(),
                Value<double?> difficultyAfter = const Value.absent(),
                Value<int?> schedulerVersion = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewsCompanion(
                id: id,
                cardId: cardId,
                reviewedAt: reviewedAt,
                grade: grade,
                source: source,
                elapsedMs: elapsedMs,
                deviceId: deviceId,
                serverSeq: serverSeq,
                intervalDaysAfter: intervalDaysAfter,
                stabilityAfter: stabilityAfter,
                difficultyAfter: difficultyAfter,
                schedulerVersion: schedulerVersion,
                appVersion: appVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cardId,
                required int reviewedAt,
                required int grade,
                required String source,
                Value<int?> elapsedMs = const Value.absent(),
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int?> intervalDaysAfter = const Value.absent(),
                Value<double?> stabilityAfter = const Value.absent(),
                Value<double?> difficultyAfter = const Value.absent(),
                Value<int?> schedulerVersion = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewsCompanion.insert(
                id: id,
                cardId: cardId,
                reviewedAt: reviewedAt,
                grade: grade,
                source: source,
                elapsedMs: elapsedMs,
                deviceId: deviceId,
                serverSeq: serverSeq,
                intervalDaysAfter: intervalDaysAfter,
                stabilityAfter: stabilityAfter,
                difficultyAfter: difficultyAfter,
                schedulerVersion: schedulerVersion,
                appVersion: appVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewsTable,
      Review,
      $$ReviewsTableFilterComposer,
      $$ReviewsTableOrderingComposer,
      $$ReviewsTableAnnotationComposer,
      $$ReviewsTableCreateCompanionBuilder,
      $$ReviewsTableUpdateCompanionBuilder,
      (Review, BaseReferences<_$AppDatabase, $ReviewsTable, Review>),
      Review,
      PrefetchHooks Function()
    >;
typedef $$ProgressResetsTableCreateCompanionBuilder =
    ProgressResetsCompanion Function({
      required String id,
      required String cardId,
      required int resetAt,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });
typedef $$ProgressResetsTableUpdateCompanionBuilder =
    ProgressResetsCompanion Function({
      Value<String> id,
      Value<String> cardId,
      Value<int> resetAt,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });

class $$ProgressResetsTableFilterComposer
    extends Composer<_$AppDatabase, $ProgressResetsTable> {
  $$ProgressResetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resetAt => $composableBuilder(
    column: $table.resetAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgressResetsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProgressResetsTable> {
  $$ProgressResetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resetAt => $composableBuilder(
    column: $table.resetAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgressResetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProgressResetsTable> {
  $$ProgressResetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get resetAt =>
      $composableBuilder(column: $table.resetAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);
}

class $$ProgressResetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProgressResetsTable,
          ProgressReset,
          $$ProgressResetsTableFilterComposer,
          $$ProgressResetsTableOrderingComposer,
          $$ProgressResetsTableAnnotationComposer,
          $$ProgressResetsTableCreateCompanionBuilder,
          $$ProgressResetsTableUpdateCompanionBuilder,
          (
            ProgressReset,
            BaseReferences<_$AppDatabase, $ProgressResetsTable, ProgressReset>,
          ),
          ProgressReset,
          PrefetchHooks Function()
        > {
  $$ProgressResetsTableTableManager(
    _$AppDatabase db,
    $ProgressResetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressResetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressResetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgressResetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> resetAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressResetsCompanion(
                id: id,
                cardId: cardId,
                resetAt: resetAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cardId,
                required int resetAt,
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressResetsCompanion.insert(
                id: id,
                cardId: cardId,
                resetAt: resetAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgressResetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProgressResetsTable,
      ProgressReset,
      $$ProgressResetsTableFilterComposer,
      $$ProgressResetsTableOrderingComposer,
      $$ProgressResetsTableAnnotationComposer,
      $$ProgressResetsTableCreateCompanionBuilder,
      $$ProgressResetsTableUpdateCompanionBuilder,
      (
        ProgressReset,
        BaseReferences<_$AppDatabase, $ProgressResetsTable, ProgressReset>,
      ),
      ProgressReset,
      PrefetchHooks Function()
    >;
typedef $$GoalHistoryTableCreateCompanionBuilder =
    GoalHistoryCompanion Function({
      required String id,
      required String effectiveFromLocalDate,
      required int dailyGoal,
      required int createdAt,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });
typedef $$GoalHistoryTableUpdateCompanionBuilder =
    GoalHistoryCompanion Function({
      Value<String> id,
      Value<String> effectiveFromLocalDate,
      Value<int> dailyGoal,
      Value<int> createdAt,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });

class $$GoalHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $GoalHistoryTable> {
  $$GoalHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveFromLocalDate => $composableBuilder(
    column: $table.effectiveFromLocalDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dailyGoal => $composableBuilder(
    column: $table.dailyGoal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GoalHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $GoalHistoryTable> {
  $$GoalHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveFromLocalDate => $composableBuilder(
    column: $table.effectiveFromLocalDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dailyGoal => $composableBuilder(
    column: $table.dailyGoal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GoalHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $GoalHistoryTable> {
  $$GoalHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get effectiveFromLocalDate => $composableBuilder(
    column: $table.effectiveFromLocalDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dailyGoal =>
      $composableBuilder(column: $table.dailyGoal, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);
}

class $$GoalHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GoalHistoryTable,
          GoalHistoryData,
          $$GoalHistoryTableFilterComposer,
          $$GoalHistoryTableOrderingComposer,
          $$GoalHistoryTableAnnotationComposer,
          $$GoalHistoryTableCreateCompanionBuilder,
          $$GoalHistoryTableUpdateCompanionBuilder,
          (
            GoalHistoryData,
            BaseReferences<_$AppDatabase, $GoalHistoryTable, GoalHistoryData>,
          ),
          GoalHistoryData,
          PrefetchHooks Function()
        > {
  $$GoalHistoryTableTableManager(_$AppDatabase db, $GoalHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GoalHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GoalHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GoalHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> effectiveFromLocalDate = const Value.absent(),
                Value<int> dailyGoal = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GoalHistoryCompanion(
                id: id,
                effectiveFromLocalDate: effectiveFromLocalDate,
                dailyGoal: dailyGoal,
                createdAt: createdAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String effectiveFromLocalDate,
                required int dailyGoal,
                required int createdAt,
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GoalHistoryCompanion.insert(
                id: id,
                effectiveFromLocalDate: effectiveFromLocalDate,
                dailyGoal: dailyGoal,
                createdAt: createdAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GoalHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GoalHistoryTable,
      GoalHistoryData,
      $$GoalHistoryTableFilterComposer,
      $$GoalHistoryTableOrderingComposer,
      $$GoalHistoryTableAnnotationComposer,
      $$GoalHistoryTableCreateCompanionBuilder,
      $$GoalHistoryTableUpdateCompanionBuilder,
      (
        GoalHistoryData,
        BaseReferences<_$AppDatabase, $GoalHistoryTable, GoalHistoryData>,
      ),
      GoalHistoryData,
      PrefetchHooks Function()
    >;
typedef $$CardStatesTableCreateCompanionBuilder =
    CardStatesCompanion Function({
      required String cardId,
      Value<double> stability,
      Value<double> difficulty,
      Value<int?> dueAt,
      Value<int?> lastReviewAt,
      Value<int> reps,
      Value<int> lapses,
      Value<String> phase,
      Value<int?> step,
      Value<int?> computedThroughReviewedAt,
      Value<String?> computedThroughReviewId,
      Value<bool> dirty,
      Value<int> fsrsParamsVersion,
      Value<int> rowid,
    });
typedef $$CardStatesTableUpdateCompanionBuilder =
    CardStatesCompanion Function({
      Value<String> cardId,
      Value<double> stability,
      Value<double> difficulty,
      Value<int?> dueAt,
      Value<int?> lastReviewAt,
      Value<int> reps,
      Value<int> lapses,
      Value<String> phase,
      Value<int?> step,
      Value<int?> computedThroughReviewedAt,
      Value<String?> computedThroughReviewId,
      Value<bool> dirty,
      Value<int> fsrsParamsVersion,
      Value<int> rowid,
    });

class $$CardStatesTableFilterComposer
    extends Composer<_$AppDatabase, $CardStatesTable> {
  $$CardStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReviewAt => $composableBuilder(
    column: $table.lastReviewAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get computedThroughReviewedAt => $composableBuilder(
    column: $table.computedThroughReviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get computedThroughReviewId => $composableBuilder(
    column: $table.computedThroughReviewId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fsrsParamsVersion => $composableBuilder(
    column: $table.fsrsParamsVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CardStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $CardStatesTable> {
  $$CardStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReviewAt => $composableBuilder(
    column: $table.lastReviewAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get computedThroughReviewedAt => $composableBuilder(
    column: $table.computedThroughReviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get computedThroughReviewId => $composableBuilder(
    column: $table.computedThroughReviewId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fsrsParamsVersion => $composableBuilder(
    column: $table.fsrsParamsVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardStatesTable> {
  $$CardStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get lastReviewAt => $composableBuilder(
    column: $table.lastReviewAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<int> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<int> get computedThroughReviewedAt => $composableBuilder(
    column: $table.computedThroughReviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get computedThroughReviewId => $composableBuilder(
    column: $table.computedThroughReviewId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get fsrsParamsVersion => $composableBuilder(
    column: $table.fsrsParamsVersion,
    builder: (column) => column,
  );
}

class $$CardStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardStatesTable,
          CardState,
          $$CardStatesTableFilterComposer,
          $$CardStatesTableOrderingComposer,
          $$CardStatesTableAnnotationComposer,
          $$CardStatesTableCreateCompanionBuilder,
          $$CardStatesTableUpdateCompanionBuilder,
          (
            CardState,
            BaseReferences<_$AppDatabase, $CardStatesTable, CardState>,
          ),
          CardState,
          PrefetchHooks Function()
        > {
  $$CardStatesTableTableManager(_$AppDatabase db, $CardStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cardId = const Value.absent(),
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int?> dueAt = const Value.absent(),
                Value<int?> lastReviewAt = const Value.absent(),
                Value<int> reps = const Value.absent(),
                Value<int> lapses = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<int?> step = const Value.absent(),
                Value<int?> computedThroughReviewedAt = const Value.absent(),
                Value<String?> computedThroughReviewId = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> fsrsParamsVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardStatesCompanion(
                cardId: cardId,
                stability: stability,
                difficulty: difficulty,
                dueAt: dueAt,
                lastReviewAt: lastReviewAt,
                reps: reps,
                lapses: lapses,
                phase: phase,
                step: step,
                computedThroughReviewedAt: computedThroughReviewedAt,
                computedThroughReviewId: computedThroughReviewId,
                dirty: dirty,
                fsrsParamsVersion: fsrsParamsVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cardId,
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int?> dueAt = const Value.absent(),
                Value<int?> lastReviewAt = const Value.absent(),
                Value<int> reps = const Value.absent(),
                Value<int> lapses = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<int?> step = const Value.absent(),
                Value<int?> computedThroughReviewedAt = const Value.absent(),
                Value<String?> computedThroughReviewId = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> fsrsParamsVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardStatesCompanion.insert(
                cardId: cardId,
                stability: stability,
                difficulty: difficulty,
                dueAt: dueAt,
                lastReviewAt: lastReviewAt,
                reps: reps,
                lapses: lapses,
                phase: phase,
                step: step,
                computedThroughReviewedAt: computedThroughReviewedAt,
                computedThroughReviewId: computedThroughReviewId,
                dirty: dirty,
                fsrsParamsVersion: fsrsParamsVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CardStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardStatesTable,
      CardState,
      $$CardStatesTableFilterComposer,
      $$CardStatesTableOrderingComposer,
      $$CardStatesTableAnnotationComposer,
      $$CardStatesTableCreateCompanionBuilder,
      $$CardStatesTableUpdateCompanionBuilder,
      (CardState, BaseReferences<_$AppDatabase, $CardStatesTable, CardState>),
      CardState,
      PrefetchHooks Function()
    >;
typedef $$UserSettingsTableCreateCompanionBuilder =
    UserSettingsCompanion Function({
      required String key,
      required String value,
      required int updatedAt,
      required String deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });
typedef $$UserSettingsTableUpdateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAt,
      Value<String> deviceId,
      Value<int?> serverSeq,
      Value<int> rowid,
    });

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);
}

class $$UserSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSettingsTable,
          UserSetting,
          $$UserSettingsTableFilterComposer,
          $$UserSettingsTableOrderingComposer,
          $$UserSettingsTableAnnotationComposer,
          $$UserSettingsTableCreateCompanionBuilder,
          $$UserSettingsTableUpdateCompanionBuilder,
          (
            UserSetting,
            BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>,
          ),
          UserSetting,
          PrefetchHooks Function()
        > {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAt,
                required String deviceId,
                Value<int?> serverSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                deviceId: deviceId,
                serverSeq: serverSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSettingsTable,
      UserSetting,
      $$UserSettingsTableFilterComposer,
      $$UserSettingsTableOrderingComposer,
      $$UserSettingsTableAnnotationComposer,
      $$UserSettingsTableCreateCompanionBuilder,
      $$UserSettingsTableUpdateCompanionBuilder,
      (
        UserSetting,
        BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>,
      ),
      UserSetting,
      PrefetchHooks Function()
    >;
typedef $$LocalSettingsTableCreateCompanionBuilder =
    LocalSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$LocalSettingsTableUpdateCompanionBuilder =
    LocalSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$LocalSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$LocalSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSettingsTable,
          LocalSetting,
          $$LocalSettingsTableFilterComposer,
          $$LocalSettingsTableOrderingComposer,
          $$LocalSettingsTableAnnotationComposer,
          $$LocalSettingsTableCreateCompanionBuilder,
          $$LocalSettingsTableUpdateCompanionBuilder,
          (
            LocalSetting,
            BaseReferences<_$AppDatabase, $LocalSettingsTable, LocalSetting>,
          ),
          LocalSetting,
          PrefetchHooks Function()
        > {
  $$LocalSettingsTableTableManager(_$AppDatabase db, $LocalSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  LocalSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => LocalSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSettingsTable,
      LocalSetting,
      $$LocalSettingsTableFilterComposer,
      $$LocalSettingsTableOrderingComposer,
      $$LocalSettingsTableAnnotationComposer,
      $$LocalSettingsTableCreateCompanionBuilder,
      $$LocalSettingsTableUpdateCompanionBuilder,
      (
        LocalSetting,
        BaseReferences<_$AppDatabase, $LocalSettingsTable, LocalSetting>,
      ),
      LocalSetting,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      required String entity,
      Value<int> lastPulledSeq,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> entity,
      Value<int> lastPulledSeq,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPulledSeq => $composableBuilder(
    column: $table.lastPulledSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPulledSeq => $composableBuilder(
    column: $table.lastPulledSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<int> get lastPulledSeq => $composableBuilder(
    column: $table.lastPulledSeq,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<int> lastPulledSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                entity: entity,
                lastPulledSeq: lastPulledSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                Value<int> lastPulledSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                entity: entity,
                lastPulledSeq: lastPulledSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$PendingCardsTableCreateCompanionBuilder =
    PendingCardsCompanion Function({
      required String id,
      required String jobId,
      required String deckId,
      required String front,
      required String back,
      Value<String> tags,
      Value<int> position,
      Value<String?> decision,
      Value<int?> decidedAt,
      Value<int> rowid,
    });
typedef $$PendingCardsTableUpdateCompanionBuilder =
    PendingCardsCompanion Function({
      Value<String> id,
      Value<String> jobId,
      Value<String> deckId,
      Value<String> front,
      Value<String> back,
      Value<String> tags,
      Value<int> position,
      Value<String?> decision,
      Value<int?> decidedAt,
      Value<int> rowid,
    });

class $$PendingCardsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingCardsTable> {
  $$PendingCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get front => $composableBuilder(
    column: $table.front,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get back => $composableBuilder(
    column: $table.back,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decidedAt => $composableBuilder(
    column: $table.decidedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingCardsTable> {
  $$PendingCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get front => $composableBuilder(
    column: $table.front,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get back => $composableBuilder(
    column: $table.back,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decidedAt => $composableBuilder(
    column: $table.decidedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingCardsTable> {
  $$PendingCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get deckId =>
      $composableBuilder(column: $table.deckId, builder: (column) => column);

  GeneratedColumn<String> get front =>
      $composableBuilder(column: $table.front, builder: (column) => column);

  GeneratedColumn<String> get back =>
      $composableBuilder(column: $table.back, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get decision =>
      $composableBuilder(column: $table.decision, builder: (column) => column);

  GeneratedColumn<int> get decidedAt =>
      $composableBuilder(column: $table.decidedAt, builder: (column) => column);
}

class $$PendingCardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingCardsTable,
          PendingCard,
          $$PendingCardsTableFilterComposer,
          $$PendingCardsTableOrderingComposer,
          $$PendingCardsTableAnnotationComposer,
          $$PendingCardsTableCreateCompanionBuilder,
          $$PendingCardsTableUpdateCompanionBuilder,
          (
            PendingCard,
            BaseReferences<_$AppDatabase, $PendingCardsTable, PendingCard>,
          ),
          PendingCard,
          PrefetchHooks Function()
        > {
  $$PendingCardsTableTableManager(_$AppDatabase db, $PendingCardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String> deckId = const Value.absent(),
                Value<String> front = const Value.absent(),
                Value<String> back = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String?> decision = const Value.absent(),
                Value<int?> decidedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingCardsCompanion(
                id: id,
                jobId: jobId,
                deckId: deckId,
                front: front,
                back: back,
                tags: tags,
                position: position,
                decision: decision,
                decidedAt: decidedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String jobId,
                required String deckId,
                required String front,
                required String back,
                Value<String> tags = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String?> decision = const Value.absent(),
                Value<int?> decidedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingCardsCompanion.insert(
                id: id,
                jobId: jobId,
                deckId: deckId,
                front: front,
                back: back,
                tags: tags,
                position: position,
                decision: decision,
                decidedAt: decidedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingCardsTable,
      PendingCard,
      $$PendingCardsTableFilterComposer,
      $$PendingCardsTableOrderingComposer,
      $$PendingCardsTableAnnotationComposer,
      $$PendingCardsTableCreateCompanionBuilder,
      $$PendingCardsTableUpdateCompanionBuilder,
      (
        PendingCard,
        BaseReferences<_$AppDatabase, $PendingCardsTable, PendingCard>,
      ),
      PendingCard,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DecksTableTableManager get decks =>
      $$DecksTableTableManager(_db, _db.decks);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db, _db.cards);
  $$CardFlagsTableTableManager get cardFlags =>
      $$CardFlagsTableTableManager(_db, _db.cardFlags);
  $$ReviewsTableTableManager get reviews =>
      $$ReviewsTableTableManager(_db, _db.reviews);
  $$ProgressResetsTableTableManager get progressResets =>
      $$ProgressResetsTableTableManager(_db, _db.progressResets);
  $$GoalHistoryTableTableManager get goalHistory =>
      $$GoalHistoryTableTableManager(_db, _db.goalHistory);
  $$CardStatesTableTableManager get cardStates =>
      $$CardStatesTableTableManager(_db, _db.cardStates);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
  $$LocalSettingsTableTableManager get localSettings =>
      $$LocalSettingsTableTableManager(_db, _db.localSettings);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$PendingCardsTableTableManager get pendingCards =>
      $$PendingCardsTableTableManager(_db, _db.pendingCards);
}
