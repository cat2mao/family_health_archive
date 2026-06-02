import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_service.dart';

/// AI-powered OCR enhancement service
/// Uses OpenAI-compatible API to analyze raw OCR text and extract structured data
class AiOcrService {
  static const String _prefApiKey = 'ai_api_key';
  static const String _prefApiEndpoint = 'ai_api_endpoint';
  static const String _prefApiModel = 'ai_api_model';
  static const String _prefEnabled = 'ai_ocr_enabled';

  /// Check if AI OCR is configured and enabled
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefEnabled) ?? false;
    final apiKey = prefs.getString(_prefApiKey) ?? '';
    return enabled && apiKey.isNotEmpty;
  }

  /// Get current API configuration
  static Future<Map<String, String>> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiKey': prefs.getString(_prefApiKey) ?? '',
      'endpoint': prefs.getString(_prefApiEndpoint) ?? 'https://api.openai.com/v1',
      'model': prefs.getString(_prefApiModel) ?? 'gpt-4o-mini',
      'enabled': (prefs.getBool(_prefEnabled) ?? false).toString(),
    };
  }

  /// Save API configuration
  static Future<void> saveConfig({
    required String apiKey,
    required String endpoint,
    required String model,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, apiKey);
    await prefs.setString(_prefApiEndpoint, endpoint);
    await prefs.setString(_prefApiModel, model);
    await prefs.setBool(_prefEnabled, enabled);
  }

  /// Use AI to analyze OCR raw text and extract structured medical information
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
            {
              'role': 'system',
              'content': '''你是一个医疗文档OCR结果分析助手。请从OCR识别的原始文本中提取结构化信息。
返回JSON格式，包含以下字段（如果没有识别到则为null）：
- hospital: 医院名称
- diagnosis: 诊断结果（优先识别门诊诊断、初步诊断等字段）
- doctorName: 医生姓名
- symptoms: 症状/主诉/病史描述
- cost: 费用金额（仅从发票/收据中提取阿拉伯数字金额，不要提取大写金额）
- date: 就诊日期
- medicineName: 药品名称
- result: 检查/检验结果
- treatment: 处置/处理方案
- documentType: 文档类型（medicalRecord/invoice/prescription/labReport/unknown）

只返回JSON，不要其他文字。'''
            },
            {
              'role': 'user',
              'content': '请分析以下OCR识别文本并提取医疗信息：\n\n$rawText',
            },
          ],
          'temperature': 0.1,
          'max_tokens': 1000,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        if (content == null) return null;

        // Parse JSON from response (handle markdown code blocks)
        String jsonStr = content.trim();
        if (jsonStr.startsWith('```')) {
          jsonStr = jsonStr.replaceFirst(RegExp(r'^```\w*\n?'), '').replaceFirst(RegExp(r'\n?```$'), '');
        }

        final extracted = jsonDecode(jsonStr) as Map<String, dynamic>;

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
      } else {
        debugPrint('AI API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('AI OCR analysis failed: $e');
      return null;
    }
  }
}
