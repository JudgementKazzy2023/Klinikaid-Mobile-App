enum Gender {
  male,
  female,
  other;

  static Gender fromString(String value) {
    switch (value.toLowerCase()) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'other':
      default:
        return Gender.other;
    }
  }

  String toJsonValue() {
    return name;
  }
}

class Patient {
  final String id;
  final String? profileId;
  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  final Gender gender;
  final String contactNumber;
  final String? email;
  final String address;
  final DateTime createdAt;
  final DateTime updatedAt;

  Patient({
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

  String get fullName => '$firstName $lastName';

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as String,
      profileId: json['profile_id'] as String?,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
      gender: Gender.fromString(json['gender'] as String? ?? 'other'),
      contactNumber: json['contact_number'] as String? ?? '',
      email: json['email'] as String?,
      address: json['address'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_id': profileId,
      'first_name': firstName,
      'last_name': lastName,
      'date_of_birth': dateOfBirth.toIso8601String().substring(0, 10), // YYYY-MM-DD
      'gender': gender.toJsonValue(),
      'contact_number': contactNumber,
      'email': email,
      'address': address,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
