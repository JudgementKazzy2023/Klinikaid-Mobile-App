import '../utils/patient_code.dart';

class SpecialistPatient {
  final String id;
  final String specialistId;
  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  final String gender; // 'male', 'female', 'other'
  final String? contactNumber;
  final String? email;
  final String? address;
  final DateTime createdAt;
  final DateTime updatedAt;

  SpecialistPatient({
    required this.id,
    required this.specialistId,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    this.contactNumber,
    this.email,
    this.address,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName';

  int get age {
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  String get patientCode => patientCodeFromId(id);

  factory SpecialistPatient.fromJson(Map<String, dynamic> json) {
    return SpecialistPatient(
      id: json['id'] as String,
      specialistId: json['specialist_id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
      gender: json['gender'] as String,
      contactNumber: json['contact_number'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'specialist_id': specialistId,
      'first_name': firstName,
      'last_name': lastName,
      'date_of_birth': dateOfBirth.toIso8601String().substring(0, 10),
      'gender': gender,
      'contact_number': contactNumber,
      'email': email,
      'address': address,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
