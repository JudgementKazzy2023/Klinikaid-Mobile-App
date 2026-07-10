/// Preset templates for receptionist clinical document rejection reasons.
/// All templates are patient-friendly, actionable, and exceed the 20-character minimum constraint.
const rejectPresets = {
  'Illegible text':
      'The uploaded document text is not legible. Please retake a '
      'clearer, well-lit photo and resubmit.',
  'Unrelated files':
      'The uploaded file does not appear to be a valid medical '
      'referral or requisition. Please upload the correct document.',
  'Wrong patient':
      'The patient name on this document does not match your account '
      'details. Please upload a document that belongs to you.',
  'Incomplete document':
      'This document appears to be incomplete or missing pages. '
      'Please upload the full document and resubmit.',
  'Expired referral':
      'This referral appears to be expired or outdated. Please '
      'provide a current referral from your physician.',
  'Wrong test requisition':
      'The test requisition does not match the requested service. '
      'Please upload the correct requisition form.',
  'Duplicate submission':
      'This document has already been submitted and processed. '
      'A duplicate is not required.',
};
