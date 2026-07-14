class TemplateField {
  final String key;
  final String label;
  final String type; // 'text' | 'textarea' | 'select' | 'date'
  final bool required;
  final List<String>? options;

  const TemplateField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    this.options,
  });
}

class DocumentTemplate {
  final String id;
  final String name;
  final String description;
  final List<TemplateField> fields;

  const DocumentTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.fields,
  });
}

const List<DocumentTemplate> clinicTemplates = [
  DocumentTemplate(
    id: 'referral-form',
    name: 'Referral Form',
    description: 'Submit doctor recommendations and requests for clinic services.',
    fields: [
      TemplateField(key: 'referring_physician', label: 'Referring Physician', type: 'text', required: true),
      TemplateField(key: 'referring_clinic', label: 'Referring Clinic / Hospital', type: 'text', required: false),
      TemplateField(key: 'reason_for_referral', label: 'Reason for Referral', type: 'textarea', required: true),
      TemplateField(key: 'requested_service', label: 'Requested Service', type: 'select', required: true, options: ['Laboratory', 'Imaging', 'Ultrasound', 'ECG']),
      TemplateField(key: 'referral_date', label: 'Referral Date', type: 'date', required: true),
    ],
  ),
  DocumentTemplate(
    id: 'lab-request',
    name: 'Laboratory Request',
    description: 'Submit request forms for specific blood and urine diagnostic tests.',
    fields: [
      TemplateField(key: 'ordering_physician', label: 'Ordering Physician', type: 'text', required: true),
      TemplateField(key: 'tests_requested', label: 'Tests Requested', type: 'textarea', required: true),
      TemplateField(key: 'fasting_required', label: 'Fasting Required?', type: 'select', required: false, options: ['Yes', 'No']),
      TemplateField(key: 'request_date', label: 'Request Date', type: 'date', required: true),
    ],
  ),
  DocumentTemplate(
    id: 'med-cert',
    name: 'Medical Certificate Request',
    description: 'Request official health certifications for school or work clearances.',
    fields: [
      TemplateField(key: 'purpose', label: 'Purpose of Certificate', type: 'textarea', required: true),
      TemplateField(key: 'date_needed', label: 'Date Needed', type: 'date', required: true),
    ],
  ),
  DocumentTemplate(
    id: 'procedure-consent',
    name: 'Consent Form',
    description: 'Acknowledge and consent to clinical laboratory diagnostic operations.',
    fields: [
      TemplateField(key: 'procedure', label: 'Clinical Procedure', type: 'text', required: true),
      TemplateField(key: 'consent_given', label: 'I Give My Consent?', type: 'select', required: true, options: ['Yes', 'No']),
      TemplateField(key: 'consent_date', label: 'Date of Consent', type: 'date', required: true),
    ],
  ),
  DocumentTemplate(
    id: 'patient-intake',
    name: 'Patient Intake Form',
    description: 'Submit basic demographics and complaints before visiting the clinic.',
    fields: [
      TemplateField(key: 'chief_complaint', label: 'Chief Health Complaint', type: 'textarea', required: true),
    ],
  ),
  DocumentTemplate(
    id: 'results-release',
    name: 'Results Release Authorization',
    description: 'Authorize third-party release or sharing of diagnostic lab results.',
    fields: [
      TemplateField(key: 'release_to', label: 'Authorize Release To (Name)', type: 'text', required: true),
      TemplateField(key: 'results_type', label: 'Clinical Results Authorized for Release', type: 'text', required: true),
      TemplateField(key: 'authorization_date', label: 'Authorization Date', type: 'date', required: true),
    ],
  ),
];
