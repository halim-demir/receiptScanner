import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../models/receipt_data.dart';
import '../storage/secure_storage_service.dart';

/// Runs on a background isolate via [compute] — base64-encoding a multi-MB
/// photo is CPU-bound and was previously done synchronously on the main
/// isolate, contributing to skipped frames (flagged in code review).
String _base64EncodeIsolate(Uint8List bytes) => base64Encode(bytes);

class AiServiceException implements Exception {
  AiServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to Google AI Studio (Gemini) to extract structured data from a
/// photographed Turkish receipt.
///
/// Security:
/// - The API key is read from [SecureStorageService] only — never
///   hardcoded, never logged.
/// - All calls go over HTTPS to `generativelanguage.googleapis.com`.
/// - The exact prompt below constrains the model to return ONLY the JSON
///   contract described in the app spec; the response is still validated
///   defensively (see [_extractJson]) since model output is untrusted
///   input and must never be `eval`'d or trusted blindly.
class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // NOTE (updated again — model lifecycle churn is real and ongoing):
  // gemini-2.0-flash was retired by Google in 2026 → caused live 404s.
  // gemini-2.5-flash was the next fix, but Google has since shipped the
  // 3.x line. gemini-3.5-flash-lite is now GA (per Google's official
  // Gemini API changelog) and is explicitly positioned for exactly this
  // app's workload: high-volume, low-latency, structured-extraction
  // subagent tasks — cheaper and faster than full 3.5/3.6 Flash for a
  // job that doesn't need deep reasoning.
  // If this model is retired too, the fix is always the same single
  // constant swap (or point it at the `gemini-flash-latest` alias, which
  // always resolves to the current default Flash model — trading away a
  // pinned, predictable model version for immunity to this exact class
  // of breakage).
  static const String _model = 'gemini-3.5-flash-lite';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static const String _prompt =
      """Bu görsellerdeki Türkçe finansal harcama fişini analiz et. Fiş üzerindeki bilgileri ayıkla ve YALNIZCA aşağıdaki JSON formatında yanıt ver:

{ "tarih": "DD.MM.YYYY", "fis_no": "string", "firma_adi": "string", "matrah": 0.00, "brut": 0.00, "kdv_tutarı": 0.00, "kategori_onerisi": "Yemek" | "Diğer" }

Okunamayan veya bulunamayan alanlar için null değeri döndür. Sayısal değerlerde nokta kullan.""";

  /// Analyzes one or more receipt images (e.g. front/back, or a multi-page
  /// receipt) and returns the merged structured result.
  Future<ReceiptData> analyzeReceipt(List<XFile> images) async {
    if (images.isEmpty) {
      throw AiServiceException('Analiz için en az bir fotoğraf gereklidir.');
    }

    final apiKey = await SecureStorageService.instance.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw AiServiceException(
        'Google AI Studio API anahtarı ayarlanmamış. Lütfen Ayarlar > API Anahtarı bölümünden ekleyin.',
      );
    }

    final imageParts = await Future.wait(images.map(_toInlineDataPart));

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _prompt},
            ...imageParts,
          ],
        },
      ],
      'generationConfig': {
        // `temperature`/`top_p`/`top_k` are deprecated as of the Gemini 3.x
        // line — replaced by `thinkingConfig.thinkingLevel`. This is a
        // structured-extraction task (no open-ended reasoning needed), so
        // LOW keeps it fast and cheap rather than defaulting to the
        // model's (more expensive) dynamic thinking behavior.
        'thinkingConfig': {'thinkingLevel': 'LOW'},
        'responseMimeType': 'application/json',
      },
    });

    final uri = Uri.parse('$_baseUrl?key=$apiKey');

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw AiServiceException('İnternet bağlantısı bulunamadı.');
    } catch (_) {
      throw AiServiceException('Sunucuya bağlanırken bir hata oluştu.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AiServiceException('API anahtarı geçersiz veya yetkisiz.');
    }
    if (response.statusCode == 429) {
      throw AiServiceException('İstek limiti aşıldı. Lütfen daha sonra tekrar deneyin.');
    }
    if (response.statusCode == 404) {
      // Almost always means the model id in `_model` no longer exists
      // (Google periodically retires model versions — this is exactly
      // what happened with gemini-2.0-flash in 2026). Not an API-key or
      // network problem. The model id is included here on purpose — it's
      // not a secret, and it lets you confirm from the on-screen error
      // alone whether the RUNNING app binary actually has the model
      // string you think it has (a stale build showing an old model id
      // here means: full rebuild needed, not a server-side problem).
      throw AiServiceException(
        'Kullanılan yapay zeka modeli ("$_model") bulunamadı ya da artık desteklenmiyor. '
        '(Bu model doğrudan test edildiğinde çalışıyorsa, uygulamanın eski bir '
        'sürümle derlenmiş olma ihtimali yüksek — flutter clean sonrası yeniden derleyin.)',
      );
    }
    if (response.statusCode != 200) {
      // Never surface raw server internals to the user — log minimally,
      // return a generic message.
      throw AiServiceException('Analiz sırasında bir hata oluştu (${response.statusCode}).');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final text = _extractModelText(decoded);
    final jsonMap = _extractJson(text);
    return ReceiptData.fromJson(jsonMap);
  }

  Future<Map<String, dynamic>> _toInlineDataPart(XFile file) async {
    final bytes = await file.readAsBytes();
    final base64Data = await compute(_base64EncodeIsolate, bytes);
    final mimeType = _mimeTypeFor(file.path);
    return {
      'inlineData': {
        'mimeType': mimeType,
        'data': base64Data,
      },
    };
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _extractModelText(Map<String, dynamic> decoded) {
    try {
      final candidates = decoded['candidates'] as List;
      final content = candidates.first['content'] as Map<String, dynamic>;
      final parts = content['parts'] as List;
      return parts.first['text'] as String;
    } catch (_) {
      throw AiServiceException('Yapay zeka yanıtı okunamadı.');
    }
  }

  /// Defensively pulls a JSON object out of the model's text response.
  /// Even with `responseMimeType: application/json` set, we don't blindly
  /// trust the model — we still guard against stray markdown fences or
  /// leading/trailing text before decoding.
  Map<String, dynamic> _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      throw AiServiceException('Fiş verisi ayrıştırılamadı.');
    }
    final jsonSlice = text.substring(start, end + 1);
    try {
      return jsonDecode(jsonSlice) as Map<String, dynamic>;
    } catch (_) {
      throw AiServiceException('Fiş verisi ayrıştırılamadı.');
    }
  }

  void dispose() => _client.close();
}
