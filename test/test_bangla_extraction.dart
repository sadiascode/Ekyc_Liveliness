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

  group('Address and Post Office Extraction Tests', () {
    test('Extract address from গ্রাম label with colon', () {
      final input = 'গ্রাম: সুন্দরপুর, উপজেলা: সদর, জেলা: ঢাকা';
      final result = NidOcrService.parseBack('', bengaliText: input);
      // Value is on same line, only extract after colon
      expect(result.address, 'সুন্দরপুর, উপজেলা: সদর, জেলা: ঢাকা');
    });

    test('Extract address from গ্রাম label with Bengali colon', () {
      final input = 'গ্রামঃ সুন্দরপুর, উপজেলা: সদর, জেলা: ঢাকা';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, 'সুন্দরপুর, উপজেলা: সদর, জেলা: ঢাকা');
    });

    test('Extract address from রাস্তা label', () {
      final input = 'রাস্তা: বাসস্ট্যান্ড রোড, উপজেলা: সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, 'বাসস্ট্যান্ড রোড, উপজেলা: সদর');
    });

    test('Extract address from next line after গ্রাম', () {
      final input = 'গ্রাম\nসুন্দরপুর, উপজেলা: সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, 'সুন্দরপুর, উপজেলা: সদর');
    });

    test('Extract multiline address', () {
      final input =
          'গ্রাম: সুন্দরপুর\nউপজেলা: সদর\nজেলা: ঢাকা\nডাকঘর: সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      // When value is on same line as label, collect from next lines until ডাকঘর
      expect(result.address, 'সুন্দরপুর উপজেলা: সদর জেলা: ঢাকা');
    });

    test('Extract post office from label with colon', () {
      final input = 'ডাকঘর: সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.postOffice, 'সদর');
    });

    test('Extract post office from label with Bengali colon', () {
      final input = 'ডাকঘরঃ সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.postOffice, 'সদর');
    });

    test('Extract post office from next line', () {
      final input = 'ডাকঘর\nসদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      // When value is from next line, collect from subsequent lines
      expect(result.postOffice, 'সদর');
    });

    test('Extract post office with post code', () {
      final input = 'ডাকঘর: সদর, ১২৩৪';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.postOffice, 'সদর, ১২৩৪');
    });

    test('Extract both address and post office', () {
      final input =
          'গ্রাম: সুন্দরপুর, উপজেলা: সদর, জেলা: ঢাকা\nডাকঘর: সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      // Address is on same line as label
      expect(result.address, 'সুন্দরপুর, উপজেলা: সদর, জেলা: ঢাকা');
      expect(result.postOffice, 'সদর');
    });

    test('Return null when গ্রাম/রাস্তা label not found', () {
      final input = 'ডাকঘর: সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, isNull);
    });

    test('Return null when ডাকঘর label not found', () {
      final input = 'গ্রাম: সুন্দরপুর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.postOffice, isNull);
    });

    test('Handle missing address label gracefully', () {
      final input = 'উপজেলা: সদর\nজেলা: ঢাকা';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, isNull);
    });

    test('Handle extra spaces in address', () {
      final input = 'গ্রাম:  সুন্দরপুর,  উপজেলা:  সদর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, 'সুন্দরপুর, উপজেলা: সদর');
    });

    test('Regression test: Extract address until ডাকঘর, post office until end', () {
      final input = 'গ্রাম/রাস্তা: ফুলবাড়ী দক্ষিনপাড়া, ফুলবাড়ি উত্তর, মধ্য, দক্ষিণ, ডাকঘর: কাজির চর - ২১০০, শ্রীবরদী, শেরপুর';
      final result = NidOcrService.parseBack('', bengaliText: input);
      expect(result.address, 'ফুলবাড়ী দক্ষিনপাড়া, ফুলবাড়ি উত্তর, মধ্য, দক্ষিণ');
      // Post office extracts from ডাকঘর: onwards until location field
      expect(result.postOffice, 'কাজির চর - ২১০০, শ্রীবরদী, শেরপুর');
    });
  });
}
