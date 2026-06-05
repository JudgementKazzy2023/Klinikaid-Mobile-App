// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CachedPatientsTable extends CachedPatients
    with TableInfo<$CachedPatientsTable, CachedPatient> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPatientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateOfBirthMeta = const VerificationMeta(
    'dateOfBirth',
  );
  @override
  late final GeneratedColumn<DateTime> dateOfBirth = GeneratedColumn<DateTime>(
    'date_of_birth',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactNumberMeta = const VerificationMeta(
    'contactNumber',
  );
  @override
  late final GeneratedColumn<String> contactNumber = GeneratedColumn<String>(
    'contact_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    firstName,
    lastName,
    dateOfBirth,
    gender,
    contactNumber,
    email,
    address,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_patients';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPatient> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    } else if (isInserting) {
      context.missing(_lastNameMeta);
    }
    if (data.containsKey('date_of_birth')) {
      context.handle(
        _dateOfBirthMeta,
        dateOfBirth.isAcceptableOrUnknown(
          data['date_of_birth']!,
          _dateOfBirthMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dateOfBirthMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    } else if (isInserting) {
      context.missing(_genderMeta);
    }
    if (data.containsKey('contact_number')) {
      context.handle(
        _contactNumberMeta,
        contactNumber.isAcceptableOrUnknown(
          data['contact_number']!,
          _contactNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contactNumberMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedPatient map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPatient(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      ),
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      dateOfBirth: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_of_birth'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      contactNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_number'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedPatientsTable createAlias(String alias) {
    return $CachedPatientsTable(attachedDatabase, alias);
  }
}

class CachedPatient extends DataClass implements Insertable<CachedPatient> {
  final String id;
  final String? profileId;
  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  final String gender;
  final String contactNumber;
  final String? email;
  final String address;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CachedPatient({
    required this.id,
    this.profileId,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    required this.contactNumber,
    this.email,
    required this.address,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<String>(profileId);
    }
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    map['date_of_birth'] = Variable<DateTime>(dateOfBirth);
    map['gender'] = Variable<String>(gender);
    map['contact_number'] = Variable<String>(contactNumber);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    map['address'] = Variable<String>(address);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedPatientsCompanion toCompanion(bool nullToAbsent) {
    return CachedPatientsCompanion(
      id: Value(id),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      firstName: Value(firstName),
      lastName: Value(lastName),
      dateOfBirth: Value(dateOfBirth),
      gender: Value(gender),
      contactNumber: Value(contactNumber),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      address: Value(address),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedPatient.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPatient(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String?>(json['profileId']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      dateOfBirth: serializer.fromJson<DateTime>(json['dateOfBirth']),
      gender: serializer.fromJson<String>(json['gender']),
      contactNumber: serializer.fromJson<String>(json['contactNumber']),
      email: serializer.fromJson<String?>(json['email']),
      address: serializer.fromJson<String>(json['address']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String?>(profileId),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'dateOfBirth': serializer.toJson<DateTime>(dateOfBirth),
      'gender': serializer.toJson<String>(gender),
      'contactNumber': serializer.toJson<String>(contactNumber),
      'email': serializer.toJson<String?>(email),
      'address': serializer.toJson<String>(address),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedPatient copyWith({
    String? id,
    Value<String?> profileId = const Value.absent(),
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    String? gender,
    String? contactNumber,
    Value<String?> email = const Value.absent(),
    String? address,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CachedPatient(
    id: id ?? this.id,
    profileId: profileId.present ? profileId.value : this.profileId,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    gender: gender ?? this.gender,
    contactNumber: contactNumber ?? this.contactNumber,
    email: email.present ? email.value : this.email,
    address: address ?? this.address,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedPatient copyWithCompanion(CachedPatientsCompanion data) {
    return CachedPatient(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      dateOfBirth: data.dateOfBirth.present
          ? data.dateOfBirth.value
          : this.dateOfBirth,
      gender: data.gender.present ? data.gender.value : this.gender,
      contactNumber: data.contactNumber.present
          ? data.contactNumber.value
          : this.contactNumber,
      email: data.email.present ? data.email.value : this.email,
      address: data.address.present ? data.address.value : this.address,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPatient(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('gender: $gender, ')
          ..write('contactNumber: $contactNumber, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    firstName,
    lastName,
    dateOfBirth,
    gender,
    contactNumber,
    email,
    address,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPatient &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.dateOfBirth == this.dateOfBirth &&
          other.gender == this.gender &&
          other.contactNumber == this.contactNumber &&
          other.email == this.email &&
          other.address == this.address &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CachedPatientsCompanion extends UpdateCompanion<CachedPatient> {
  final Value<String> id;
  final Value<String?> profileId;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<DateTime> dateOfBirth;
  final Value<String> gender;
  final Value<String> contactNumber;
  final Value<String?> email;
  final Value<String> address;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedPatientsCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    this.gender = const Value.absent(),
    this.contactNumber = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPatientsCompanion.insert({
    required String id,
    this.profileId = const Value.absent(),
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required String gender,
    required String contactNumber,
    this.email = const Value.absent(),
    required String address,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       firstName = Value(firstName),
       lastName = Value(lastName),
       dateOfBirth = Value(dateOfBirth),
       gender = Value(gender),
       contactNumber = Value(contactNumber),
       address = Value(address),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CachedPatient> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<DateTime>? dateOfBirth,
    Expression<String>? gender,
    Expression<String>? contactNumber,
    Expression<String>? email,
    Expression<String>? address,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (gender != null) 'gender': gender,
      if (contactNumber != null) 'contact_number': contactNumber,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPatientsCompanion copyWith({
    Value<String>? id,
    Value<String?>? profileId,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<DateTime>? dateOfBirth,
    Value<String>? gender,
    Value<String>? contactNumber,
    Value<String?>? email,
    Value<String>? address,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedPatientsCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      contactNumber: contactNumber ?? this.contactNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (dateOfBirth.present) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (contactNumber.present) {
      map['contact_number'] = Variable<String>(contactNumber.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPatientsCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('gender: $gender, ')
          ..write('contactNumber: $contactNumber, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDocumentsTable extends CachedDocuments
    with TableInfo<$CachedDocumentsTable, CachedDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploaderIdMeta = const VerificationMeta(
    'uploaderId',
  );
  @override
  late final GeneratedColumn<String> uploaderId = GeneratedColumn<String>(
    'uploader_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileTypeMeta = const VerificationMeta(
    'fileType',
  );
  @override
  late final GeneratedColumn<String> fileType = GeneratedColumn<String>(
    'file_type',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ocrTextMeta = const VerificationMeta(
    'ocrText',
  );
  @override
  late final GeneratedColumn<String> ocrText = GeneratedColumn<String>(
    'ocr_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractedMetadataMeta = const VerificationMeta(
    'extractedMetadata',
  );
  @override
  late final GeneratedColumn<String> extractedMetadata =
      GeneratedColumn<String>(
        'extracted_metadata',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rejectionReasonMeta = const VerificationMeta(
    'rejectionReason',
  );
  @override
  late final GeneratedColumn<String> rejectionReason = GeneratedColumn<String>(
    'rejection_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    patientId,
    uploaderId,
    fileName,
    filePath,
    fileType,
    status,
    ocrText,
    extractedMetadata,
    rejectionReason,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    if (data.containsKey('uploader_id')) {
      context.handle(
        _uploaderIdMeta,
        uploaderId.isAcceptableOrUnknown(data['uploader_id']!, _uploaderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_uploaderIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('file_type')) {
      context.handle(
        _fileTypeMeta,
        fileType.isAcceptableOrUnknown(data['file_type']!, _fileTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileTypeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('ocr_text')) {
      context.handle(
        _ocrTextMeta,
        ocrText.isAcceptableOrUnknown(data['ocr_text']!, _ocrTextMeta),
      );
    }
    if (data.containsKey('extracted_metadata')) {
      context.handle(
        _extractedMetadataMeta,
        extractedMetadata.isAcceptableOrUnknown(
          data['extracted_metadata']!,
          _extractedMetadataMeta,
        ),
      );
    }
    if (data.containsKey('rejection_reason')) {
      context.handle(
        _rejectionReasonMeta,
        rejectionReason.isAcceptableOrUnknown(
          data['rejection_reason']!,
          _rejectionReasonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDocument(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      ),
      uploaderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploader_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      fileType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      ocrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_text'],
      ),
      extractedMetadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extracted_metadata'],
      ),
      rejectionReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejection_reason'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedDocumentsTable createAlias(String alias) {
    return $CachedDocumentsTable(attachedDatabase, alias);
  }
}

class CachedDocument extends DataClass implements Insertable<CachedDocument> {
  final String id;
  final String? patientId;
  final String uploaderId;
  final String fileName;
  final String filePath;
  final String fileType;
  final String status;
  final String? ocrText;
  final String? extractedMetadata;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CachedDocument({
    required this.id,
    this.patientId,
    required this.uploaderId,
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.status,
    this.ocrText,
    this.extractedMetadata,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    map['uploader_id'] = Variable<String>(uploaderId);
    map['file_name'] = Variable<String>(fileName);
    map['file_path'] = Variable<String>(filePath);
    map['file_type'] = Variable<String>(fileType);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || ocrText != null) {
      map['ocr_text'] = Variable<String>(ocrText);
    }
    if (!nullToAbsent || extractedMetadata != null) {
      map['extracted_metadata'] = Variable<String>(extractedMetadata);
    }
    if (!nullToAbsent || rejectionReason != null) {
      map['rejection_reason'] = Variable<String>(rejectionReason);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedDocumentsCompanion toCompanion(bool nullToAbsent) {
    return CachedDocumentsCompanion(
      id: Value(id),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
      uploaderId: Value(uploaderId),
      fileName: Value(fileName),
      filePath: Value(filePath),
      fileType: Value(fileType),
      status: Value(status),
      ocrText: ocrText == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrText),
      extractedMetadata: extractedMetadata == null && nullToAbsent
          ? const Value.absent()
          : Value(extractedMetadata),
      rejectionReason: rejectionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectionReason),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDocument(
      id: serializer.fromJson<String>(json['id']),
      patientId: serializer.fromJson<String?>(json['patientId']),
      uploaderId: serializer.fromJson<String>(json['uploaderId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      filePath: serializer.fromJson<String>(json['filePath']),
      fileType: serializer.fromJson<String>(json['fileType']),
      status: serializer.fromJson<String>(json['status']),
      ocrText: serializer.fromJson<String?>(json['ocrText']),
      extractedMetadata: serializer.fromJson<String?>(
        json['extractedMetadata'],
      ),
      rejectionReason: serializer.fromJson<String?>(json['rejectionReason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'patientId': serializer.toJson<String?>(patientId),
      'uploaderId': serializer.toJson<String>(uploaderId),
      'fileName': serializer.toJson<String>(fileName),
      'filePath': serializer.toJson<String>(filePath),
      'fileType': serializer.toJson<String>(fileType),
      'status': serializer.toJson<String>(status),
      'ocrText': serializer.toJson<String?>(ocrText),
      'extractedMetadata': serializer.toJson<String?>(extractedMetadata),
      'rejectionReason': serializer.toJson<String?>(rejectionReason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedDocument copyWith({
    String? id,
    Value<String?> patientId = const Value.absent(),
    String? uploaderId,
    String? fileName,
    String? filePath,
    String? fileType,
    String? status,
    Value<String?> ocrText = const Value.absent(),
    Value<String?> extractedMetadata = const Value.absent(),
    Value<String?> rejectionReason = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CachedDocument(
    id: id ?? this.id,
    patientId: patientId.present ? patientId.value : this.patientId,
    uploaderId: uploaderId ?? this.uploaderId,
    fileName: fileName ?? this.fileName,
    filePath: filePath ?? this.filePath,
    fileType: fileType ?? this.fileType,
    status: status ?? this.status,
    ocrText: ocrText.present ? ocrText.value : this.ocrText,
    extractedMetadata: extractedMetadata.present
        ? extractedMetadata.value
        : this.extractedMetadata,
    rejectionReason: rejectionReason.present
        ? rejectionReason.value
        : this.rejectionReason,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedDocument copyWithCompanion(CachedDocumentsCompanion data) {
    return CachedDocument(
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      uploaderId: data.uploaderId.present
          ? data.uploaderId.value
          : this.uploaderId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileType: data.fileType.present ? data.fileType.value : this.fileType,
      status: data.status.present ? data.status.value : this.status,
      ocrText: data.ocrText.present ? data.ocrText.value : this.ocrText,
      extractedMetadata: data.extractedMetadata.present
          ? data.extractedMetadata.value
          : this.extractedMetadata,
      rejectionReason: data.rejectionReason.present
          ? data.rejectionReason.value
          : this.rejectionReason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDocument(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('uploaderId: $uploaderId, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('fileType: $fileType, ')
          ..write('status: $status, ')
          ..write('ocrText: $ocrText, ')
          ..write('extractedMetadata: $extractedMetadata, ')
          ..write('rejectionReason: $rejectionReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    patientId,
    uploaderId,
    fileName,
    filePath,
    fileType,
    status,
    ocrText,
    extractedMetadata,
    rejectionReason,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDocument &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.uploaderId == this.uploaderId &&
          other.fileName == this.fileName &&
          other.filePath == this.filePath &&
          other.fileType == this.fileType &&
          other.status == this.status &&
          other.ocrText == this.ocrText &&
          other.extractedMetadata == this.extractedMetadata &&
          other.rejectionReason == this.rejectionReason &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CachedDocumentsCompanion extends UpdateCompanion<CachedDocument> {
  final Value<String> id;
  final Value<String?> patientId;
  final Value<String> uploaderId;
  final Value<String> fileName;
  final Value<String> filePath;
  final Value<String> fileType;
  final Value<String> status;
  final Value<String?> ocrText;
  final Value<String?> extractedMetadata;
  final Value<String?> rejectionReason;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedDocumentsCompanion({
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.uploaderId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileType = const Value.absent(),
    this.status = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.extractedMetadata = const Value.absent(),
    this.rejectionReason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDocumentsCompanion.insert({
    required String id,
    this.patientId = const Value.absent(),
    required String uploaderId,
    required String fileName,
    required String filePath,
    required String fileType,
    required String status,
    this.ocrText = const Value.absent(),
    this.extractedMetadata = const Value.absent(),
    this.rejectionReason = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       uploaderId = Value(uploaderId),
       fileName = Value(fileName),
       filePath = Value(filePath),
       fileType = Value(fileType),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CachedDocument> custom({
    Expression<String>? id,
    Expression<String>? patientId,
    Expression<String>? uploaderId,
    Expression<String>? fileName,
    Expression<String>? filePath,
    Expression<String>? fileType,
    Expression<String>? status,
    Expression<String>? ocrText,
    Expression<String>? extractedMetadata,
    Expression<String>? rejectionReason,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (uploaderId != null) 'uploader_id': uploaderId,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
      if (fileType != null) 'file_type': fileType,
      if (status != null) 'status': status,
      if (ocrText != null) 'ocr_text': ocrText,
      if (extractedMetadata != null) 'extracted_metadata': extractedMetadata,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDocumentsCompanion copyWith({
    Value<String>? id,
    Value<String?>? patientId,
    Value<String>? uploaderId,
    Value<String>? fileName,
    Value<String>? filePath,
    Value<String>? fileType,
    Value<String>? status,
    Value<String?>? ocrText,
    Value<String?>? extractedMetadata,
    Value<String?>? rejectionReason,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedDocumentsCompanion(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      uploaderId: uploaderId ?? this.uploaderId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      status: status ?? this.status,
      ocrText: ocrText ?? this.ocrText,
      extractedMetadata: extractedMetadata ?? this.extractedMetadata,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (uploaderId.present) {
      map['uploader_id'] = Variable<String>(uploaderId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileType.present) {
      map['file_type'] = Variable<String>(fileType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (ocrText.present) {
      map['ocr_text'] = Variable<String>(ocrText.value);
    }
    if (extractedMetadata.present) {
      map['extracted_metadata'] = Variable<String>(extractedMetadata.value);
    }
    if (rejectionReason.present) {
      map['rejection_reason'] = Variable<String>(rejectionReason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('uploaderId: $uploaderId, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('fileType: $fileType, ')
          ..write('status: $status, ')
          ..write('ocrText: $ocrText, ')
          ..write('extractedMetadata: $extractedMetadata, ')
          ..write('rejectionReason: $rejectionReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPatientQueuesTable extends CachedPatientQueues
    with TableInfo<$CachedPatientQueuesTable, CachedPatientQueue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPatientQueuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _departmentMeta = const VerificationMeta(
    'department',
  );
  @override
  late final GeneratedColumn<String> department = GeneratedColumn<String>(
    'department',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triageNotesMeta = const VerificationMeta(
    'triageNotes',
  );
  @override
  late final GeneratedColumn<String> triageNotes = GeneratedColumn<String>(
    'triage_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityLevelMeta = const VerificationMeta(
    'priorityLevel',
  );
  @override
  late final GeneratedColumn<String> priorityLevel = GeneratedColumn<String>(
    'priority_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _estimatedWaitMinutesMeta =
      const VerificationMeta('estimatedWaitMinutes');
  @override
  late final GeneratedColumn<int> estimatedWaitMinutes = GeneratedColumn<int>(
    'estimated_wait_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    patientId,
    status,
    department,
    triageNotes,
    priorityLevel,
    estimatedWaitMinutes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_patient_queues';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPatientQueue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('department')) {
      context.handle(
        _departmentMeta,
        department.isAcceptableOrUnknown(data['department']!, _departmentMeta),
      );
    } else if (isInserting) {
      context.missing(_departmentMeta);
    }
    if (data.containsKey('triage_notes')) {
      context.handle(
        _triageNotesMeta,
        triageNotes.isAcceptableOrUnknown(
          data['triage_notes']!,
          _triageNotesMeta,
        ),
      );
    }
    if (data.containsKey('priority_level')) {
      context.handle(
        _priorityLevelMeta,
        priorityLevel.isAcceptableOrUnknown(
          data['priority_level']!,
          _priorityLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priorityLevelMeta);
    }
    if (data.containsKey('estimated_wait_minutes')) {
      context.handle(
        _estimatedWaitMinutesMeta,
        estimatedWaitMinutes.isAcceptableOrUnknown(
          data['estimated_wait_minutes']!,
          _estimatedWaitMinutesMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedPatientQueue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPatientQueue(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      department: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}department'],
      )!,
      triageNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}triage_notes'],
      ),
      priorityLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority_level'],
      )!,
      estimatedWaitMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_wait_minutes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedPatientQueuesTable createAlias(String alias) {
    return $CachedPatientQueuesTable(attachedDatabase, alias);
  }
}

class CachedPatientQueue extends DataClass
    implements Insertable<CachedPatientQueue> {
  final int id;
  final String patientId;
  final String status;
  final String department;
  final String? triageNotes;
  final String priorityLevel;
  final int? estimatedWaitMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CachedPatientQueue({
    required this.id,
    required this.patientId,
    required this.status,
    required this.department,
    this.triageNotes,
    required this.priorityLevel,
    this.estimatedWaitMinutes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['patient_id'] = Variable<String>(patientId);
    map['status'] = Variable<String>(status);
    map['department'] = Variable<String>(department);
    if (!nullToAbsent || triageNotes != null) {
      map['triage_notes'] = Variable<String>(triageNotes);
    }
    map['priority_level'] = Variable<String>(priorityLevel);
    if (!nullToAbsent || estimatedWaitMinutes != null) {
      map['estimated_wait_minutes'] = Variable<int>(estimatedWaitMinutes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedPatientQueuesCompanion toCompanion(bool nullToAbsent) {
    return CachedPatientQueuesCompanion(
      id: Value(id),
      patientId: Value(patientId),
      status: Value(status),
      department: Value(department),
      triageNotes: triageNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(triageNotes),
      priorityLevel: Value(priorityLevel),
      estimatedWaitMinutes: estimatedWaitMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedWaitMinutes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedPatientQueue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPatientQueue(
      id: serializer.fromJson<int>(json['id']),
      patientId: serializer.fromJson<String>(json['patientId']),
      status: serializer.fromJson<String>(json['status']),
      department: serializer.fromJson<String>(json['department']),
      triageNotes: serializer.fromJson<String?>(json['triageNotes']),
      priorityLevel: serializer.fromJson<String>(json['priorityLevel']),
      estimatedWaitMinutes: serializer.fromJson<int?>(
        json['estimatedWaitMinutes'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'patientId': serializer.toJson<String>(patientId),
      'status': serializer.toJson<String>(status),
      'department': serializer.toJson<String>(department),
      'triageNotes': serializer.toJson<String?>(triageNotes),
      'priorityLevel': serializer.toJson<String>(priorityLevel),
      'estimatedWaitMinutes': serializer.toJson<int?>(estimatedWaitMinutes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedPatientQueue copyWith({
    int? id,
    String? patientId,
    String? status,
    String? department,
    Value<String?> triageNotes = const Value.absent(),
    String? priorityLevel,
    Value<int?> estimatedWaitMinutes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CachedPatientQueue(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    status: status ?? this.status,
    department: department ?? this.department,
    triageNotes: triageNotes.present ? triageNotes.value : this.triageNotes,
    priorityLevel: priorityLevel ?? this.priorityLevel,
    estimatedWaitMinutes: estimatedWaitMinutes.present
        ? estimatedWaitMinutes.value
        : this.estimatedWaitMinutes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedPatientQueue copyWithCompanion(CachedPatientQueuesCompanion data) {
    return CachedPatientQueue(
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      status: data.status.present ? data.status.value : this.status,
      department: data.department.present
          ? data.department.value
          : this.department,
      triageNotes: data.triageNotes.present
          ? data.triageNotes.value
          : this.triageNotes,
      priorityLevel: data.priorityLevel.present
          ? data.priorityLevel.value
          : this.priorityLevel,
      estimatedWaitMinutes: data.estimatedWaitMinutes.present
          ? data.estimatedWaitMinutes.value
          : this.estimatedWaitMinutes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPatientQueue(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('status: $status, ')
          ..write('department: $department, ')
          ..write('triageNotes: $triageNotes, ')
          ..write('priorityLevel: $priorityLevel, ')
          ..write('estimatedWaitMinutes: $estimatedWaitMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    patientId,
    status,
    department,
    triageNotes,
    priorityLevel,
    estimatedWaitMinutes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPatientQueue &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.status == this.status &&
          other.department == this.department &&
          other.triageNotes == this.triageNotes &&
          other.priorityLevel == this.priorityLevel &&
          other.estimatedWaitMinutes == this.estimatedWaitMinutes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CachedPatientQueuesCompanion extends UpdateCompanion<CachedPatientQueue> {
  final Value<int> id;
  final Value<String> patientId;
  final Value<String> status;
  final Value<String> department;
  final Value<String?> triageNotes;
  final Value<String> priorityLevel;
  final Value<int?> estimatedWaitMinutes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CachedPatientQueuesCompanion({
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.status = const Value.absent(),
    this.department = const Value.absent(),
    this.triageNotes = const Value.absent(),
    this.priorityLevel = const Value.absent(),
    this.estimatedWaitMinutes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CachedPatientQueuesCompanion.insert({
    this.id = const Value.absent(),
    required String patientId,
    required String status,
    required String department,
    this.triageNotes = const Value.absent(),
    required String priorityLevel,
    this.estimatedWaitMinutes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : patientId = Value(patientId),
       status = Value(status),
       department = Value(department),
       priorityLevel = Value(priorityLevel),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CachedPatientQueue> custom({
    Expression<int>? id,
    Expression<String>? patientId,
    Expression<String>? status,
    Expression<String>? department,
    Expression<String>? triageNotes,
    Expression<String>? priorityLevel,
    Expression<int>? estimatedWaitMinutes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (status != null) 'status': status,
      if (department != null) 'department': department,
      if (triageNotes != null) 'triage_notes': triageNotes,
      if (priorityLevel != null) 'priority_level': priorityLevel,
      if (estimatedWaitMinutes != null)
        'estimated_wait_minutes': estimatedWaitMinutes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CachedPatientQueuesCompanion copyWith({
    Value<int>? id,
    Value<String>? patientId,
    Value<String>? status,
    Value<String>? department,
    Value<String?>? triageNotes,
    Value<String>? priorityLevel,
    Value<int?>? estimatedWaitMinutes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return CachedPatientQueuesCompanion(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      status: status ?? this.status,
      department: department ?? this.department,
      triageNotes: triageNotes ?? this.triageNotes,
      priorityLevel: priorityLevel ?? this.priorityLevel,
      estimatedWaitMinutes: estimatedWaitMinutes ?? this.estimatedWaitMinutes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (department.present) {
      map['department'] = Variable<String>(department.value);
    }
    if (triageNotes.present) {
      map['triage_notes'] = Variable<String>(triageNotes.value);
    }
    if (priorityLevel.present) {
      map['priority_level'] = Variable<String>(priorityLevel.value);
    }
    if (estimatedWaitMinutes.present) {
      map['estimated_wait_minutes'] = Variable<int>(estimatedWaitMinutes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPatientQueuesCompanion(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('status: $status, ')
          ..write('department: $department, ')
          ..write('triageNotes: $triageNotes, ')
          ..write('priorityLevel: $priorityLevel, ')
          ..write('estimatedWaitMinutes: $estimatedWaitMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CachedDepartmentRecordsTable extends CachedDepartmentRecords
    with TableInfo<$CachedDepartmentRecordsTable, CachedDepartmentRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDepartmentRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recorderIdMeta = const VerificationMeta(
    'recorderId',
  );
  @override
  late final GeneratedColumn<String> recorderId = GeneratedColumn<String>(
    'recorder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _departmentMeta = const VerificationMeta(
    'department',
  );
  @override
  late final GeneratedColumn<String> department = GeneratedColumn<String>(
    'department',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _testTypeMeta = const VerificationMeta(
    'testType',
  );
  @override
  late final GeneratedColumn<String> testType = GeneratedColumn<String>(
    'test_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _testResultsMeta = const VerificationMeta(
    'testResults',
  );
  @override
  late final GeneratedColumn<String> testResults = GeneratedColumn<String>(
    'test_results',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceRangeStatusMeta =
      const VerificationMeta('referenceRangeStatus');
  @override
  late final GeneratedColumn<String> referenceRangeStatus =
      GeneratedColumn<String>(
        'reference_range_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    patientId,
    recorderId,
    department,
    testType,
    testResults,
    referenceRangeStatus,
    notes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_department_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDepartmentRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('recorder_id')) {
      context.handle(
        _recorderIdMeta,
        recorderId.isAcceptableOrUnknown(data['recorder_id']!, _recorderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recorderIdMeta);
    }
    if (data.containsKey('department')) {
      context.handle(
        _departmentMeta,
        department.isAcceptableOrUnknown(data['department']!, _departmentMeta),
      );
    } else if (isInserting) {
      context.missing(_departmentMeta);
    }
    if (data.containsKey('test_type')) {
      context.handle(
        _testTypeMeta,
        testType.isAcceptableOrUnknown(data['test_type']!, _testTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_testTypeMeta);
    }
    if (data.containsKey('test_results')) {
      context.handle(
        _testResultsMeta,
        testResults.isAcceptableOrUnknown(
          data['test_results']!,
          _testResultsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_testResultsMeta);
    }
    if (data.containsKey('reference_range_status')) {
      context.handle(
        _referenceRangeStatusMeta,
        referenceRangeStatus.isAcceptableOrUnknown(
          data['reference_range_status']!,
          _referenceRangeStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_referenceRangeStatusMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedDepartmentRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDepartmentRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      )!,
      recorderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorder_id'],
      )!,
      department: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}department'],
      )!,
      testType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}test_type'],
      )!,
      testResults: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}test_results'],
      )!,
      referenceRangeStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_range_status'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedDepartmentRecordsTable createAlias(String alias) {
    return $CachedDepartmentRecordsTable(attachedDatabase, alias);
  }
}

class CachedDepartmentRecord extends DataClass
    implements Insertable<CachedDepartmentRecord> {
  final String id;
  final String patientId;
  final String recorderId;
  final String department;
  final String testType;
  final String testResults;
  final String referenceRangeStatus;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CachedDepartmentRecord({
    required this.id,
    required this.patientId,
    required this.recorderId,
    required this.department,
    required this.testType,
    required this.testResults,
    required this.referenceRangeStatus,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['patient_id'] = Variable<String>(patientId);
    map['recorder_id'] = Variable<String>(recorderId);
    map['department'] = Variable<String>(department);
    map['test_type'] = Variable<String>(testType);
    map['test_results'] = Variable<String>(testResults);
    map['reference_range_status'] = Variable<String>(referenceRangeStatus);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedDepartmentRecordsCompanion toCompanion(bool nullToAbsent) {
    return CachedDepartmentRecordsCompanion(
      id: Value(id),
      patientId: Value(patientId),
      recorderId: Value(recorderId),
      department: Value(department),
      testType: Value(testType),
      testResults: Value(testResults),
      referenceRangeStatus: Value(referenceRangeStatus),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedDepartmentRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDepartmentRecord(
      id: serializer.fromJson<String>(json['id']),
      patientId: serializer.fromJson<String>(json['patientId']),
      recorderId: serializer.fromJson<String>(json['recorderId']),
      department: serializer.fromJson<String>(json['department']),
      testType: serializer.fromJson<String>(json['testType']),
      testResults: serializer.fromJson<String>(json['testResults']),
      referenceRangeStatus: serializer.fromJson<String>(
        json['referenceRangeStatus'],
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'patientId': serializer.toJson<String>(patientId),
      'recorderId': serializer.toJson<String>(recorderId),
      'department': serializer.toJson<String>(department),
      'testType': serializer.toJson<String>(testType),
      'testResults': serializer.toJson<String>(testResults),
      'referenceRangeStatus': serializer.toJson<String>(referenceRangeStatus),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedDepartmentRecord copyWith({
    String? id,
    String? patientId,
    String? recorderId,
    String? department,
    String? testType,
    String? testResults,
    String? referenceRangeStatus,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CachedDepartmentRecord(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    recorderId: recorderId ?? this.recorderId,
    department: department ?? this.department,
    testType: testType ?? this.testType,
    testResults: testResults ?? this.testResults,
    referenceRangeStatus: referenceRangeStatus ?? this.referenceRangeStatus,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedDepartmentRecord copyWithCompanion(
    CachedDepartmentRecordsCompanion data,
  ) {
    return CachedDepartmentRecord(
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      recorderId: data.recorderId.present
          ? data.recorderId.value
          : this.recorderId,
      department: data.department.present
          ? data.department.value
          : this.department,
      testType: data.testType.present ? data.testType.value : this.testType,
      testResults: data.testResults.present
          ? data.testResults.value
          : this.testResults,
      referenceRangeStatus: data.referenceRangeStatus.present
          ? data.referenceRangeStatus.value
          : this.referenceRangeStatus,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDepartmentRecord(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('recorderId: $recorderId, ')
          ..write('department: $department, ')
          ..write('testType: $testType, ')
          ..write('testResults: $testResults, ')
          ..write('referenceRangeStatus: $referenceRangeStatus, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    patientId,
    recorderId,
    department,
    testType,
    testResults,
    referenceRangeStatus,
    notes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDepartmentRecord &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.recorderId == this.recorderId &&
          other.department == this.department &&
          other.testType == this.testType &&
          other.testResults == this.testResults &&
          other.referenceRangeStatus == this.referenceRangeStatus &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CachedDepartmentRecordsCompanion
    extends UpdateCompanion<CachedDepartmentRecord> {
  final Value<String> id;
  final Value<String> patientId;
  final Value<String> recorderId;
  final Value<String> department;
  final Value<String> testType;
  final Value<String> testResults;
  final Value<String> referenceRangeStatus;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedDepartmentRecordsCompanion({
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.recorderId = const Value.absent(),
    this.department = const Value.absent(),
    this.testType = const Value.absent(),
    this.testResults = const Value.absent(),
    this.referenceRangeStatus = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDepartmentRecordsCompanion.insert({
    required String id,
    required String patientId,
    required String recorderId,
    required String department,
    required String testType,
    required String testResults,
    required String referenceRangeStatus,
    this.notes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       patientId = Value(patientId),
       recorderId = Value(recorderId),
       department = Value(department),
       testType = Value(testType),
       testResults = Value(testResults),
       referenceRangeStatus = Value(referenceRangeStatus),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CachedDepartmentRecord> custom({
    Expression<String>? id,
    Expression<String>? patientId,
    Expression<String>? recorderId,
    Expression<String>? department,
    Expression<String>? testType,
    Expression<String>? testResults,
    Expression<String>? referenceRangeStatus,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (recorderId != null) 'recorder_id': recorderId,
      if (department != null) 'department': department,
      if (testType != null) 'test_type': testType,
      if (testResults != null) 'test_results': testResults,
      if (referenceRangeStatus != null)
        'reference_range_status': referenceRangeStatus,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDepartmentRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? patientId,
    Value<String>? recorderId,
    Value<String>? department,
    Value<String>? testType,
    Value<String>? testResults,
    Value<String>? referenceRangeStatus,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedDepartmentRecordsCompanion(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      recorderId: recorderId ?? this.recorderId,
      department: department ?? this.department,
      testType: testType ?? this.testType,
      testResults: testResults ?? this.testResults,
      referenceRangeStatus: referenceRangeStatus ?? this.referenceRangeStatus,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (recorderId.present) {
      map['recorder_id'] = Variable<String>(recorderId.value);
    }
    if (department.present) {
      map['department'] = Variable<String>(department.value);
    }
    if (testType.present) {
      map['test_type'] = Variable<String>(testType.value);
    }
    if (testResults.present) {
      map['test_results'] = Variable<String>(testResults.value);
    }
    if (referenceRangeStatus.present) {
      map['reference_range_status'] = Variable<String>(
        referenceRangeStatus.value,
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDepartmentRecordsCompanion(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('recorderId: $recorderId, ')
          ..write('department: $department, ')
          ..write('testType: $testType, ')
          ..write('testResults: $testResults, ')
          ..write('referenceRangeStatus: $referenceRangeStatus, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineDocumentsQueueTable extends OfflineDocumentsQueue
    with TableInfo<$OfflineDocumentsQueueTable, OfflineDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineDocumentsQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploaderIdMeta = const VerificationMeta(
    'uploaderId',
  );
  @override
  late final GeneratedColumn<String> uploaderId = GeneratedColumn<String>(
    'uploader_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileTypeMeta = const VerificationMeta(
    'fileType',
  );
  @override
  late final GeneratedColumn<String> fileType = GeneratedColumn<String>(
    'file_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ocrTextMeta = const VerificationMeta(
    'ocrText',
  );
  @override
  late final GeneratedColumn<String> ocrText = GeneratedColumn<String>(
    'ocr_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractedMetadataMeta = const VerificationMeta(
    'extractedMetadata',
  );
  @override
  late final GeneratedColumn<String> extractedMetadata =
      GeneratedColumn<String>(
        'extracted_metadata',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    patientId,
    uploaderId,
    fileName,
    localFilePath,
    fileType,
    ocrText,
    extractedMetadata,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_documents_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    if (data.containsKey('uploader_id')) {
      context.handle(
        _uploaderIdMeta,
        uploaderId.isAcceptableOrUnknown(data['uploader_id']!, _uploaderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_uploaderIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localFilePathMeta);
    }
    if (data.containsKey('file_type')) {
      context.handle(
        _fileTypeMeta,
        fileType.isAcceptableOrUnknown(data['file_type']!, _fileTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileTypeMeta);
    }
    if (data.containsKey('ocr_text')) {
      context.handle(
        _ocrTextMeta,
        ocrText.isAcceptableOrUnknown(data['ocr_text']!, _ocrTextMeta),
      );
    }
    if (data.containsKey('extracted_metadata')) {
      context.handle(
        _extractedMetadataMeta,
        extractedMetadata.isAcceptableOrUnknown(
          data['extracted_metadata']!,
          _extractedMetadataMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineDocument(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      ),
      uploaderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploader_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      )!,
      fileType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_type'],
      )!,
      ocrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_text'],
      ),
      extractedMetadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extracted_metadata'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OfflineDocumentsQueueTable createAlias(String alias) {
    return $OfflineDocumentsQueueTable(attachedDatabase, alias);
  }
}

class OfflineDocument extends DataClass implements Insertable<OfflineDocument> {
  final String id;
  final String? patientId;
  final String uploaderId;
  final String fileName;
  final String localFilePath;
  final String fileType;
  final String? ocrText;
  final String? extractedMetadata;
  final DateTime createdAt;
  const OfflineDocument({
    required this.id,
    this.patientId,
    required this.uploaderId,
    required this.fileName,
    required this.localFilePath,
    required this.fileType,
    this.ocrText,
    this.extractedMetadata,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    map['uploader_id'] = Variable<String>(uploaderId);
    map['file_name'] = Variable<String>(fileName);
    map['local_file_path'] = Variable<String>(localFilePath);
    map['file_type'] = Variable<String>(fileType);
    if (!nullToAbsent || ocrText != null) {
      map['ocr_text'] = Variable<String>(ocrText);
    }
    if (!nullToAbsent || extractedMetadata != null) {
      map['extracted_metadata'] = Variable<String>(extractedMetadata);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OfflineDocumentsQueueCompanion toCompanion(bool nullToAbsent) {
    return OfflineDocumentsQueueCompanion(
      id: Value(id),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
      uploaderId: Value(uploaderId),
      fileName: Value(fileName),
      localFilePath: Value(localFilePath),
      fileType: Value(fileType),
      ocrText: ocrText == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrText),
      extractedMetadata: extractedMetadata == null && nullToAbsent
          ? const Value.absent()
          : Value(extractedMetadata),
      createdAt: Value(createdAt),
    );
  }

  factory OfflineDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineDocument(
      id: serializer.fromJson<String>(json['id']),
      patientId: serializer.fromJson<String?>(json['patientId']),
      uploaderId: serializer.fromJson<String>(json['uploaderId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      localFilePath: serializer.fromJson<String>(json['localFilePath']),
      fileType: serializer.fromJson<String>(json['fileType']),
      ocrText: serializer.fromJson<String?>(json['ocrText']),
      extractedMetadata: serializer.fromJson<String?>(
        json['extractedMetadata'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'patientId': serializer.toJson<String?>(patientId),
      'uploaderId': serializer.toJson<String>(uploaderId),
      'fileName': serializer.toJson<String>(fileName),
      'localFilePath': serializer.toJson<String>(localFilePath),
      'fileType': serializer.toJson<String>(fileType),
      'ocrText': serializer.toJson<String?>(ocrText),
      'extractedMetadata': serializer.toJson<String?>(extractedMetadata),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OfflineDocument copyWith({
    String? id,
    Value<String?> patientId = const Value.absent(),
    String? uploaderId,
    String? fileName,
    String? localFilePath,
    String? fileType,
    Value<String?> ocrText = const Value.absent(),
    Value<String?> extractedMetadata = const Value.absent(),
    DateTime? createdAt,
  }) => OfflineDocument(
    id: id ?? this.id,
    patientId: patientId.present ? patientId.value : this.patientId,
    uploaderId: uploaderId ?? this.uploaderId,
    fileName: fileName ?? this.fileName,
    localFilePath: localFilePath ?? this.localFilePath,
    fileType: fileType ?? this.fileType,
    ocrText: ocrText.present ? ocrText.value : this.ocrText,
    extractedMetadata: extractedMetadata.present
        ? extractedMetadata.value
        : this.extractedMetadata,
    createdAt: createdAt ?? this.createdAt,
  );
  OfflineDocument copyWithCompanion(OfflineDocumentsQueueCompanion data) {
    return OfflineDocument(
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      uploaderId: data.uploaderId.present
          ? data.uploaderId.value
          : this.uploaderId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      fileType: data.fileType.present ? data.fileType.value : this.fileType,
      ocrText: data.ocrText.present ? data.ocrText.value : this.ocrText,
      extractedMetadata: data.extractedMetadata.present
          ? data.extractedMetadata.value
          : this.extractedMetadata,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineDocument(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('uploaderId: $uploaderId, ')
          ..write('fileName: $fileName, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('fileType: $fileType, ')
          ..write('ocrText: $ocrText, ')
          ..write('extractedMetadata: $extractedMetadata, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    patientId,
    uploaderId,
    fileName,
    localFilePath,
    fileType,
    ocrText,
    extractedMetadata,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineDocument &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.uploaderId == this.uploaderId &&
          other.fileName == this.fileName &&
          other.localFilePath == this.localFilePath &&
          other.fileType == this.fileType &&
          other.ocrText == this.ocrText &&
          other.extractedMetadata == this.extractedMetadata &&
          other.createdAt == this.createdAt);
}

class OfflineDocumentsQueueCompanion extends UpdateCompanion<OfflineDocument> {
  final Value<String> id;
  final Value<String?> patientId;
  final Value<String> uploaderId;
  final Value<String> fileName;
  final Value<String> localFilePath;
  final Value<String> fileType;
  final Value<String?> ocrText;
  final Value<String?> extractedMetadata;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OfflineDocumentsQueueCompanion({
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.uploaderId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.fileType = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.extractedMetadata = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineDocumentsQueueCompanion.insert({
    required String id,
    this.patientId = const Value.absent(),
    required String uploaderId,
    required String fileName,
    required String localFilePath,
    required String fileType,
    this.ocrText = const Value.absent(),
    this.extractedMetadata = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       uploaderId = Value(uploaderId),
       fileName = Value(fileName),
       localFilePath = Value(localFilePath),
       fileType = Value(fileType),
       createdAt = Value(createdAt);
  static Insertable<OfflineDocument> custom({
    Expression<String>? id,
    Expression<String>? patientId,
    Expression<String>? uploaderId,
    Expression<String>? fileName,
    Expression<String>? localFilePath,
    Expression<String>? fileType,
    Expression<String>? ocrText,
    Expression<String>? extractedMetadata,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (uploaderId != null) 'uploader_id': uploaderId,
      if (fileName != null) 'file_name': fileName,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (fileType != null) 'file_type': fileType,
      if (ocrText != null) 'ocr_text': ocrText,
      if (extractedMetadata != null) 'extracted_metadata': extractedMetadata,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineDocumentsQueueCompanion copyWith({
    Value<String>? id,
    Value<String?>? patientId,
    Value<String>? uploaderId,
    Value<String>? fileName,
    Value<String>? localFilePath,
    Value<String>? fileType,
    Value<String?>? ocrText,
    Value<String?>? extractedMetadata,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return OfflineDocumentsQueueCompanion(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      uploaderId: uploaderId ?? this.uploaderId,
      fileName: fileName ?? this.fileName,
      localFilePath: localFilePath ?? this.localFilePath,
      fileType: fileType ?? this.fileType,
      ocrText: ocrText ?? this.ocrText,
      extractedMetadata: extractedMetadata ?? this.extractedMetadata,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (uploaderId.present) {
      map['uploader_id'] = Variable<String>(uploaderId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (fileType.present) {
      map['file_type'] = Variable<String>(fileType.value);
    }
    if (ocrText.present) {
      map['ocr_text'] = Variable<String>(ocrText.value);
    }
    if (extractedMetadata.present) {
      map['extracted_metadata'] = Variable<String>(extractedMetadata.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineDocumentsQueueCompanion(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('uploaderId: $uploaderId, ')
          ..write('fileName: $fileName, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('fileType: $fileType, ')
          ..write('ocrText: $ocrText, ')
          ..write('extractedMetadata: $extractedMetadata, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $CachedPatientsTable cachedPatients = $CachedPatientsTable(this);
  late final $CachedDocumentsTable cachedDocuments = $CachedDocumentsTable(
    this,
  );
  late final $CachedPatientQueuesTable cachedPatientQueues =
      $CachedPatientQueuesTable(this);
  late final $CachedDepartmentRecordsTable cachedDepartmentRecords =
      $CachedDepartmentRecordsTable(this);
  late final $OfflineDocumentsQueueTable offlineDocumentsQueue =
      $OfflineDocumentsQueueTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedPatients,
    cachedDocuments,
    cachedPatientQueues,
    cachedDepartmentRecords,
    offlineDocumentsQueue,
  ];
}

typedef $$CachedPatientsTableCreateCompanionBuilder =
    CachedPatientsCompanion Function({
      required String id,
      Value<String?> profileId,
      required String firstName,
      required String lastName,
      required DateTime dateOfBirth,
      required String gender,
      required String contactNumber,
      Value<String?> email,
      required String address,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedPatientsTableUpdateCompanionBuilder =
    CachedPatientsCompanion Function({
      Value<String> id,
      Value<String?> profileId,
      Value<String> firstName,
      Value<String> lastName,
      Value<DateTime> dateOfBirth,
      Value<String> gender,
      Value<String> contactNumber,
      Value<String?> email,
      Value<String> address,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedPatientsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedPatientsTable> {
  $$CachedPatientsTableFilterComposer({
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

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactNumber => $composableBuilder(
    column: $table.contactNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPatientsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedPatientsTable> {
  $$CachedPatientsTableOrderingComposer({
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

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactNumber => $composableBuilder(
    column: $table.contactNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPatientsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedPatientsTable> {
  $$CachedPatientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get contactNumber => $composableBuilder(
    column: $table.contactNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedPatientsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedPatientsTable,
          CachedPatient,
          $$CachedPatientsTableFilterComposer,
          $$CachedPatientsTableOrderingComposer,
          $$CachedPatientsTableAnnotationComposer,
          $$CachedPatientsTableCreateCompanionBuilder,
          $$CachedPatientsTableUpdateCompanionBuilder,
          (
            CachedPatient,
            BaseReferences<
              _$LocalDatabase,
              $CachedPatientsTable,
              CachedPatient
            >,
          ),
          CachedPatient,
          PrefetchHooks Function()
        > {
  $$CachedPatientsTableTableManager(
    _$LocalDatabase db,
    $CachedPatientsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPatientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPatientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPatientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> profileId = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<DateTime> dateOfBirth = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> contactNumber = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPatientsCompanion(
                id: id,
                profileId: profileId,
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dateOfBirth,
                gender: gender,
                contactNumber: contactNumber,
                email: email,
                address: address,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> profileId = const Value.absent(),
                required String firstName,
                required String lastName,
                required DateTime dateOfBirth,
                required String gender,
                required String contactNumber,
                Value<String?> email = const Value.absent(),
                required String address,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedPatientsCompanion.insert(
                id: id,
                profileId: profileId,
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dateOfBirth,
                gender: gender,
                contactNumber: contactNumber,
                email: email,
                address: address,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPatientsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedPatientsTable,
      CachedPatient,
      $$CachedPatientsTableFilterComposer,
      $$CachedPatientsTableOrderingComposer,
      $$CachedPatientsTableAnnotationComposer,
      $$CachedPatientsTableCreateCompanionBuilder,
      $$CachedPatientsTableUpdateCompanionBuilder,
      (
        CachedPatient,
        BaseReferences<_$LocalDatabase, $CachedPatientsTable, CachedPatient>,
      ),
      CachedPatient,
      PrefetchHooks Function()
    >;
typedef $$CachedDocumentsTableCreateCompanionBuilder =
    CachedDocumentsCompanion Function({
      required String id,
      Value<String?> patientId,
      required String uploaderId,
      required String fileName,
      required String filePath,
      required String fileType,
      required String status,
      Value<String?> ocrText,
      Value<String?> extractedMetadata,
      Value<String?> rejectionReason,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedDocumentsTableUpdateCompanionBuilder =
    CachedDocumentsCompanion Function({
      Value<String> id,
      Value<String?> patientId,
      Value<String> uploaderId,
      Value<String> fileName,
      Value<String> filePath,
      Value<String> fileType,
      Value<String> status,
      Value<String?> ocrText,
      Value<String?> extractedMetadata,
      Value<String?> rejectionReason,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedDocumentsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedDocumentsTable> {
  $$CachedDocumentsTableFilterComposer({
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

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploaderId => $composableBuilder(
    column: $table.uploaderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileType => $composableBuilder(
    column: $table.fileType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractedMetadata => $composableBuilder(
    column: $table.extractedMetadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectionReason => $composableBuilder(
    column: $table.rejectionReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDocumentsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedDocumentsTable> {
  $$CachedDocumentsTableOrderingComposer({
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

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploaderId => $composableBuilder(
    column: $table.uploaderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileType => $composableBuilder(
    column: $table.fileType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractedMetadata => $composableBuilder(
    column: $table.extractedMetadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectionReason => $composableBuilder(
    column: $table.rejectionReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDocumentsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedDocumentsTable> {
  $$CachedDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get uploaderId => $composableBuilder(
    column: $table.uploaderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get fileType =>
      $composableBuilder(column: $table.fileType, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get ocrText =>
      $composableBuilder(column: $table.ocrText, builder: (column) => column);

  GeneratedColumn<String> get extractedMetadata => $composableBuilder(
    column: $table.extractedMetadata,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rejectionReason => $composableBuilder(
    column: $table.rejectionReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedDocumentsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedDocumentsTable,
          CachedDocument,
          $$CachedDocumentsTableFilterComposer,
          $$CachedDocumentsTableOrderingComposer,
          $$CachedDocumentsTableAnnotationComposer,
          $$CachedDocumentsTableCreateCompanionBuilder,
          $$CachedDocumentsTableUpdateCompanionBuilder,
          (
            CachedDocument,
            BaseReferences<
              _$LocalDatabase,
              $CachedDocumentsTable,
              CachedDocument
            >,
          ),
          CachedDocument,
          PrefetchHooks Function()
        > {
  $$CachedDocumentsTableTableManager(
    _$LocalDatabase db,
    $CachedDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<String> uploaderId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> fileType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> ocrText = const Value.absent(),
                Value<String?> extractedMetadata = const Value.absent(),
                Value<String?> rejectionReason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDocumentsCompanion(
                id: id,
                patientId: patientId,
                uploaderId: uploaderId,
                fileName: fileName,
                filePath: filePath,
                fileType: fileType,
                status: status,
                ocrText: ocrText,
                extractedMetadata: extractedMetadata,
                rejectionReason: rejectionReason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> patientId = const Value.absent(),
                required String uploaderId,
                required String fileName,
                required String filePath,
                required String fileType,
                required String status,
                Value<String?> ocrText = const Value.absent(),
                Value<String?> extractedMetadata = const Value.absent(),
                Value<String?> rejectionReason = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedDocumentsCompanion.insert(
                id: id,
                patientId: patientId,
                uploaderId: uploaderId,
                fileName: fileName,
                filePath: filePath,
                fileType: fileType,
                status: status,
                ocrText: ocrText,
                extractedMetadata: extractedMetadata,
                rejectionReason: rejectionReason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedDocumentsTable,
      CachedDocument,
      $$CachedDocumentsTableFilterComposer,
      $$CachedDocumentsTableOrderingComposer,
      $$CachedDocumentsTableAnnotationComposer,
      $$CachedDocumentsTableCreateCompanionBuilder,
      $$CachedDocumentsTableUpdateCompanionBuilder,
      (
        CachedDocument,
        BaseReferences<_$LocalDatabase, $CachedDocumentsTable, CachedDocument>,
      ),
      CachedDocument,
      PrefetchHooks Function()
    >;
typedef $$CachedPatientQueuesTableCreateCompanionBuilder =
    CachedPatientQueuesCompanion Function({
      Value<int> id,
      required String patientId,
      required String status,
      required String department,
      Value<String?> triageNotes,
      required String priorityLevel,
      Value<int?> estimatedWaitMinutes,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$CachedPatientQueuesTableUpdateCompanionBuilder =
    CachedPatientQueuesCompanion Function({
      Value<int> id,
      Value<String> patientId,
      Value<String> status,
      Value<String> department,
      Value<String?> triageNotes,
      Value<String> priorityLevel,
      Value<int?> estimatedWaitMinutes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$CachedPatientQueuesTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedPatientQueuesTable> {
  $$CachedPatientQueuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triageNotes => $composableBuilder(
    column: $table.triageNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priorityLevel => $composableBuilder(
    column: $table.priorityLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedWaitMinutes => $composableBuilder(
    column: $table.estimatedWaitMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPatientQueuesTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedPatientQueuesTable> {
  $$CachedPatientQueuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triageNotes => $composableBuilder(
    column: $table.triageNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priorityLevel => $composableBuilder(
    column: $table.priorityLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedWaitMinutes => $composableBuilder(
    column: $table.estimatedWaitMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPatientQueuesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedPatientQueuesTable> {
  $$CachedPatientQueuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => column,
  );

  GeneratedColumn<String> get triageNotes => $composableBuilder(
    column: $table.triageNotes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priorityLevel => $composableBuilder(
    column: $table.priorityLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedWaitMinutes => $composableBuilder(
    column: $table.estimatedWaitMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedPatientQueuesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedPatientQueuesTable,
          CachedPatientQueue,
          $$CachedPatientQueuesTableFilterComposer,
          $$CachedPatientQueuesTableOrderingComposer,
          $$CachedPatientQueuesTableAnnotationComposer,
          $$CachedPatientQueuesTableCreateCompanionBuilder,
          $$CachedPatientQueuesTableUpdateCompanionBuilder,
          (
            CachedPatientQueue,
            BaseReferences<
              _$LocalDatabase,
              $CachedPatientQueuesTable,
              CachedPatientQueue
            >,
          ),
          CachedPatientQueue,
          PrefetchHooks Function()
        > {
  $$CachedPatientQueuesTableTableManager(
    _$LocalDatabase db,
    $CachedPatientQueuesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPatientQueuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPatientQueuesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedPatientQueuesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> patientId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> department = const Value.absent(),
                Value<String?> triageNotes = const Value.absent(),
                Value<String> priorityLevel = const Value.absent(),
                Value<int?> estimatedWaitMinutes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CachedPatientQueuesCompanion(
                id: id,
                patientId: patientId,
                status: status,
                department: department,
                triageNotes: triageNotes,
                priorityLevel: priorityLevel,
                estimatedWaitMinutes: estimatedWaitMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String patientId,
                required String status,
                required String department,
                Value<String?> triageNotes = const Value.absent(),
                required String priorityLevel,
                Value<int?> estimatedWaitMinutes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => CachedPatientQueuesCompanion.insert(
                id: id,
                patientId: patientId,
                status: status,
                department: department,
                triageNotes: triageNotes,
                priorityLevel: priorityLevel,
                estimatedWaitMinutes: estimatedWaitMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPatientQueuesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedPatientQueuesTable,
      CachedPatientQueue,
      $$CachedPatientQueuesTableFilterComposer,
      $$CachedPatientQueuesTableOrderingComposer,
      $$CachedPatientQueuesTableAnnotationComposer,
      $$CachedPatientQueuesTableCreateCompanionBuilder,
      $$CachedPatientQueuesTableUpdateCompanionBuilder,
      (
        CachedPatientQueue,
        BaseReferences<
          _$LocalDatabase,
          $CachedPatientQueuesTable,
          CachedPatientQueue
        >,
      ),
      CachedPatientQueue,
      PrefetchHooks Function()
    >;
typedef $$CachedDepartmentRecordsTableCreateCompanionBuilder =
    CachedDepartmentRecordsCompanion Function({
      required String id,
      required String patientId,
      required String recorderId,
      required String department,
      required String testType,
      required String testResults,
      required String referenceRangeStatus,
      Value<String?> notes,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedDepartmentRecordsTableUpdateCompanionBuilder =
    CachedDepartmentRecordsCompanion Function({
      Value<String> id,
      Value<String> patientId,
      Value<String> recorderId,
      Value<String> department,
      Value<String> testType,
      Value<String> testResults,
      Value<String> referenceRangeStatus,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedDepartmentRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedDepartmentRecordsTable> {
  $$CachedDepartmentRecordsTableFilterComposer({
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

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recorderId => $composableBuilder(
    column: $table.recorderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get testType => $composableBuilder(
    column: $table.testType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get testResults => $composableBuilder(
    column: $table.testResults,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceRangeStatus => $composableBuilder(
    column: $table.referenceRangeStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDepartmentRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedDepartmentRecordsTable> {
  $$CachedDepartmentRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recorderId => $composableBuilder(
    column: $table.recorderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get testType => $composableBuilder(
    column: $table.testType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get testResults => $composableBuilder(
    column: $table.testResults,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceRangeStatus => $composableBuilder(
    column: $table.referenceRangeStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDepartmentRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedDepartmentRecordsTable> {
  $$CachedDepartmentRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get recorderId => $composableBuilder(
    column: $table.recorderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => column,
  );

  GeneratedColumn<String> get testType =>
      $composableBuilder(column: $table.testType, builder: (column) => column);

  GeneratedColumn<String> get testResults => $composableBuilder(
    column: $table.testResults,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referenceRangeStatus => $composableBuilder(
    column: $table.referenceRangeStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedDepartmentRecordsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedDepartmentRecordsTable,
          CachedDepartmentRecord,
          $$CachedDepartmentRecordsTableFilterComposer,
          $$CachedDepartmentRecordsTableOrderingComposer,
          $$CachedDepartmentRecordsTableAnnotationComposer,
          $$CachedDepartmentRecordsTableCreateCompanionBuilder,
          $$CachedDepartmentRecordsTableUpdateCompanionBuilder,
          (
            CachedDepartmentRecord,
            BaseReferences<
              _$LocalDatabase,
              $CachedDepartmentRecordsTable,
              CachedDepartmentRecord
            >,
          ),
          CachedDepartmentRecord,
          PrefetchHooks Function()
        > {
  $$CachedDepartmentRecordsTableTableManager(
    _$LocalDatabase db,
    $CachedDepartmentRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDepartmentRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedDepartmentRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedDepartmentRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> patientId = const Value.absent(),
                Value<String> recorderId = const Value.absent(),
                Value<String> department = const Value.absent(),
                Value<String> testType = const Value.absent(),
                Value<String> testResults = const Value.absent(),
                Value<String> referenceRangeStatus = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDepartmentRecordsCompanion(
                id: id,
                patientId: patientId,
                recorderId: recorderId,
                department: department,
                testType: testType,
                testResults: testResults,
                referenceRangeStatus: referenceRangeStatus,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String patientId,
                required String recorderId,
                required String department,
                required String testType,
                required String testResults,
                required String referenceRangeStatus,
                Value<String?> notes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedDepartmentRecordsCompanion.insert(
                id: id,
                patientId: patientId,
                recorderId: recorderId,
                department: department,
                testType: testType,
                testResults: testResults,
                referenceRangeStatus: referenceRangeStatus,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDepartmentRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedDepartmentRecordsTable,
      CachedDepartmentRecord,
      $$CachedDepartmentRecordsTableFilterComposer,
      $$CachedDepartmentRecordsTableOrderingComposer,
      $$CachedDepartmentRecordsTableAnnotationComposer,
      $$CachedDepartmentRecordsTableCreateCompanionBuilder,
      $$CachedDepartmentRecordsTableUpdateCompanionBuilder,
      (
        CachedDepartmentRecord,
        BaseReferences<
          _$LocalDatabase,
          $CachedDepartmentRecordsTable,
          CachedDepartmentRecord
        >,
      ),
      CachedDepartmentRecord,
      PrefetchHooks Function()
    >;
typedef $$OfflineDocumentsQueueTableCreateCompanionBuilder =
    OfflineDocumentsQueueCompanion Function({
      required String id,
      Value<String?> patientId,
      required String uploaderId,
      required String fileName,
      required String localFilePath,
      required String fileType,
      Value<String?> ocrText,
      Value<String?> extractedMetadata,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$OfflineDocumentsQueueTableUpdateCompanionBuilder =
    OfflineDocumentsQueueCompanion Function({
      Value<String> id,
      Value<String?> patientId,
      Value<String> uploaderId,
      Value<String> fileName,
      Value<String> localFilePath,
      Value<String> fileType,
      Value<String?> ocrText,
      Value<String?> extractedMetadata,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$OfflineDocumentsQueueTableFilterComposer
    extends Composer<_$LocalDatabase, $OfflineDocumentsQueueTable> {
  $$OfflineDocumentsQueueTableFilterComposer({
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

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploaderId => $composableBuilder(
    column: $table.uploaderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileType => $composableBuilder(
    column: $table.fileType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractedMetadata => $composableBuilder(
    column: $table.extractedMetadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineDocumentsQueueTableOrderingComposer
    extends Composer<_$LocalDatabase, $OfflineDocumentsQueueTable> {
  $$OfflineDocumentsQueueTableOrderingComposer({
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

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploaderId => $composableBuilder(
    column: $table.uploaderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileType => $composableBuilder(
    column: $table.fileType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractedMetadata => $composableBuilder(
    column: $table.extractedMetadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineDocumentsQueueTableAnnotationComposer
    extends Composer<_$LocalDatabase, $OfflineDocumentsQueueTable> {
  $$OfflineDocumentsQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get uploaderId => $composableBuilder(
    column: $table.uploaderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileType =>
      $composableBuilder(column: $table.fileType, builder: (column) => column);

  GeneratedColumn<String> get ocrText =>
      $composableBuilder(column: $table.ocrText, builder: (column) => column);

  GeneratedColumn<String> get extractedMetadata => $composableBuilder(
    column: $table.extractedMetadata,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OfflineDocumentsQueueTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $OfflineDocumentsQueueTable,
          OfflineDocument,
          $$OfflineDocumentsQueueTableFilterComposer,
          $$OfflineDocumentsQueueTableOrderingComposer,
          $$OfflineDocumentsQueueTableAnnotationComposer,
          $$OfflineDocumentsQueueTableCreateCompanionBuilder,
          $$OfflineDocumentsQueueTableUpdateCompanionBuilder,
          (
            OfflineDocument,
            BaseReferences<
              _$LocalDatabase,
              $OfflineDocumentsQueueTable,
              OfflineDocument
            >,
          ),
          OfflineDocument,
          PrefetchHooks Function()
        > {
  $$OfflineDocumentsQueueTableTableManager(
    _$LocalDatabase db,
    $OfflineDocumentsQueueTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineDocumentsQueueTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OfflineDocumentsQueueTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineDocumentsQueueTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<String> uploaderId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> localFilePath = const Value.absent(),
                Value<String> fileType = const Value.absent(),
                Value<String?> ocrText = const Value.absent(),
                Value<String?> extractedMetadata = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineDocumentsQueueCompanion(
                id: id,
                patientId: patientId,
                uploaderId: uploaderId,
                fileName: fileName,
                localFilePath: localFilePath,
                fileType: fileType,
                ocrText: ocrText,
                extractedMetadata: extractedMetadata,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> patientId = const Value.absent(),
                required String uploaderId,
                required String fileName,
                required String localFilePath,
                required String fileType,
                Value<String?> ocrText = const Value.absent(),
                Value<String?> extractedMetadata = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflineDocumentsQueueCompanion.insert(
                id: id,
                patientId: patientId,
                uploaderId: uploaderId,
                fileName: fileName,
                localFilePath: localFilePath,
                fileType: fileType,
                ocrText: ocrText,
                extractedMetadata: extractedMetadata,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineDocumentsQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $OfflineDocumentsQueueTable,
      OfflineDocument,
      $$OfflineDocumentsQueueTableFilterComposer,
      $$OfflineDocumentsQueueTableOrderingComposer,
      $$OfflineDocumentsQueueTableAnnotationComposer,
      $$OfflineDocumentsQueueTableCreateCompanionBuilder,
      $$OfflineDocumentsQueueTableUpdateCompanionBuilder,
      (
        OfflineDocument,
        BaseReferences<
          _$LocalDatabase,
          $OfflineDocumentsQueueTable,
          OfflineDocument
        >,
      ),
      OfflineDocument,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$CachedPatientsTableTableManager get cachedPatients =>
      $$CachedPatientsTableTableManager(_db, _db.cachedPatients);
  $$CachedDocumentsTableTableManager get cachedDocuments =>
      $$CachedDocumentsTableTableManager(_db, _db.cachedDocuments);
  $$CachedPatientQueuesTableTableManager get cachedPatientQueues =>
      $$CachedPatientQueuesTableTableManager(_db, _db.cachedPatientQueues);
  $$CachedDepartmentRecordsTableTableManager get cachedDepartmentRecords =>
      $$CachedDepartmentRecordsTableTableManager(
        _db,
        _db.cachedDepartmentRecords,
      );
  $$OfflineDocumentsQueueTableTableManager get offlineDocumentsQueue =>
      $$OfflineDocumentsQueueTableTableManager(_db, _db.offlineDocumentsQueue);
}
