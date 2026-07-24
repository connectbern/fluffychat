// Connect-Bern: Unit tests for the phone-normalization functions.
//
// Direct Dart port of the Cinny test suite
// (src/app/features/wa-start-chat/normalizePhone.test.ts) — same 13 cases, so
// the two implementations are kept behaviourally identical.
//
// Run: flutter test test/wa_start_chat/normalize_phone_test.dart

import 'package:fluffychat/pages/wa_start_chat/normalize_phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripToDigitsPlus', () {
    test('removes spaces, dashes, dots, brackets, slashes', () {
      expect(stripToDigitsPlus('079 123 45 67'), '0791234567');
      expect(stripToDigitsPlus('(079) 123-45.67'), '0791234567');
      expect(stripToDigitsPlus('079/123/45/67'), '0791234567');
    });
    test('keeps a single leading + only, drops inner +', () {
      expect(stripToDigitsPlus('+41 79 123 45 67'), '+41791234567');
      expect(stripToDigitsPlus('++41 79'), '+4179');
    });
    test('a + not at the start is dropped', () {
      expect(stripToDigitsPlus('0041+79'), '004179');
    });
    test('strips letters and misc symbols; empty stays empty', () {
      expect(stripToDigitsPlus('  +41 79 '), '+4179');
      expect(stripToDigitsPlus(''), '');
      expect(stripToDigitsPlus('abc'), '');
    });
  });

  group('normalizePhone — already international', () {
    test('leading + kept as-is', () {
      final r = normalizePhone('+49 151 23456789');
      expect(r.e164, '+4915123456789');
      expect(r.candidates, ['+4915123456789']);
      expect(r.wasInternational, true);
    });
    test('leading 00 becomes +', () {
      final r = normalizePhone('0041 79 123 45 67');
      expect(r.e164, '+41791234567');
      expect(r.candidates, ['+41791234567']);
      expect(r.wasInternational, true);
    });
    test('messy international with brackets and dashes', () {
      final r = normalizePhone('+1 (415) 555-2671');
      expect(r.e164, '+14155552671');
      expect(r.wasInternational, true);
    });
  });

  group('normalizePhone — bare/local', () {
    test('Swiss trunk 0 dropped, +41 first; full ordered list', () {
      final r = normalizePhone('079 123 45 67');
      expect(r.wasInternational, false);
      expect(r.e164, '+41791234567');
      expect(r.candidates, [
        '+41791234567', // CH: drop trunk 0
        '+49791234567', // DE: drop 0
        '+33791234567', // FR: drop 0
        '+390791234567', // IT: KEEP leading 0
        '+43791234567', // AT: drop 0
        '+423791234567', // LI: drop 0
      ]);
    });
    test('Italy keeps the leading 0 while others drop it', () {
      final r = normalizePhone('0791234567');
      expect(r.candidates.contains('+390791234567'), true);
      expect(r.candidates.contains('+41791234567'), true);
    });
    test('bare number with no leading zero', () {
      final r = normalizePhone('791234567');
      expect(r.e164, '+41791234567');
      expect(r.candidates.contains('+39791234567'), true);
    });
    test('candidate list is deduped and CH-first', () {
      final r = normalizePhone('44 123');
      expect(r.candidates.first.startsWith('+41'), true);
      expect(r.candidates.toSet().length, r.candidates.length);
    });
  });

  group('empty / junk', () {
    test('no digits yields empty result', () {
      final r = normalizePhone('no numbers here');
      expect(r.e164, '');
      expect(r.candidates, isEmpty);
      expect(r.wasInternational, false);
    });
  });

  group('e164Digits', () {
    test('drops the + and stray non-digits', () {
      expect(e164Digits('+41791234567'), '41791234567');
      expect(e164Digits('+1 (415) 555-2671'), '14155552671');
    });
  });
}
