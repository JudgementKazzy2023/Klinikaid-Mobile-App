enum SubmissionStatus {
  submitted,
  aiVerified,
  staffReview,
  approved,
  rejected;

  static SubmissionStatus fromDbStatus(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return SubmissionStatus.approved;
      case 'rejected':
        return SubmissionStatus.rejected;
      case 'pending':
      default:
        return SubmissionStatus.submitted;
    }
  }

  String toDbStatus() {
    switch (this) {
      case SubmissionStatus.approved:
        return 'approved';
      case SubmissionStatus.rejected:
        return 'rejected';
      default:
        return 'pending';
    }
  }
}
