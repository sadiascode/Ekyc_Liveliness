import 'package:flutter_test/flutter_test.dart';
import 'package:ekyc_app/services/nid_ocr_service.dart';

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

  group('Bangla Parent Name Extraction Tests', () {
    test('Extract father name from label with colon', () {
      final input = 'পিতা: মোঃ আব্দুল করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaFatherName, 'মোঃ আব্দুল করিম');
    });

    test('Extract father name from label with Bengali colon', () {
      final input = 'পিতাঃ মোঃ আব্দুল করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaFatherName, 'মোঃ আব্দুল করিম');
    });

    test('Extract father name from next line', () {
      final input = 'পিতা\nমোঃ আব্দুল করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaFatherName, 'মোঃ আব্দুল করিম');
    });

    test('Extract mother name from label with colon', () {
      final input = 'মাতা: রহিমা খাতুন';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaMotherName, 'রহিমা খাতুন');
    });

    test('Extract mother name from label with Bengali colon', () {
      final input = 'মাতাঃ রহিমা খাতুন';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaMotherName, 'রহিমা খাতুন');
    });

    test('Extract mother name from next line', () {
      final input = 'মাতা\nরহিমা খাতুন';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaMotherName, 'রহিমা খাতুন');
    });

    test('Extract both parent names from mixed OCR', () {
      final input = 'নাম: সাদিয়া\nপিতা: মোঃ আব্দুল করিম\nমাতা: রহিমা খাতুন';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaName, 'সাদিয়া');
      expect(result.banglaFatherName, 'মোঃ আব্দুল করিম');
      expect(result.banglaMotherName, 'রহিমা খাতুন');
    });

    test('Handle extra spaces in parent names', () {
      final input = 'পিতা:  মোঃ   আব্দুল   করিম';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaFatherName, 'মোঃ আব্দুল করিম');
    });

    test('Return null when parent label not found', () {
      final input = 'নাম: সাদিয়া';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaFatherName, isNull);
      expect(result.banglaMotherName, isNull);
    });

    test('Reject digits in parent name', () {
      final input = 'পিতা: ১২৩৪৫';
      final result = NidOcrService.parse('', bengaliText: input);
      expect(result.banglaFatherName, isNull);
    });
  });
}
