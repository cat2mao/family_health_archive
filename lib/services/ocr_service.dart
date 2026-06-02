import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Detected document type from OCR
enum OcrDocumentType {
  medicalRecord, // 病历/就诊记录
  invoice, // 发票/收据
  prescription, // 处方
  labReport, // 检验/检查报告
  unknown, // 未知
}

/// Data extracted from OCR of a medical record or invoice image
class OcrExtractedData {
  String? hospital;
  String? diagnosis;
  String? doctorName;
  String? symptoms;
  String? cost;
  String? date;
  String? medicineName;
  String? result;
  String? treatment;
  String? rawText;
  OcrDocumentType documentType;

  OcrExtractedData({
    this.hospital,
    this.diagnosis,
    this.doctorName,
    this.symptoms,
    this.cost,
    this.date,
    this.medicineName,
    this.result,
    this.treatment,
    this.rawText,
    this.documentType = OcrDocumentType.unknown,
  });

  bool get hasAnyData =>
      hospital != null ||
      diagnosis != null ||
      doctorName != null ||
      symptoms != null ||
      cost != null ||
      date != null ||
      medicineName != null ||
      result != null ||
      treatment != null;

  /// Get a human-readable document type name
  String get documentTypeName {
    switch (documentType) {
      case OcrDocumentType.medicalRecord:
        return '病历';
      case OcrDocumentType.invoice:
        return '发票/收据';
      case OcrDocumentType.prescription:
        return '处方';
      case OcrDocumentType.labReport:
        return '检验/检查报告';
      case OcrDocumentType.unknown:
        return '文档';
    }
  }

  /// Fields that should be auto-filled based on document type
  /// Returns a map of field label to value
  Map<String, String> get autoFillFields {
    final fields = <String, String>{};
    if (hospital != null) fields['医院'] = hospital!;
    if (diagnosis != null) fields['诊断'] = diagnosis!;
    if (doctorName != null) fields['医生'] = doctorName!;
    if (symptoms != null) fields['症状'] = symptoms!;
    if (cost != null) fields['费用'] = '¥$cost';
    if (date != null) fields['日期'] = date!;
    if (medicineName != null) fields['药品'] = medicineName!;
    if (result != null) fields['结果'] = result!;
    if (treatment != null) fields['处置'] = treatment!;
    return fields;
  }

  @override
  String toString() {
    return 'OcrExtractedData(hospital=$hospital, diagnosis=$diagnosis, doctor=$doctorName, '
        'symptoms=$symptoms, cost=$cost, date=$date, medicine=$medicineName, result=$result, treatment=$treatment, '
        'type=$documentTypeName)';
  }
}

class OcrService {
  static TextRecognizer? _textRecognizer;
  static bool _isInitialized = false;

  /// Initialize the text recognizer (lazy initialization for better error handling)
  static Future<void> _ensureInitialized() async {
    if (_isInitialized && _textRecognizer != null) return;
    try {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize Chinese text recognizer: $e');
      // Fallback to Latin script
      try {
        _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        _isInitialized = true;
        debugPrint('Using Latin text recognizer as fallback');
      } catch (e2) {
        debugPrint('Failed to initialize any text recognizer: $e2');
        rethrow;
      }
    }
  }

  /// Recognize text from an image file and extract medical record information
  static Future<OcrExtractedData> recognizeFromFile(String filePath) async {
    try {
      await _ensureInitialized();
      if (_textRecognizer == null) {
        return OcrExtractedData();
      }

      final inputImage = InputImage.fromFilePath(filePath);
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      final rawText = recognizedText.text;
      debugPrint('OCR raw text: $rawText');

      if (rawText.isEmpty) {
        return OcrExtractedData(rawText: rawText);
      }

      return _extractMedicalInfo(rawText);
    } catch (e) {
      debugPrint('OCR recognition failed: $e');
      return OcrExtractedData();
    }
  }

