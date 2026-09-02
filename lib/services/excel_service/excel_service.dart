import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/receipt_data.dart';
import '../storage/secure_storage_service.dart';

class ExcelServiceException implements Exception {
  ExcelServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Used only when creating a brand-new file (nothing imported yet) — an
/// imported file's real headers are always read and used as-is instead.
const _defaultHeaderOrder = [
  'TARİH',
  'FİŞ NO',
  'FİRMA ADI',
  'MATRAH',
  'BRÜT',
  '%20 KDV',
  '%10 KDV',
  '%1 KDV',
  'MASRAFI YAPAN',
];

/// The one column used to decide where the "next empty row" is — per
/// explicit product decision, gaps elsewhere in the sheet are ignored;
/// only this column's last non-empty value matters.
const _rowAnchorHeader = 'FİŞ NO';

/// Input for the background isolate that writes one row.
class _WriteJob {
  _WriteJob(this.existingBytes, this.rowByHeader);
  final Uint8List? existingBytes;
  final Map<String, String> rowByHeader;
}

String _normalizeHeader(String raw) => raw.trim().toUpperCase();

/// Runs entirely on a background isolate via [compute].
///
/// Column placement is by HEADER NAME, not fixed position — read row 0,
/// build a name→column-index map, and place each field under its matching
/// header. Any header in [rowByHeader] that isn't found in the sheet is
/// simply skipped (never crashes, never invents a column).
///
/// Row placement: scan the [_rowAnchorHeader] ("FİŞ NO") column from the
/// top, remember the LAST row with a non-empty value there, and write the
/// new row immediately below it — ignoring blank rows anywhere else in
/// the sheet. This matches the exact behavior described by the user
/// (e.g. rows 1–15 filled, 16–18 blank, 19 filled → new row goes to 20,
/// not into the 16–18 gap).
Uint8List _writeRowIsolate(_WriteJob job) {
  final excel = job.existingBytes != null && job.existingBytes!.isNotEmpty
      ? Excel.decodeBytes(job.existingBytes!)
      : Excel.createExcel();

  final sheetName = excel.tables.isNotEmpty ? excel.tables.keys.first : 'Fişler';
  final sheet = excel[sheetName];

  // Ensure a header row exists. A totally empty sheet gets our own
  // default headers; anything else is left exactly as the user has it.
  if (sheet.maxRows == 0) {
    sheet.appendRow(_defaultHeaderOrder.map((h) => TextCellValue(h)).toList());
  }

  // Build header-name -> column-index map from row 0, as it actually is.
  final rows = sheet.rows;
  final headerRow = rows.isNotEmpty ? rows.first : const <Data?>[];
  final columnByHeader = <String, int>{};
  for (var col = 0; col < headerRow.length; col++) {
    final text = headerRow[col]?.value?.toString();
    if (text != null && text.trim().isNotEmpty) {
      columnByHeader[_normalizeHeader(text)] = col;
    }
  }

  // Find the target row via the FİŞ NO column specifically.
  final anchorCol = columnByHeader[_normalizeHeader(_rowAnchorHeader)];
  int targetRow = 1; // default: right after the header row
  if (anchorCol != null) {
    var lastNonEmpty = 0; // row 0 is the header
    for (var r = 1; r < sheet.maxRows; r++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: anchorCol, rowIndex: r));
      final text = cell.value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        lastNonEmpty = r;
      }
    }
    targetRow = lastNonEmpty + 1;
  } else {
    // No FİŞ NO column found at all (shouldn't normally happen) — fall
    // back to appending after whatever the sheet already considers used.
    targetRow = sheet.maxRows;
  }

  // Write each field under its matching header; silently skip anything
  // whose header isn't present in this sheet.
  job.rowByHeader.forEach((header, value) {
    final col = columnByHeader[_normalizeHeader(header)];
    if (col == null) return;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: targetRow))
        .value = TextCellValue(value);
  });

  final bytes = excel.encode();
  if (bytes == null) {
    throw ExcelServiceException('Excel dosyası oluşturulamadı.');
  }
  return Uint8List.fromList(bytes);
}

/// Manages the running Excel file that every scanned receipt is written
/// into, matching the user's real spreadsheet's own header layout exactly
/// (see `_writeRowIsolate` doc for the column/row-placement rules).
///
/// Platform limitation (see git history for the full writeup): mobile OSes
/// don't allow a persistent, repeatedly-writable handle to an arbitrary
/// external file without native platform code — every dedicated Flutter
/// package for this is either unmaintained or broken on current Flutter.
/// So: the user's file is imported once into an in-app working copy
/// (headers preserved exactly), every scan writes into that copy, and
/// `saveExtraCopy()` lets them push the result back over the original
/// file whenever they choose.
class ExcelService {
  Future<File> _targetFile() async {
    final path = await SecureStorageService.instance.getExcelPath();
    if (path == null) {
      // Professional default: Use the user-visible "Documents" folder.
      // On iOS, this is "On My iPhone > receiptscanner".
      // On Android, this is the app's primary documents folder.
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/fisler.xlsx');
      
      // Auto-save this as the target if nothing is selected yet.
      await SecureStorageService.instance.saveExcelPath(file.path);
      return file;
    }
    return File(path);
  }

  Future<String> localFilePath() async {
    final path = await SecureStorageService.instance.getExcelPath();
    if (path == null) {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/fisler.xlsx';
    }
    return path;
  }

  Future<bool> hasTargetFile() async {
    final path = await SecureStorageService.instance.getExcelPath();
    if (path == null) return false;
    return File(path).exists();
  }

  /// Lets the user pick their existing .xlsx. The selected file's path
  /// is stored persistently and used directly for future scans.
  Future<bool> selectTargetFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'İşlem yapılacak Excel dosyasını seç',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    final picked = result?.files.single;
    if (picked?.path == null) return false;

    // Direct path usage as requested ("var olan dosyaya yazılsın")
    await SecureStorageService.instance.saveExcelPath(picked!.path!);
    return true;
  }

  /// Writes one [ReceiptData] directly into the selected Excel file.
  Future<String> exportReceipt(ReceiptData data) async {
    final file = await _targetFile();
    
    // Check if file still exists at the selected path
    if (!await file.exists()) {
      throw ExcelServiceException('Seçili dosya yerinde bulunamadı. Lütfen Ayarlar\'dan tekrar seçin.');
    }

    final existingBytes = await file.readAsBytes();
    final job = _WriteJob(existingBytes, data.toExcelRowByHeader());
    final newBytes = await compute(_writeRowIsolate, job);
    
    // Direct write to the selected path.
    await file.writeAsBytes(newBytes, flush: true);
    return file.path;
  }

  /// Creates a copy of the current file at a new location.
  Future<String?> saveAs() async {
    final file = await _targetFile();
    if (!await file.exists()) {
      throw ExcelServiceException('Dosya bulunamadı.');
    }
    final bytes = await file.readAsBytes();

    return FilePicker.platform.saveFile(
      dialogTitle: 'Excel dosyasını farklı kaydet',
      fileName: 'fisler_yedek.xlsx',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
  }
}
