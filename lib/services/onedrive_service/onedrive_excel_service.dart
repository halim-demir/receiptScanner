import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../models/receipt_data.dart';
import 'onedrive_auth_service.dart';

class OneDriveExcelException implements Exception {
  OneDriveExcelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The one column used to decide where the "next empty row" is — matches
/// the exact rule used for the local-file path: only this column's last
/// non-empty value matters, gaps elsewhere in the sheet are ignored.
const _rowAnchorHeader = 'FİŞ NO';

String _normalizeHeader(String raw) => raw.trim().toUpperCase();

/// Converts a zero-based column index to its Excel letter (0->A, 25->Z,
/// 26->AA, ...) — Graph's range addresses use A1-style notation.
String _columnLetter(int index) {
  var n = index + 1;
  var letters = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    letters = String.fromCharCode(65 + rem) + letters;
    n = (n - 1) ~/ 26;
  }
  return letters;
}

/// Writes scanned receipts directly into a live OneDrive/SharePoint Excel
/// workbook via Microsoft Graph — no local device copy, changes are
/// visible immediately to anyone with the file open.
///
/// Requires [OneDriveAuthService] to be configured (see that class's doc
/// for the one-time Azure app registration steps).
class OneDriveExcelService {
  OneDriveExcelService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _graphBase = 'https://graph.microsoft.com/v1.0';

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Resolves a OneDrive/SharePoint sharing URL to its (driveId, itemId)
  /// pair via Graph's `/shares` endpoint. Call this once when the user
  /// pastes their link in Settings.
  Future<OneDriveFileRef> resolveShareLink(String shareUrl, String accessToken) async {
    final encoded = _encodeSharingUrl(shareUrl);
    final uri = Uri.parse('$_graphBase/shares/$encoded/driveItem');
    final response = await _client.get(uri, headers: _authHeaders(accessToken));

    if (response.statusCode != 200) {
      throw OneDriveExcelException(
        'Excel dosyasına ulaşılamadı. Bağlantının doğru ve paylaşım izninin '
        '"düzenleyebilir" olduğundan emin olun. (${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final driveId = json['parentReference']?['driveId'] as String?;
    final itemId = json['id'] as String?;
    if (driveId == null || itemId == null) {
      throw OneDriveExcelException('Dosya bilgisi okunamadı.');
    }
    return OneDriveFileRef(driveId: driveId, itemId: itemId, name: json['name'] as String?);
  }

  /// Base64url-encodes a sharing URL the way Graph's `/shares` API expects:
  /// `"u!" + base64url(url).trimEnd('=')`.
  String _encodeSharingUrl(String url) {
    final base64Value = base64Encode(utf8.encode(url));
    final base64Url = base64Value.replaceAll('/', '_').replaceAll('+', '-').replaceAll('=', '');
    return 'u!$base64Url';
  }

  String _itemPath(OneDriveFileRef ref) => '$_graphBase/drives/${ref.driveId}/items/${ref.itemId}';

  Future<String> _firstWorksheetName(OneDriveFileRef ref, String token) async {
    final uri = Uri.parse('${_itemPath(ref)}/workbook/worksheets');
    final response = await _client.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw OneDriveExcelException('Çalışma sayfaları okunamadı (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sheets = json['value'] as List;
    if (sheets.isEmpty) {
      throw OneDriveExcelException('Excel dosyasında çalışma sayfası bulunamadı.');
    }
    return sheets.first['name'] as String;
  }

  Future<List<String>> _headerRow(OneDriveFileRef ref, String sheet, String token) async {
    final uri = Uri.parse(
      "${_itemPath(ref)}/workbook/worksheets('${Uri.encodeComponent(sheet)}')/range(address='A1:AZ1')",
    );
    final response = await _client.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw OneDriveExcelException('Başlık satırı okunamadı (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final row = (json['values'] as List).first as List;
    return row.map((v) => v?.toString() ?? '').toList();
  }

  Future<int> _usedRowCount(OneDriveFileRef ref, String sheet, String token) async {
    final uri = Uri.parse(
      "${_itemPath(ref)}/workbook/worksheets('${Uri.encodeComponent(sheet)}')/usedRange(valuesOnly=true)",
    );
    final response = await _client.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      // No used range at all (empty sheet) isn't necessarily an error.
      return 1;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rowCount = json['rowCount'] as int?;
    return rowCount ?? 1;
  }

  /// Finds the target row exactly like the local-file path: last non-empty
  /// value in the FİŞ NO column, +1. Ignores gaps anywhere else.
  Future<int> _findTargetRow({
    required OneDriveFileRef ref,
    required String sheet,
    required String token,
    required Map<String, int> columnByHeader,
  }) async {
    final anchorCol = columnByHeader[_normalizeHeader(_rowAnchorHeader)];
    if (anchorCol == null) {
      // No FİŞ NO column found — fall back to right after whatever the
      // sheet already considers used.
      return await _usedRowCount(ref, sheet, token) + 1;
    }

    final lastRow = await _usedRowCount(ref, sheet, token);
    final letter = _columnLetter(anchorCol);
    final uri = Uri.parse(
      "${_itemPath(ref)}/workbook/worksheets('${Uri.encodeComponent(sheet)}')"
      "/range(address='$letter"
      '1:$letter'
      "$lastRow')",
    );
    final response = await _client.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw OneDriveExcelException('FİŞ NO sütunu okunamadı (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final values = json['values'] as List;

    var lastNonEmpty = 0; // row index 0 is the header
    for (var r = 1; r < values.length; r++) {
      final cell = (values[r] as List).isNotEmpty ? values[r][0] : null;
      final text = cell?.toString().trim();
      if (text != null && text.isNotEmpty) {
        lastNonEmpty = r;
      }
    }
    return lastNonEmpty + 1; // convert 0-based row index to 1-based Graph row
  }

  /// Writes one [ReceiptData] into the connected workbook, under the
  /// existing headers, at the row right after the last used FİŞ NO value.
  Future<void> exportReceipt(OneDriveFileRef ref, ReceiptData data, String accessToken) async {
    final sheet = await _firstWorksheetName(ref, accessToken);
    final headerRow = await _headerRow(ref, sheet, accessToken);
    final columnByHeader = <String, int>{
      for (var i = 0; i < headerRow.length; i++)
        if (headerRow[i].trim().isNotEmpty) _normalizeHeader(headerRow[i]): i,
    };

    final targetRow = await _findTargetRow(
      ref: ref,
      sheet: sheet,
      token: accessToken,
      columnByHeader: columnByHeader,
    );

    final rowByHeader = data.toExcelRowByHeader();
    for (final entry in rowByHeader.entries) {
      final col = columnByHeader[_normalizeHeader(entry.key)];
      if (col == null) continue; // header not present in this sheet — skip
      await _writeCell(ref, sheet, col, targetRow, entry.value, accessToken);
    }
  }

  Future<void> _writeCell(
    OneDriveFileRef ref,
    String sheet,
    int col,
    int row1Based,
    String value,
    String token,
  ) async {
    final address = '${_columnLetter(col)}$row1Based';
    final uri = Uri.parse(
      "${_itemPath(ref)}/workbook/worksheets('${Uri.encodeComponent(sheet)}')/range(address='$address')",
    );
    final response = await _client.patch(
      uri,
      headers: _authHeaders(token),
      body: jsonEncode({
        'values': [
          [value]
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw OneDriveExcelException(
        'Hücreye yazılamadı ($address, ${response.statusCode}). Lütfen tekrar deneyin.',
      );
    }
  }

  void dispose() => _client.close();
}

class OneDriveFileRef {
  OneDriveFileRef({required this.driveId, required this.itemId, this.name});
  final String driveId;
  final String itemId;
  final String? name;

  Map<String, String> toJson() => {
        'driveId': driveId,
        'itemId': itemId,
        if (name != null) 'name': name!,
      };

  static OneDriveFileRef fromJson(Map<String, dynamic> json) => OneDriveFileRef(
        driveId: json['driveId'] as String,
        itemId: json['itemId'] as String,
        name: json['name'] as String?,
      );
}
