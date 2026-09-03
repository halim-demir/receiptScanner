import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'onedrive_excel_service.dart';

/// Persists the resolved (driveId, itemId) pair from [OneDriveExcelService]
/// so the user only has to paste their sharing link once. Not sensitive —
/// these IDs are meaningless without a valid signed-in Microsoft account's
/// access token, which is never stored (see [OneDriveAuthService] —
/// msal_auth manages its own token cache securely on the native side).
class OneDriveFileRefStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/onedrive_file_ref.json');
  }

  Future<OneDriveFileRef?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return OneDriveFileRef.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(OneDriveFileRef ref) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(ref.toJson()), flush: true);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
