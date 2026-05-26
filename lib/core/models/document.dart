import 'patient.dart';
import 'profile.dart';

enum DocumentStatus {
  pending,
  approved,
  rejected;

  static DocumentStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'approved':
        return DocumentStatus.approved;
      case 'rejected':
        return DocumentStatus.rejected;
      case 'pending':
      default:
        return DocumentStatus.pending;
    }
  }

  String toJsonValue() {
    return name;
  }
}

class Document {
  final String id;
  final String? patientId;
  final String uploaderId;
  final String fileName;
  final String filePath;
  final String fileType;
  final DocumentStatus status;
  final String? ocrText;
  final Map<String, dynamic>? extractedMetadata;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Profile? uploader;
  final Patient? patient;

  Document({
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
    this.uploader,
    this.patient,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      patientId: json['patient_id'] as String?,
      uploaderId: json['uploader_id'] as String,
      fileName: json['file_name'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      fileType: json['file_type'] as String? ?? '',
      status: DocumentStatus.fromString(json['status'] as String? ?? 'pending'),
      ocrText: json['ocr_text'] as String?,
      extractedMetadata: json['extracted_metadata'] as Map<String, dynamic>?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      uploader: json['uploader'] != null ? Profile.fromJson(json['uploader'] as Map<String, dynamic>) : null,
      patient: json['patient'] != null ? Patient.fromJson(json['patient'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'uploader_id': uploaderId,
      'file_name': fileName,
      'file_path': filePath,
      'file_type': fileType,
      'status': status.toJsonValue(),
      'ocr_text': ocrText,
      'extracted_metadata': extractedMetadata,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'uploader': uploader?.toJson(),
      'patient': patient?.toJson(),
    };
  }
}
