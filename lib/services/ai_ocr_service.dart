import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_service.dart';

/// AI-powered OCR enhancement service
/// Uses OpenAI-compatible API to analyze raw OCR text (and optionally images)
/// to extract structured medical data
class AiOcrService {
  static const String _prefApiKey = 'ai_api_key';
  static const String _prefApiEndpoint = 'ai_api_endpoint';
  static const String _prefApiModel = 'ai_api_model';
  static const String _prefVisionModel = 'ai_vision_model';
  static const String _prefVisionEnabled = 'ai_vision_enabled';
  static const String _prefEnabled = 'ai_ocr_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefEnabled) ?? false;
    final apiKey = prefs.getString(_prefApiKey) ?? '';
    return enabled && apiKey.isNotEmpty;
  }

  static Future<bool> isVisionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefVisionEnabled) ?? false;
  }

  static Future<Map<String, String>> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiKey': prefs.getString(_prefApiKey) ?? '',
      'endpoint': prefs.getString(_prefApiEndpoint) ?? 'https://api.openai.com/v1',
      'model': prefs.getString(_prefApiModel) ?? 'gpt-4o-mini',
      'visionModel': prefs.getString(_prefVisionModel) ?? 'gpt-4o',
      'visionEnabled': (prefs.getBool(_prefVisionEnabled) ?? false).toString(),
      'enabled': (prefs.getBool(_prefEnabled) ?? false).toString(),
    };
  }

  static Future<void> saveConfig({
    required String apiKey,
    required String endpoint,
    required String model,
    required String visionModel,
    required bool enabled,
    required bool visionEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, apiKey);
    await prefs.setString(_prefApiEndpoint, endpoint);
    await prefs.setString(_prefApiModel, model);
    await prefs.setString(_prefVisionModel, visionModel);
    await prefs.setBool(_prefEnabled, enabled);
    await prefs.setBool(_prefVisionEnabled, visionEnabled);
  }

  static String get _systemPrompt => '''你是一个专业的医疗文档分析助手。请从以下OCR文本中提取结构化医疗信息。

重要规则：
1. 纠正OCR识别错误：修复断字、合并跨行文本、修正形近字（如"曰期"→"日期"）
2. 优先提取明确的诊断字段（门诊诊断 > 初步诊断 > 诊断）
3. 费用：仅从发票/收据中提取阿拉伯数字金额，优先"实付"/"合计"对应的金额
4. 日期：统一为YYYY-MM-DD格式
5. 药品：提取处方中的药品通用名，忽略剂型说明

返回纯JSON（不要markdown代码块），格式如下：
{"hospital": "医院名称或null", "diagnosis": "诊断或null", "doctorName": "医生姓名或null", "symptoms": "症状/主诉或null", "cost": "金额数字或null", "date": "日期或null", "medicineName": "药品名或null", "result": "检查结果或null", "treatment": "处置方案或null", "documentType": "medicalRecord/invoice/prescription/labReport/unknown"}''';

  /// Analyze OCR raw text with AI (text-only mode)
  static Future<OcrExtractedData?> analyzeWithAi(String rawText) async {
    if (!await isEnabled()) return null;

    final config = await getConfig();
    final apiKey = config['apiKey']!;
    final endpoint = config['endpoint']!;
    final model = config['model']!;

    try {
      final url = Uri.parse('$endpoint/chat/completions');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': '请分析以下OCR识别文本并提取医疗信息：\n\n$rawText'},
          ],
          'temperature': 0.1,
          'max_tokens': 1000,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return _parseResponse(response.body, rawText);
      } else {
        debugPrint('AI API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('AI OCR text analysis failed: $e');
      return null;
    }
  }

  /// Analyze image directly using a vision-capable model
  static Future<OcrExtractedData?> analyzeImageWithVision(String imagePath) async {
    if (!await isEnabled()) return null;
    if (!await isVisionEnabled()) return null;

    final config = await getConfig();
    final apiKey = config['apiKey']!;
    final endpoint = config['endpoint']!;
    final visionModel = config['visionModel']!;

    try {
      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);
      final ext = p.extension(imagePath).toLowerCase().replaceAll('.', '');
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      final url = Uri.parse('$endpoint/chat/completions');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': visionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,$base64Image',
                    'detail': 'high',
                  },
                },
                {
                  'type': 'text',
                  'text': '''$_systemPrompt

请直接对这张图片进行OCR识别，提取其中的医疗信息。注意：
- 仔细识别图片中的所有文字，包括表格中的内容
- 如果图片是发票/收据，重点关注金额信息
- 如果图片是病历，重点关注诊断、症状、处置信息
- 如果图片是处方，重点关注药品名称和用法
- 如果图片是检验报告，重点关注检查项目和结果

只返回JSON，不要其他文字。''',
                },
              ],
            },
          ],
          'temperature': 0.1,
          'max_tokens': 1500,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return _parseResponse(response.body, null);
      } else {
        debugPrint('Vision API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('AI vision analysis failed: $e');
      return null;
    }
  }

  /// Parse AI response with JSON repair retry
  static OcrExtractedData? _parseResponse(String responseBody, String? rawText) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      // Try to parse JSON, with repair attempts
      String jsonStr = content.trim();

      // Remove markdown code blocks
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr
            .replaceFirst(RegExp(r'^```\w*\n?'), '')
            .replaceFirst(RegExp(r'\n?```$'), '');
        jsonStr = jsonStr.trim();
      }

      // Try direct parse first
      try {
        return _buildFromJson(jsonDecode(jsonStr) as Map<String, dynamic>, rawText);
      } catch (_) {
        // Attempt JSON repair
        jsonStr = _repairJson(jsonStr);
        return _buildFromJson(jsonDecode(jsonStr) as Map<String, dynamic>, rawText);
      }
    } catch (e) {
      debugPrint('AI OCR JSON parse failed: $e');
      return null;
    }
  }

  /// Attempt to repair common JSON format issues from LLM output
  static String _repairJson(String jsonStr) {
    // Remove trailing commas before closing brackets
    jsonStr = jsonStr.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    // Fix unquoted keys (simple cases)
    // Fix single quotes to double quotes
    jsonStr = jsonStr.replaceAll("'", '"');
    // Remove any text before { and after }
    final start = jsonStr.indexOf('{');
    final end = jsonStr.lastIndexOf('}');
    if (start >= 0 && end > start) {
      jsonStr = jsonStr.substring(start, end + 1);
    }
    return jsonStr;
  }

  static OcrExtractedData _buildFromJson(Map<String, dynamic> extracted, String? rawText) {
    OcrDocumentType docType = OcrDocumentType.unknown;
    final dtStr = extracted['documentType'] as String?;
    if (dtStr == 'medicalRecord') docType = OcrDocumentType.medicalRecord;
    else if (dtStr == 'invoice') docType = OcrDocumentType.invoice;
    else if (dtStr == 'prescription') docType = OcrDocumentType.prescription;
    else if (dtStr == 'labReport') docType = OcrDocumentType.labReport;

    return OcrExtractedData(
      hospital: extracted['hospital'] as String?,
      diagnosis: extracted['diagnosis'] as String?,
      doctorName: extracted['doctorName'] as String?,
      symptoms: extracted['symptoms'] as String?,
      cost: extracted['cost']?.toString(),
      date: extracted['date'] as String?,
      medicineName: extracted['medicineName'] as String?,
      result: extracted['result'] as String?,
      treatment: extracted['treatment'] as String?,
      rawText: rawText,
      documentType: docType,
    );
  }
}
