import 'package:flutter_test/flutter_test.dart';
import '../lib/services/nid_ocr_service.dart';

void main() {
  group('Bangla Name Extraction Tests', () {
    test('Extract name from label with colon', () {
      final input = 'নাম: মোঃ আব্দুল করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, 'মোঃ আব্দুল করিম');
    });

    test('Extract name from label with Bengali colon', () {
      final input = 'নামঃ মোঃ আব্দুল করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, 'মোঃ আব্দুল করিম');
    });

    test('Extract name from next line', () {
      final input = 'নাম\nসাদিয়া আক্তার মন';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, 'সাদিয়া আক্তার মন');
    });

    test('Reject Bengali digits only', () {
      final input = '৮০';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });

    test('Reject Bengali NID number', () {
      final input = '৫১১৭৪৪৮২৮১';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });

    test('Reject English digits', () {
      final input = '123456';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });

    test('Reject Latin letters', () {
      final input = 'SADIA 123';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });

    test('Reject empty input', () {
      final input = '';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });

    test('Extract name from mixed OCR output', () {
      final input = 'নাম: মোছাম্মদ সাদিয়া\nআইডি: ৫১১৭৪৪৮২৮১';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, 'মোছাম্মদ সাদিয়া');
    });

    test('Fallback extraction when no label', () {
      final input = 'মোঃ আব্দুল করিম\nআইডি: ৫১১৭৪৪৮২৮১';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, 'মোঃ আব্দুল করিম');
    });

    test('Reject father label', () {
      final input = 'পিতা: আব্দুল করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });

    test('Reject mother label', () {
      final input = 'মাতা: ফাতেমা বেগম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, isNull);
    });
  });
}
