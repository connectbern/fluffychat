// Connect-Bern: Phone-number normalization for the "Message a phone number"
// (start WhatsApp chat) feature.
//
// This is a direct Dart port of the proven TypeScript implementation used in
// Chagai's Cinny web client (src/app/features/wa-start-chat/normalizePhone.ts,
// 13 passing unit tests). Keep the two in sync if the rules ever change.
//
// The goal: take ANY human-typed phone number (however messy) and turn it into a
// clean E.164 string (digits only, single leading `+`) suitable for the mautrix
// WhatsApp bridge command `!wa pm <number>`.
//
// ─────────────────────────────────────────────────────────────────────────────
// NORMALIZATION RULES (exact — identical to the Cinny version)
// ─────────────────────────────────────────────────────────────────────────────
// 1. Strip EVERYTHING that is not a digit, EXCEPT a single leading `+`.
//    Removed: spaces (incl. non-breaking space U+00A0 / narrow no-break U+202F),
//    brackets ( ) [ ], dashes - – —, dots ., slashes / \, and any other symbol
//    or letter. A `+` only counts if it is the very first non-whitespace char.
//
// 2. Decide the country code:
//    a. If the cleaned value starts with `+`  → it is ALREADY international.
//       Keep the country code as-is → E.164 = `+` followed by all the digits.
//    b. If it starts with `00`               → international prefix. Replace the
//       leading `00` with `+` → E.164 as in (a). (e.g. `0041 79…` → `+4179…`.)
//    c. Otherwise it is a BARE / LOCAL number (may have a trunk `0`, or none):
//       we do NOT know the country, so we produce an ORDERED CANDIDATE LIST by
//       trying likely country codes in a fixed preference order (see below). For
//       each candidate country code we DROP one leading national trunk `0` (the
//       digit used inside a country before the subscriber number) when that
//       country uses a trunk 0, then prefix the country's dial code.
//
// 3. CANDIDATE COUNTRY ORDER (for bare/local numbers) — Switzerland FIRST, then
//    geographically nearby countries:
//       +41  Switzerland   (trunk 0)      ← primary / default
//       +49  Germany       (trunk 0)
//       +33  France        (trunk 0)
//       +39  Italy         (NO trunk 0 — the leading 0 is part of the number)
//       +43  Austria       (trunk 0)
//       +423 Liechtenstein (trunk 0)
//
// 4. Output for EVERY input:
//      - `e164`             : the single best/primary E.164 candidate, or ''.
//      - `candidates`       : the ordered list of ALL viable E.164 candidates.
//      - `wasInternational` : true if the input already carried +/00.

/// A country dial code we try for a bare/local number.
class CountryDial {
  /// Human-readable label for display.
  final String name;

  /// Dial code digits WITHOUT the leading + (e.g. '41', '423').
  final String code;

  /// Whether this country uses a national trunk '0' that must be dropped.
  final bool trunkZero;

  const CountryDial({
    required this.name,
    required this.code,
    required this.trunkZero,
  });
}

/// Ordered list of country codes to try for a bare/local number.
/// Switzerland is intentionally FIRST (Chagai's default), then nearby countries.
/// Adjust here if the preference order ever changes.
const List<CountryDial> kCandidateCountries = [
  CountryDial(name: 'Switzerland', code: '41', trunkZero: true),
  CountryDial(name: 'Germany', code: '49', trunkZero: true),
  CountryDial(name: 'France', code: '33', trunkZero: true),
  CountryDial(name: 'Italy', code: '39', trunkZero: false),
  CountryDial(name: 'Austria', code: '43', trunkZero: true),
  CountryDial(name: 'Liechtenstein', code: '423', trunkZero: true),
];

/// The result of normalizing a phone number.
class NormalizedPhone {
  /// Primary E.164 candidate (best guess). Empty string if no digits.
  final String e164;

  /// Ordered list of all E.164 candidates (deduped).
  final List<String> candidates;

  /// True when the raw input already had a + or 00 international prefix.
  final bool wasInternational;

  const NormalizedPhone({
    required this.e164,
    required this.candidates,
    required this.wasInternational,
  });
}

final RegExp _nonDigit = RegExp(r'\D+');
final RegExp _leadingZeros = RegExp(r'^0+');
// JS `\s` (used by the TS version's trim) covers NBSP (U+00A0) and the narrow
// no-break space (U+202F); Dart's `trim()` also strips these Unicode whitespace
// characters, so pasted numbers with them are handled the same way.

/// Rule 1: strip everything except digits, preserving a single leading `+`.
/// A `+` is only honored when it is the first non-whitespace character.
String stripToDigitsPlus(String raw) {
  final trimmed = raw.trim();
  final hasLeadingPlus = trimmed.startsWith('+');
  // Remove every non-digit character (this also drops any inner '+').
  final digits = trimmed.replaceAll(_nonDigit, '');
  return hasLeadingPlus ? '+$digits' : digits;
}

/// Build the E.164 candidate for a BARE local number under a given country.
/// Drops one leading trunk '0' (all leading zeros) when the country uses one.
String _localToE164(String localDigits, CountryDial country) {
  var subscriber = localDigits;
  if (country.trunkZero && subscriber.startsWith('0')) {
    subscriber = subscriber.replaceFirst(_leadingZeros, '');
  }
  if (subscriber.isEmpty) return '';
  return '+${country.code}$subscriber';
}

/// The main entry point. Accepts any messy input and returns the normalized
/// E.164 + ordered candidate list per the rules documented at the top of the
/// file. Mirrors normalizePhone() in the Cinny TypeScript version exactly.
NormalizedPhone normalizePhone(String raw) {
  final cleaned = stripToDigitsPlus(raw);

  // No usable digits at all.
  final digitCount = cleaned.replaceAll(_nonDigit, '').length;
  if (digitCount == 0) {
    return const NormalizedPhone(
      e164: '',
      candidates: [],
      wasInternational: false,
    );
  }

  // Rule 2a: already has a leading '+'.
  if (cleaned.startsWith('+')) {
    return NormalizedPhone(
      e164: cleaned,
      candidates: [cleaned],
      wasInternational: true,
    );
  }

  // Rule 2b: leading '00' international prefix → replace with '+'.
  if (cleaned.startsWith('00')) {
    final e164 = '+${cleaned.substring(2)}';
    return NormalizedPhone(
      e164: e164,
      candidates: [e164],
      wasInternational: true,
    );
  }

  // Rule 2c: bare/local number → ordered candidate list across countries.
  final candidates = <String>[];
  for (final country in kCandidateCountries) {
    final candidate = _localToE164(cleaned, country);
    if (candidate.isNotEmpty && !candidates.contains(candidate)) {
      candidates.add(candidate);
    }
  }

  return NormalizedPhone(
    e164: candidates.isNotEmpty ? candidates.first : '',
    candidates: candidates,
    wasInternational: false,
  );
}

/// The bare digits (no +) of an E.164 string — what mautrix `!wa pm` wants after
/// the leading +. mautrix-whatsapp accepts the number with or without the +, but
/// we pass it WITH the + for clarity/robustness. Exposed for callers that need
/// the plain digits.
String e164Digits(String e164) => e164.replaceAll(_nonDigit, '');
