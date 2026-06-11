import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  String? medicineUsage; // 用法用量
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
    this.medicineUsage,
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
      medicineUsage != null ||
      result != null ||
      treatment != null;

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

  Map<String, String> get autoFillFields {
    final fields = <String, String>{};
    if (hospital != null) fields['医院'] = hospital!;
    if (diagnosis != null) fields['诊断'] = diagnosis!;
    if (doctorName != null) fields['医生'] = doctorName!;
    if (symptoms != null) fields['症状'] = symptoms!;
    if (cost != null) fields['费用'] = '¥$cost';
    if (date != null) fields['日期'] = date!;
    if (medicineName != null) fields['药品'] = medicineName!;
    if (medicineUsage != null) fields['用法用量'] = medicineUsage!;
    if (result != null) fields['结果'] = result!;
    if (treatment != null) fields['处置'] = treatment!;
    return fields;
  }

  @override
  String toString() {
    return 'OcrExtractedData(hospital=$hospital, diagnosis=$diagnosis, doctor=$doctorName, '
        'symptoms=$symptoms, cost=$cost, date=$date, medicine=$medicineName, usage=$medicineUsage, '
        'result=$result, treatment=$treatment, type=$documentTypeName)';
  }
}

class OcrService {
  static TextRecognizer? _textRecognizer;
  static bool _isInitialized = false;

