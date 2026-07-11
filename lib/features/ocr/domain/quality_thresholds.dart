/// Quality threshold configurations for OCR document processing.
class QualityThresholds {
  /// Minimum OCR quality score required to pass without a warning.
  /// Score >= 85 is a PASS (inclusive), score < 85 is a WARNING.
  static const int minOcrPassScore = 85;
}
