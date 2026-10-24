/// Helpers for the reception-board document search.
///
/// The search box on the reception board filters the *whole* documents table on
/// the server, not the capped page the board already loaded. Two grammars read
/// the user's term, so two different sets of characters have to be neutralised
/// before the term reaches the database:
///
///  - PostgREST's `like`/`ilike` operators are unusable here. After parsing,
///    PostgREST rewrites every `*` in their value into `%` — a wildcard alias
///    for clients that cannot URL-encode a percent — and provides no escape for
///    it, not even inside the double-quoted values the `or=` grammar accepts.
///    A term containing `*` would therefore match unrelated rows. The regex
///    operators `match`/`imatch` (Postgres `~`/`~*`) have no such alias, so
///    the search matches with `imatch` against a POSIX regular expression built
///    from the term: every regex metacharacter (including `*`) is
///    backslash-escaped so the term matches literally. `~*` is an unanchored
///    substring match, so no `%`-wrapping is needed, and `%`/`_` are not regex
///    metacharacters, so they are literal for free.
///
///  - PostgREST's `or=` grammar treats `,` (condition separator), `(` and `)`
///    (grouping), `.` (field/operator separator) and `"` (value quoting) as
///    structural. A term containing any of them would be misparsed as extra
///    conditions or rejected outright.
///
/// The two are escaped in-band, one layer at a time:
///
///  1. [escapeRegexLiteral] backslash-escapes the term's regex metacharacters
///     so Postgres's regex engine matches them literally.
///  2. [quotePostgrestValue] wraps the result in double quotes and escapes `"`
///     and `\` for PostgREST's quoted-value lexer, so `,`, `(`, `)` and `.` are
///     treated as value characters rather than grammar.
///
/// The two backslash-escapes compose: PostgREST's quoted lexer turns each `\\`
/// back into a single `\`, which is exactly the escape the regex engine needs
/// to read `*`, `.` and friends as literals.
///
/// Ported from web's `src/lib/reception-search.ts`, whose tests pin every one
/// of these behaviours.
library;

/// Longest search term accepted, in characters after trimming.
const int maxSearchTermLength = 100;

/// Maximum documents returned; the caller fetches one extra to detect this
/// bound.
const int searchResultLimit = 50;

/// Most first/last split points tried for a multi-word term.
const int maxNameSplits = 6;

/// Escape the POSIX regular-expression metacharacters in a term so it matches
/// literally under Postgres `~*`.
///
/// Backslash is escaped first so that a backslash already in the term is not
/// mistaken for an escape it did not intend. Only punctuation is escaped:
/// `\<letter>` sequences are regex character classes (`\d`, `\w`, ...), so
/// escaping a letter would change its meaning instead of pinning it.
String escapeRegexLiteral(String term) {
  return term.replaceAllMapped(
    RegExp(r'[\\.[\]{}()*+?^$|]'),
    (match) => '\\${match[0]}',
  );
}

/// Quote a value for embedding in a PostgREST filter string.
///
/// Inside double quotes PostgREST treats `"` and `\` as escape sequences, so
/// those are escaped; everything else — including the `,`, `(`, `)` and `.`
/// that would otherwise be structural in an `or=` filter — is taken literally.
String quotePostgrestValue(String value) {
  return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// The `imatch` pattern for "the term appears anywhere", escaped for the regex
/// engine and quoted for PostgREST. Ready to embed as
/// `column.imatch.${buildSearchPattern(term)}`.
String buildSearchPattern(String term) {
  return quotePostgrestValue(escapeRegexLiteral(term));
}

/// PostgREST `or` conditions matching a patient's "first last" name the way the
/// board's local filter did (`"${first} ${last}".contains(term)`): one
/// condition per point where the term's words could split between first_name
/// and last_name, plus each column on its own. Single-word terms only need the
/// per-column conditions.
List<String> patientNameConditions(String term) {
  final conditions = <String>[
    'first_name.imatch.${buildSearchPattern(term)}',
    'last_name.imatch.${buildSearchPattern(term)}',
  ];
  final words =
      term.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  for (var i = 1; i < words.length && i <= maxNameSplits; i++) {
    final first = words.sublist(0, i).join(' ');
    final last = words.sublist(i).join(' ');
    conditions.add(
      'and(first_name.imatch.${buildSearchPattern(first)},'
      'last_name.imatch.${buildSearchPattern(last)})',
    );
  }
  return conditions;
}