  static Future<void> _ensureInitialized() async {
    if (_isInitialized && _textRecognizer != null) return;
    try {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize Chinese text recognizer: $e');
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

  /// Preprocess an image for OCR: resize, grayscale, contrast enhancement.
  /// Returns path to the preprocessed temporary file.
  static Future<String> _preprocessForOcr(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return filePath;

      var image = original;

      // Resize: keep reasonable size for OCR (2048px max dimension)
      final maxDim = max(image.width, image.height);
      if (maxDim > 2048) {
        final scale = 2048 / maxDim;
        image = img.copyResize(image,
            width: (image.width * scale).round(),
            height: (image.height * scale).round());
      }

      // Convert to grayscale
      image = img.grayscale(image);

      // Contrast enhancement: linear contrast stretch
      image = _contrastStretch(image);

      // Save to temp file
      final dir = await getApplicationDocumentsDirectory();
      final tempDir = Directory(p.join(dir.path, 'ocr_temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final tempPath = p.join(tempDir.path,
          'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final outputBytes = img.encodeJpg(image, quality: 92);
      await File(tempPath).writeAsBytes(outputBytes);

      return tempPath;
    } catch (e) {
      debugPrint('Image preprocessing failed, using original: $e');
      return filePath;
    }
  }

  /// Apply linear contrast stretching to enhance text readability
  static img.Image _contrastStretch(img.Image image) {
    int minVal = 255, maxVal = 0;
    for (final pixel in image) {
      final lum = img.getLuminance(pixel).toInt();
      if (lum < minVal) minVal = lum;
      if (lum > maxVal) maxVal = lum;
    }
    if (maxVal <= minVal) return image; // No stretch possible

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final a = pixel.a.toInt();
        final nr = ((r - minVal) * 255 ~/ (maxVal - minVal)).clamp(0, 255);
        final ng = ((g - minVal) * 255 ~/ (maxVal - minVal)).clamp(0, 255);
        final nb = ((b - minVal) * 255 ~/ (maxVal - minVal)).clamp(0, 255);
        image.setPixel(x, y, img.ColorRgba8(nr, ng, nb, a));
      }
    }
    return image;
  }

  /// Recognize text from an image file with preprocessing and extract medical info
  static Future<OcrExtractedData> recognizeFromFile(String filePath) async {
    try {
      await _ensureInitialized();
      if (_textRecognizer == null) {
        return OcrExtractedData();
      }

      // Preprocess the image for better OCR accuracy
      final preprocessedPath = await _preprocessForOcr(filePath);

      final inputImage = InputImage.fromFilePath(preprocessedPath);
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      // Clean up temp preprocessed file
      if (preprocessedPath != filePath) {
        try {
          await File(preprocessedPath).delete();
        } catch (_) {}
      }

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
    final invoicePatterns = [
      '发票', '收据', '缴费', '收费', '费用清单', '账单',
      '增值税', '电子发票', '医疗收费', '门诊收费',
    ];
    int invoiceScore = 0;
    for (final p in invoicePatterns) {
      if (fullText.contains(p)) invoiceScore++;
    }

    final prescriptionPatterns = [
      '处方', '处方签', '用法', '用量', '每日', '每次',
      '口服', '外用', '静滴', '注射', 'Rx', 'rx',
    ];
    int prescriptionScore = 0;
    for (final p in prescriptionPatterns) {
      if (fullText.contains(p)) prescriptionScore++;
    }

    final labPatterns = [
      '检验', '检查', '报告单', '化验', '血常规', '尿常规',
      '生化', '免疫', '参考值', '参考范围', '结果', '单位',
    ];
    int labScore = 0;
    for (final p in labPatterns) {
      if (fullText.contains(p)) labScore++;
    }

    final recordPatterns = [
      '病历', '门诊', '住院', '就诊', '入院', '出院',
      '主诉', '现病史', '既往史', '诊断', '医嘱',
    ];
    int recordScore = 0;
    for (final p in recordPatterns) {
      if (fullText.contains(p)) recordScore++;
    }

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
    // Pre-process: merge broken lines (OCR often splits Chinese text mid-sentence)
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    // Merge short lines that are likely continuations (no punctuation at end)
    final mergedLines = <String>[];
    for (final line in lines) {
      if (mergedLines.isNotEmpty &&
          mergedLines.last.isNotEmpty &&
          !mergedLines.last.endsWith('。') &&
          !mergedLines.last.endsWith('，') &&
          !mergedLines.last.endsWith(':') &&
          !mergedLines.last.endsWith('：') &&
          mergedLines.last.length < 40) {
        mergedLines.last = '${mergedLines.last}$line';
      } else {
        mergedLines.add(line);
      }
    }
    final fullText = mergedLines.join(' ');

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

    // --- Hospital detection (improved: keep longest match) ---
    String? hospitalBest;
    final hospitalPatterns = [
      RegExp(r'[一-龥]{2,}(?:医院|诊所|卫生院|中心|门诊部|卫生服务中心|附属医院|人民医院|妇幼保健院|儿童医院|中医院)'),
      RegExp(r'(?:医院|诊所|卫生院)[一-龥]{0,6}'),
    ];
    for (final pattern in hospitalPatterns) {
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        final h = match.group(0)?.trim();
        if (hospitalBest == null || (h != null && h.length > hospitalBest.length)) {
          hospitalBest = h;
        }
      }
    }
    // Also check first few lines for hospital name
    for (final line in lines.take(5)) {
      if (line.contains('医院') || line.contains('诊所') || line.contains('卫生')) {
        final match = RegExp(r'[一-龥]{2,}(?:医院|诊所|卫生院|中心|门诊部)').firstMatch(line);
        if (match != null) {
          final h = match.group(0)?.trim();
          if (h != null && (hospitalBest == null || h.length > hospitalBest.length)) {
            hospitalBest = h;
          }
        }
      }
    }
    hospital = hospitalBest;

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

    // --- Diagnosis detection ---
    final diagnosisKeywords = [
      '门诊诊断', '初步诊断', '临床诊断', '最终诊断', '出院诊断', '入院诊断',
      '西医诊断', '中医诊断', '诊断', '病名', '疾病名称',
    ];
    for (final keyword in diagnosisKeywords) {
      final idx = fullText.indexOf(keyword);
      if (idx >= 0) {
        final after = fullText.substring(idx + keyword.length).trim();
        final cleaned = after.replaceFirst(RegExp(r'^[:：\s]+'), '');
        final match = RegExp(r'^[一-龥A-Za-z0-9\s\(\)（）]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          diagnosis = match.group(0)!.trim();
          if (diagnosis.length > 50) {
            diagnosis = diagnosis.substring(0, 50);
          }
          break;
        }
      }
    }
    if (diagnosis == null) {
      // Expanded disease pattern (200+ common diseases)
      const diseasePatterns = [
        '支气管炎', '肺炎', '感冒', '发烧', '发热', '腹泻', '过敏', '湿疹', '咳嗽', '哮喘',
        '贫血', '中耳炎', '扁桃体炎', '胃肠炎', '手足口病', '水痘', '麻疹', '结膜炎', '鼻炎',
        '皮炎', '外伤', '骨折', '扭伤', '烧伤', '烫伤', '高血压', '糖尿病', '冠心病',
        '脑梗塞', '脑梗死', '心肌梗塞', '心力衰竭', '心律失常', '高血脂', '高脂血症',
        '脂肪肝', '肝硬化', '肝炎', '乙肝', '甲肝', '丙肝', '胆囊炎', '胆结石',
        '肾结石', '肾炎', '肾衰竭', '尿路感染', '前列腺炎', '前列腺增生',
        '甲状腺', '甲亢', '甲减', '痛风', '关节炎', '类风湿', '骨质疏松',
        '颈椎病', '腰椎间盘', '坐骨神经痛', '肩周炎', '腱鞘炎', '滑囊炎',
        '胃炎', '胃溃疡', '十二指肠溃疡', '反流性食管炎', '肠炎', '便秘', '痔疮',
        '胰腺炎', '阑尾炎', '腹膜炎', '肠梗阻', '疝气', '肛裂', '肛瘘',
        '咽炎', '喉炎', '扁桃体', '鼻窦炎', '中耳炎', '外耳道炎', '麦粒肿',
        '青光眼', '白内障', '视网膜', '角膜炎', '干眼症', '飞蚊症',
        '口腔溃疡', '牙龈炎', '牙周炎', '龋齿', '根尖周炎', '颞下颌',
        '抑郁症', '焦虑症', '失眠', '神经衰弱', '偏头痛', '三叉神经痛',
        '面瘫', '帕金森', '阿尔茨海默', '癫痫', '脑出血', '脑外伤',
        '银屑病', '白癜风', '荨麻疹', '带状疱疹', '痤疮', '脱发', '灰指甲',
        '静脉曲张', '血栓', '动脉硬化', '脉管炎', '淋巴炎',
        '贫血', '白血病', '血小板减少', '过敏性紫癜', '血友病',
        '系统性红斑狼疮', '强直性脊柱炎', '干燥综合征', '硬皮病', '多发性肌炎',
        '子宫肌瘤', '卵巢囊肿', '盆腔炎', '阴道炎', '宫颈炎', '月经不调',
        '更年期', '前列腺炎', '前列腺增生', '阳痿', '早泄',
        '小儿肺炎', '小儿腹泻', '小儿发热', '小儿惊厥', '小儿哮喘', '小儿湿疹',
        '猫瘟', '犬瘟', '细小病毒', '冠状病毒', '猫传腹', '猫癣', '耳螨',
      ];
      for (final disease in diseasePatterns) {
        if (fullText.contains(disease)) {
          diagnosis = disease;
          break;
        }
      }
    }

    // --- Doctor name detection ---
    final doctorPattern = RegExp(r'(?:主治|主任|副主任|主诊|主管)?(?:医师|医生)[：:\s]*([一-龥]{2,4})');
    final doctorMatch = doctorPattern.firstMatch(fullText);
    if (doctorMatch != null) {
      doctorName = doctorMatch.group(1)?.trim();
    }
    if (doctorName == null) {
      final pattern = RegExp(r'(?:医生|医师|主治)[：:]\s*([一-龥]{2,4})');
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        doctorName = match.group(1)?.trim();
      }
    }

    // --- Symptoms detection ---
    final symptomKeywords = [
      '主诉', '现病史', '病史', '临床表现', '既往史', '个人史',
      '家族史', '过敏史', '症状', '不适',
    ];
    for (final keyword in symptomKeywords) {
      final idx = fullText.indexOf(keyword);
      if (idx >= 0) {
        final after = fullText.substring(idx + keyword.length).trim();
        final cleaned = after.replaceFirst(RegExp(r'^[:：\s]+'), '');
        final match = RegExp(r'^[一-龥A-Za-z0-9\s,，、。;；]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          symptoms = match.group(0)!.trim();
          if (symptoms.length > 100) {
            symptoms = symptoms.substring(0, 100);
          }
          break;
        }
      }
    }

    // --- Cost detection (invoices only) ---
    final List<double> foundCosts = [];

    if (docType == OcrDocumentType.invoice) {
      final smallCostPatterns = [
        RegExp(r'(?:合计|总计|总额)[（(]小写[)）][：:\s]*¥?\s*(\d+\.?\d*)'),
        RegExp(r'(?:合计|总计|总额|价税合计|实付|应付|实收|应收|缴费|金额)[：:\s]*¥?\s*(\d+\.?\d*)'),
        RegExp(r'(?:金额|费用|总计)[：:\s]*(\d+\.?\d+)\s*元'),
        RegExp(r'¥\s*(\d+\.?\d+)'),
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
        if (foundCosts.isNotEmpty) break;
      }

      if (foundCosts.isNotEmpty) {
        final totalCost = foundCosts.reduce((a, b) => a + b);
        cost = totalCost.toStringAsFixed(2);
      }
    }

    // --- Medicine name detection (improved: multiple medicines with specs) ---
    final List<String> medicines = [];
    String? medicineUsage;

    // Pattern 1: Look for prescription section with numbered medicines
    final prescriptionSectionPattern = RegExp(r'(?:处方|药品|用药|Rp)[：:\s]*([\s\S]*?)(?=(?:诊断|处置|医嘱|签名|盖章|$))');
    final prescriptionMatch = prescriptionSectionPattern.firstMatch(fullText);
    if (prescriptionMatch != null) {
      final prescriptionText = prescriptionMatch.group(1) ?? '';
      // Split by numbered items or newlines
      final medicineLines = prescriptionText.split(RegExp(r'[\n\r]+'));
      for (final line in medicineLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // Match medicine with optional spec: "药品名 规格 用法"
        final medPattern = RegExp(r'(?:\d+[.、)）]\s*)?([一-龥A-Za-z][一-龥A-Za-z0-9\s()（）]*(?:片|胶囊|颗粒|口服液|滴剂|软膏|乳膏|凝胶|喷雾剂|气雾剂|注射液|糖浆|混悬液|散|丸|膏|贴|栓)?)[\s,，]*([0-9]+(?:mg|g|ml|μg|ug|片|粒|支|袋|瓶|盒)?(?:\s*[×xX*]\s*[0-9]+(?:片|粒|支|袋|瓶|盒))?)?[\s,，]*((?:口服|外用|静滴|注射|滴注|含服|喷入|涂抹|外敷|每日\d+次|每次\d+(?:片|粒|支|袋|ml|g)?|(?:一日|每天)\d+次|(?:一次|每次)\d+(?:片|粒|支|袋|ml|g)?)[\s,，]*(?:\d+(?:天|日|周))?)?');
        final medMatch = medPattern.firstMatch(trimmed);
        if (medMatch != null) {
          final name = medMatch.group(1)?.trim();
          final spec = medMatch.group(2)?.trim();
          final usage = medMatch.group(3)?.trim();
          if (name != null && name.length >= 2) {
            String medicine = name;
            if (spec != null && spec.isNotEmpty) {
              medicine += ' $spec';
            }
            medicines.add(medicine);
            if (usage != null && usage.isNotEmpty) {
              if (medicineUsage == null) {
                medicineUsage = usage;
              } else {
                medicineUsage += '\n$usage';
              }
            }
          }
        }
      }
    }

    // Pattern 2: If no medicines found, try simpler patterns
    if (medicines.isEmpty) {
      final medicineKeywords = ['处方', '药品', '用药', '药物', '品名', '药品名称'];
      for (final keyword in medicineKeywords) {
        final pattern = RegExp('$keyword[：:\s]*([一-龥A-Za-z0-9\s]+)');
        final match = pattern.firstMatch(fullText);
        if (match != null) {
          final name = match.group(1)?.trim();
          if (name != null && name.length >= 2) {
            medicines.add(name.length > 30 ? name.substring(0, 30) : name);
            break;
          }
        }
      }
    }

    // Pattern 3: Look for common medicine patterns in the text
    if (medicines.isEmpty) {
      final commonMedPattern = RegExp(r'([一-龥]{2,10}(?:片|胶囊|颗粒|口服液|滴剂|糖浆|软膏|乳膏|凝胶|喷雾剂|注射液))[\s,，]*([0-9]+(?:mg|g|ml|μg|ug)?(?:\s*[×xX*]\s*[0-9]+(?:片|粒|支|袋|盒))?)?');
      final medMatches = commonMedPattern.allMatches(fullText);
      for (final match in medMatches) {
        final name = match.group(1)?.trim();
        final spec = match.group(2)?.trim();
        if (name != null && name.length >= 2) {
          String medicine = name;
          if (spec != null && spec.isNotEmpty) {
            medicine += ' $spec';
          }
          medicines.add(medicine);
        }
      }
    }

    // Combine medicines with newlines
    if (medicines.isNotEmpty) {
      medicineName = medicines.join('\n');
    }

    // Detect usage/dosage if not found with medicines
    if (medicineUsage == null) {
      final usagePatterns = [
        RegExp(r'(?:用法|用量|服用方法|使用方法)[：:\s]*([一-龥A-Za-z0-9\s,，、]+?)(?=(?:诊断|处置|医嘱|$))'),
        RegExp(r'(?:口服|外用|静滴|注射|滴注|含服)[，,\s]*(?:每次|一次)\s*([0-9]+\s*(?:片|粒|支|袋|ml|g)[，,\s]*(?:一日|每天|每日)\s*[0-9]+\s*次(?:[，,\s]*连服\s*[0-9]+\s*(?:天|日|周))?)'),
      ];
      for (final pattern in usagePatterns) {
        final match = pattern.firstMatch(fullText);
        if (match != null) {
          medicineUsage = match.group(0)?.trim();
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
        final match = RegExp(r'^[一-龥A-Za-z0-9\s\+\-]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          result = match.group(0)!.trim();
          if (result.length > 100) {
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
        final match = RegExp(r'^[一-龥A-Za-z0-9\s,，、。;；\+\-]+').firstMatch(cleaned);
        if (match != null && match.group(0)!.length >= 2) {
          treatment = match.group(0)!.trim();
          if (treatment.length > 100) {
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
      medicineUsage: medicineUsage,
      result: result,
      treatment: treatment,
      rawText: rawText,
      documentType: docType,
    );
  }

  static void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    _isInitialized = false;
  }
}
