import '../../../core/utils/manila_time.dart';
import 'document_templates.dart';

/// The answers that mean "the patient declined", mirroring the shared rule
/// /^(no|n|false|declined?|refused?|i do not consent)$/i.
final RegExp _declinedAnswerPattern = RegExp(
  r'^(no|n|false|declined?|refused?|i do not consent)$',
  caseSensitive: false,
);

/// True when [value] is one of the answers that mean the patient declined.
///
/// A decline is a valid answer to a consent question: the patient may decline
/// the form, and the form is still submitted for reception to review. It is
/// not a refused submission, and it says nothing about the account's
/// data-privacy consent.
bool isDeclinedConsentAnswer(String value) =>
    _declinedAnswerPattern.hasMatch(value.trim());

/// True when [field] asks the patient for consent.
bool isConsentField(TemplateField field) =>
    field.consent ||
    RegExp('consent', caseSensitive: false).hasMatch(field.key);

/// The consent fields of [template] the patient declined in [answers].
List<TemplateField> declinedConsentFields(
  DocumentTemplate template,
  Map<String, dynamic> answers,
) =>
    template.fields
        .where(
          (field) =>
              isConsentField(field) &&
              isDeclinedConsentAnswer(answers[field.key]?.toString() ?? ''),
        )
        .toList();

/// The latest date a template answer may carry: [kTemplateDateMaxYearsAhead]
/// years after [today].
DateTime latestTemplateDate(DateTime today) =>
    addYears(today, kTemplateDateMaxYearsAhead);

/// Why [value] is not an acceptable answer to [field], as a phrase that
/// follows the field label; null when the answer is acceptable.
///
/// The same rules the shared clinic contract uses: length bounds, the date
/// window, past-only dates, and the allowed choices. The length is counted
/// after trimming, because a stray space is not part of the answer.
String? templateFieldProblem(
  TemplateField field,
  String value,
  DateTime today,
) {
  final answer = value.trim();

  final maxLength = templateFieldMaxLength(field);
  if (maxLength != null && answer.length > maxLength) {
    return 'must be $maxLength characters or fewer (has ${answer.length})';
  }

  if (field.type == 'date') {
    if (parseIsoDate(answer) == null) return 'must be a valid date';

    final todayIso = formatIsoDate(today);
    if (answer.compareTo(kTemplateDateMin) < 0) {
      return 'must be on or after $kTemplateDateMin';
    }
    if (field.notFuture && answer.compareTo(todayIso) > 0) {
      return 'cannot be after today ($todayIso)';
    }
    final latest = formatIsoDate(latestTemplateDate(today));
    if (answer.compareTo(latest) > 0) {
      return 'must be on or before $latest';
    }
  }

  if (field.type == 'select' &&
      !(field.options ?? const <String>[]).contains(answer)) {
    return 'must be one of the allowed options';
  }

  return null;
}
