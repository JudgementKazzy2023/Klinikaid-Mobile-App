import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/lab_reference_ranges.dart';

class LabValueExtractionResult {
  final String? panel;
  final Map<String, String> values;
  final int tokensUsed;

  const LabValueExtractionResult({
    required this.panel,
    required this.values,
    this.tokensUsed = 0,
  });

  bool get hasAutofillValues => panel != null && values.isNotEmpty;
}

class LabValueExtractionService {
  SupabaseClient get _client => SupabaseService.client;

  static const String functionName = 'extract-lab-values';
  static final RegExp _numericPattern = RegExp(r'^-?\d+(\.\d+)?$');
  static final RegExp _refusalPattern = RegExp(
    r"\b(i am sorry|i'm sorry|cannot|can't|unable|illegible|unreadable|too blurry|cannot read|can't read)\b",
    caseSensitive: false,
  );

  Future<LabValueExtractionResult> extractFromImagePath(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final response = await _client.functions.invoke(
      functionName,
      body: {
        'image_base64': base64Encode(bytes),
        'mime_type': _mimeTypeForPath(imagePath),
      },
    );

    if (response.status != 200) {
      return const LabValueExtractionResult(panel: null, values: {});
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return sanitizeFunctionResponse(data);
    }
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return sanitizeFunctionResponse(decoded);
      }
    }
    return const LabValueExtractionResult(panel: null, values: {});
  }

  static LabValueExtractionResult sanitizeFunctionResponse(Map<String, dynamic> json) {
    final rawPanel = json['panel'];
    final panel = rawPanel is String && kLabTestGroups.containsKey(rawPanel)
        ? rawPanel
        : null;
    final tokensUsed = (json['tokens_used'] as num?)?.toInt() ?? 0;

    if (panel == null) {
      return LabValueExtractionResult(panel: null, values: const {}, tokensUsed: tokensUsed);
    }

    final rawValues = json['values'];
    if (rawValues is! Map) {
      return LabValueExtractionResult(panel: panel, values: const {}, tokensUsed: tokensUsed);
    }

    final allowedParameters = kLabTestGroups[panel]!.toSet();
    final values = <String, String>{};
    for (final entry in rawValues.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !allowedParameters.contains(key)) continue;
      if (value is! String && value is! num) continue;

      final stringValue = value.toString().trim();
      if (!_numericPattern.hasMatch(stringValue)) continue;
      values[key] = stringValue;
    }

    return LabValueExtractionResult(panel: panel, values: values, tokensUsed: tokensUsed);
  }

  static LabValueExtractionResult sanitizeGeminiText(String text) {
    if (text.trim().isEmpty || _refusalPattern.hasMatch(text)) {
      return const LabValueExtractionResult(panel: null, values: {});
    }

    try {
      final decoded = jsonDecode(_stripMarkdownFences(text));
      if (decoded is Map<String, dynamic>) {
        return sanitizeFunctionResponse(decoded);
      }
    } catch (_) {}
    return const LabValueExtractionResult(panel: null, values: {});
  }

  static String _stripMarkdownFences(String text) {
    return text
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
