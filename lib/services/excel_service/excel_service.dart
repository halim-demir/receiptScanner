import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/receipt_data.dart';

class ExcelServiceException implements Exception {
  ExcelServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _sheetName = 'Fişler';
const _headers = [
  'Tarih',
  'Fiş No',
  'Firma Adı',
  'Matrah',
  'Brüt',
  'KDV Tutarı',
  'Kategori Önerisi',
  'Eklenme Zamanı',
];

/// Fixed input for the isolate that appends one receipt row.
class _AppendJob {
  _AppendJob(this.existingBytes, this.row);
  final Uint8List? existingBytes;
  final List<String?> row; // pre-formatted strings, cell-type-agnostic
}

/// Runs entirely on a background isolate via [compute]: decodes the
/// existing workbook (if any), appends one row, re-encodes. Keeping this
/// as a single top-level/static function (not a closure) is required for
/// `compute()`.
Uint8List _appendRowIsolate(_AppendJob job) {
  final excel = job.existingBytes != null
      ? Excel.decodeBytes(job.existingBytes!)
      : Excel.createExcel();

  if (!excel.sheets.containsKey(_sheetName)) {
    final sheet = excel[_sheetName];
    sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
    // `Excel.createExcel()` ships with a default 'Sheet1' — drop it once
    // our named sheet exists so the file stays tidy.
    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }
  }

  final sheet = excel[_sheetName];
  sheet.appendRow([
    TextCellValue(job.row[0] ?? ''),
    TextCellValue(job.row[1] ?? ''),
    TextCellValue(job.row[2] ?? ''),
    DoubleCellValue(double.tryParse(job.row[3] ?? '') ?? 0),
    DoubleCellValue(double.tryParse(job.row[4] ?? '') ?? 0),
    DoubleCellValue(double.tryParse(job.row[5] ?? '') ?? 0),
    TextCellValue(job.row[6] ?? ''),
    TextCellValue(job.row[7] ?? ''),
  ]);

  final bytes = excel.encode();
  if (bytes == null) {
    throw ExcelServiceException('Excel dosyası oluşturulamadı.');
  }
  return Uint8List.fromList(bytes);
}

/// Appends analyzed receipts to a single running .xlsx file.
///
/// Architecture (revised after code review — see chat for the original
/// bug): the *canonical* file that every export appends to lives in the
/// app's own sandboxed documents directory (`path_provider`), which is
/// always a real, directly-writable filesystem path — no permissions, no
/// Storage Access Framework, no scoped-storage edge cases.
///
/// `file_picker`'s `saveFile()` is only used for the explicit, one-shot
/// "export/share a copy" action, where the current bytes are handed to it
/// directly (required on Android/iOS — `saveFile()` cannot return a
/// writable path on mobile without `bytes`, and any path it *does* return
/// isn't guaranteed to be a `dart:io`-usable filesystem path for later
/// re-opening).
class ExcelService {
  Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/fisler.xlsx');
  }

  /// Where the running Excel file lives on this device (for display in
  /// Settings only — not something the user needs to manage).
  Future<String> localFilePath() async => (await _localFile()).path;

  /// Appends one [ReceiptData] row to the local running Excel file,
  /// creating it (with a header row) on first use. Decoding/encoding runs
  /// on a background isolate via [compute] so it never blocks the UI
  /// thread — important since this file only grows over the app's
  /// lifetime.
  Future<String> exportReceipt(ReceiptData data) async {
    final file = await _localFile();
    final existingBytes = await file.exists() ? await file.readAsBytes() : null;

    final job = _AppendJob(existingBytes, [
      data.tarih,
      data.fisNo,
      data.firmaAdi,
      data.matrah?.toString(),
      data.brut?.toString(),
      data.kdvTutari?.toString(),
      data.kategoriOnerisi?.label,
      DateTime.now().toIso8601String(),
    ]);

    final newBytes = await compute(_appendRowIsolate, job);
    await file.writeAsBytes(newBytes, flush: true);
    return file.path;
  }

  /// Lets the user save/share a copy of the current running Excel file to
  /// wherever they choose (Drive, Files app, email, etc). This is a
  /// single-shot write — `bytes` is provided directly, which is required
  /// for `saveFile()` to work at all on Android/iOS (see class doc).
  /// Returns the destination path chosen by the user, or `null` if they
  /// cancelled.
  Future<String?> exportCopyToUserLocation() async {
    final file = await _localFile();
    if (!await file.exists()) {
      throw ExcelServiceException('Henüz dışa aktarılacak bir fiş kaydı yok.');
    }
    final bytes = await file.readAsBytes();

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Excel kopyasını kaydet',
      fileName: 'fisler.xlsx',
      bytes: bytes, // required on Android/iOS — see class doc
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    return path;
  }
}