  /// Detect document type from raw text
  static OcrDocumentType _detectDocumentType(String fullText) {
    // Invoice patterns
    final invoicePatterns = [
      '发票', '收据', '缴费', '收费', '费用清单', '账单',
      '增值税', '电子发票', '医疗收费', '门诊收费',
    ];
    int invoiceScore = 0;
    for (final p in invoicePatterns) {
      if (fullText.contains(p)) invoiceScore++;
    }

    // Prescription patterns
    final prescriptionPatterns = [
      '处方', '处方签', '用法', '用量', '每日', '每次',
      '口服', '外用', '静滴', '注射', 'Rx', 'rx',
    ];
    int prescriptionScore = 0;
    for (final p in prescriptionPatterns) {
      if (fullText.contains(p)) prescriptionScore++;
    }

    // Lab report patterns
    final labPatterns = [
      '检验', '检查', '报告单', '化验', '血常规', '尿常规',
      '生化', '免疫', '参考值', '参考范围', '结果', '单位',
    ];
    int labScore = 0;
    for (final p in labPatterns) {
      if (fullText.contains(p)) labScore++;
    }

    // Medical record patterns
    final recordPatterns = [
      '病历', '门诊', '住院', '就诊', '入院', '出院',
      '主诉', '现病史', '既往史', '诊断', '医嘱',
    ];
    int recordScore = 0;
    for (final p in recordPatterns) {
      if (fullText.contains(p)) recordScore++;
    }

    // Determine the highest score
    final scores = {
      OcrDocumentType.invoice: invoiceScore,
      OcrDocumentType.prescription: prescriptionScore,
      OcrDocumentType.labReport: labScore,
      OcrDocumentType.medicalRecord: recordScore,
    };

    final maxEntry = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (maxEntry.value == 0) return OcrDocumentType.unknown;
    return maxEntry.key;
  }

  /// Extract structured medical information from raw OCR text
  static OcrExtractedData _extractMedicalInfo(String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final fullText = lines.join(' ');

    // Detect document type
    final docType = _detectDocumentType(fullText);

    String? hospital;
    String? diagnosis;
    String? doctorName;
    String? symptoms;
    String? cost;
    String? date;
    String? medicineName;
    String? result;
    String? treatment;

    // --- Hospital detection ---
    final hospitalPatterns = [
      RegExp(r'[\u4e00-\u9fa5]{2,}(?:医院|诊所|卫生院|中心|门诊部|卫生服务中心|附属医院|人民医院|妇幼保健院|儿童医院|中医院)'),
      RegExp(r'(?:医院|诊所|卫生院)[\u4e00-\u9fa5]{0,6}'),
    ];
    for (final pattern in hospitalPatterns) {
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        hospital = match.group(0)?.trim();
        break;
      }
    }
    for (final line in lines.take(5)) {
      if (line.contains('医院') || line.contains('诊所') || line.contains('卫生')) {
        final match = RegExp(r'[\u4e00-\u9fa5]{2,}(?:医院|诊所|卫生院|中心|门诊部)').firstMatch(line);
        if (match != null) {
          hospital = match.group(0)?.trim();
          break;
        }
      }
    }

    // --- Date detection ---
    final datePatterns = [
      RegExp(r'(\d{4})[年\-/\.](\d{1,2})[月\-/\.](\d{1,2})[日号]?'),
      RegExp(r'(\d{4})(\d{2})(\d{2})'),
    ];
    for (final pattern in datePatterns) {
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        date = match.group(0)?.trim();
        break;
      }
    }

    // --- Diagnosis detection (enhanced: prefer 门诊诊断/诊断) ---
    final diagnosisKeywords = [
      '门诊诊断', '初步诊断', '临床诊断', '最终诊断', '出院诊断', '入院诊断',
      '西医诊断', '中医诊断', '诊断', '病名', '疾病名称',
    ];
    for (final keyword in diagnosisKeywords) {
      final idx = fullText.indexOf(keyword);
      if (idx >= 0) {
        final after = fullText.substring(idx + keyword.length).trim();
        final cleaned = after.replaceFirst(RegExp(r'^[:：\s]+'), '');
        final match = RegExp(r'^[\u4e00-\u9fa5A-Za-z0-9\s\(\)（）]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          diagnosis = match.group(0)!.trim();
          if (diagnosis!.length > 50) {
            diagnosis = diagnosis.substring(0, 50);
          }
          break;
        }
      }
    }
    if (diagnosis == null) {
      final diseasePattern = RegExp(
          r'(?:支气管炎|肺炎|感冒|发烧|腹泻|过敏|湿疹|咳嗽|哮喘|贫血|中耳炎|扁桃体炎|胃肠炎|手足口病|水痘|麻疹|结膜炎|鼻炎|皮炎|外伤|骨折|扭伤|烧伤|烫伤)[\u4e00-\u9fa5]*');
      final match = diseasePattern.firstMatch(fullText);
      if (match != null) {
        diagnosis = match.group(0)?.trim();
      }
    }

    // --- Doctor name detection ---
    final doctorKeywords = ['医师', '医生', '主治', '主任', '副主任', '主诊'];
    for (final keyword in doctorKeywords) {
      final pattern = RegExp('(?:主治|主任|副主任|主诊|主管)?(?:医师|医生)[：:\s]*([\u4e00-\u9fa5]{2,4})');
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        doctorName = match.group(1)?.trim();
        break;
      }
    }
    if (doctorName == null) {
      final pattern = RegExp(r'(?:医生|医师|主治)[：:]\s*([\u4e00-\u9fa5]{2,4})');
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        doctorName = match.group(1)?.trim();
      }
    }

    // --- Symptoms detection (enhanced for 病史) ---
    final symptomKeywords = [
      '主诉', '现病史', '病史', '临床表现', '既往史', '个人史',
      '家族史', '过敏史', '症状', '不适',
    ];
    for (final keyword in symptomKeywords) {
      final idx = fullText.indexOf(keyword);
      if (idx >= 0) {
        final after = fullText.substring(idx + keyword.length).trim();
        final cleaned = after.replaceFirst(RegExp(r'^[:：\s]+'), '');
        final match = RegExp(r'^[\u4e00-\u9fa5A-Za-z0-9\s,，、。;；]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          symptoms = match.group(0)!.trim();
          if (symptoms!.length > 100) {
            symptoms = symptoms.substring(0, 100);
          }
          break;
        }
      }
    }

    // --- Cost detection (invoices only) ---
    // Only extract cost when the document is an invoice
    final List<double> foundCosts = [];
    
    if (docType == OcrDocumentType.invoice) {
      // Pattern: Match 小写金额 patterns (优先识别阿拉伯数字金额)
      final smallCostPatterns = [
        // Match "合计(小写)" or "金额合计(小写)" followed by amount
        RegExp(r'(?:合计|总计|总额)[（(]小写[)）][：:\s]*¥?\s*(\d+\.?\d*)'),
        // Match standard total patterns
        RegExp(r'(?:合计|总计|总额|价税合计|实付|应付|实收|应收|缴费|金额)[：:\s]*¥?\s*(\d+\.?\d*)'),
        // Match "金额 XX.XX 元" pattern
        RegExp(r'(?:金额|费用|总计)[：:\s]*(\d+\.?\d+)\s*元'),
        // Match ¥ followed by number
        RegExp(r'¥\s*(\d+\.?\d*)'),
      ];
    
    for (final pattern in smallCostPatterns) {
      final matches = pattern.allMatches(fullText);
      for (final match in matches) {
        final costStr = match.group(1)?.trim();
        if (costStr != null) {
          final parsed = double.tryParse(costStr);
          if (parsed != null && parsed > 0) {
            foundCosts.add(parsed);
          }
        }
      }
      if (foundCosts.isNotEmpty) break; // Use first pattern that finds matches
    }
    
      if (foundCosts.isNotEmpty) {
        // Sum all found costs (handles multiple invoices)
        final totalCost = foundCosts.reduce((a, b) => a + b);
        cost = totalCost.toStringAsFixed(2);
      }
    }

    // --- Medicine name detection ---
    final medicineKeywords = ['处方', '药品', '用药', '药物', '品名', '药品名称'];
    for (final keyword in medicineKeywords) {
      final pattern = RegExp('$keyword[：:\s]*([\u4e00-\u9fa5A-Za-z0-9\s]+)');
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        final name = match.group(1)?.trim();
        if (name != null && name.length >= 2) {
          medicineName = name.length > 30 ? name.substring(0, 30) : name;
          break;
        }
      }
    }

    // --- Result detection ---
    final resultKeywords = ['检查结果', '检验结果', '结果', '所见', '结论'];
    for (final keyword in resultKeywords) {
      final idx = fullText.indexOf(keyword);
      if (idx >= 0) {
        final after = fullText.substring(idx + keyword.length).trim();
        final cleaned = after.replaceFirst(RegExp(r'^[:：\s]+'), '');
        final match = RegExp(r'^[\u4e00-\u9fa5A-Za-z0-9\s\+\-]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          result = match.group(0)!.trim();
          if (result!.length > 100) {
            result = result.substring(0, 100);
          }
          break;
        }
      }
    }

    // --- Treatment detection ---
    final treatmentKeywords = ['处置', '处理', '治疗', '医嘱', '处方医嘱', '治疗方案'];
    for (final keyword in treatmentKeywords) {
      final idx = fullText.indexOf(keyword);
      if (idx >= 0) {
        final after = fullText.substring(idx + keyword.length).trim();
        final cleaned = after.replaceFirst(RegExp(r'^[:：\s]+'), '');
        final match = RegExp(r'^[\u4e00-\u9fa5A-Za-z0-9\s,，、。;；\+\-]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          treatment = match.group(0)!.trim();
          if (treatment!.length > 100) {
            treatment = treatment.substring(0, 100);
          }
          break;
        }
      }
    }

    return OcrExtractedData(
      hospital: hospital,
      diagnosis: diagnosis,
      doctorName: doctorName,
      symptoms: symptoms,
      cost: cost,
      date: date,
      medicineName: medicineName,
      result: result,
      treatment: treatment,
      rawText: rawText,
      documentType: docType,
    );
  }

  /// Dispose the text recognizer
  static void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    _isInitialized = false;
  }
}
