import 'package:flutter/material.dart';
import '../services/excel_service/excel_service.dart';
import '../services/onedrive_service/onedrive_auth_service.dart';
import '../services/onedrive_service/onedrive_excel_service.dart';
import '../services/onedrive_service/onedrive_file_ref_store.dart';
import '../services/storage/secure_storage_service.dart';
import '../theme/app_theme.dart';

/// The side menu opened from the gear icon on Camera/Gallery headers.
/// Holds:
///  - Google AI Studio API key entry (stored via [SecureStorageService])
///  - Excel connection: EITHER a live OneDrive/SharePoint workbook
///    (preferred when connected — writes go straight into the real file
///    via Microsoft Graph, see OneDriveExcelService) OR a local file
///    picked once and kept as an in-app working copy (see ExcelService
///    doc for why that one can't auto-sync back to the original).
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  final _apiKeyController = TextEditingController();
  final _shareLinkController = TextEditingController();
  final _excelService = ExcelService();
  final _oneDriveRefStore = OneDriveFileRefStore();
  bool _obscureKey = true;
  bool _hasSavedKey = false;
  String? _excelPath;
  bool _hasWorkingFile = false;
  bool _exportingCopy = false;
  bool _importing = false;
  bool _loading = true;
  OneDriveFileRef? _oneDriveRef;
  bool _connectingOneDrive = false;
  String? _oneDriveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasKey = await SecureStorageService.instance.hasApiKey();
    final hasFile = await _excelService.hasWorkingFile();
    final path = await _excelService.localFilePath();
    final oneDriveRef = await _oneDriveRefStore.load();
    if (!mounted) return;
    setState(() {
      _hasSavedKey = hasKey;
      _excelPath = path;
      _hasWorkingFile = hasFile;
      _oneDriveRef = oneDriveRef;
      _loading = false;
    });
  }

  Future<void> _saveApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) return;
    await SecureStorageService.instance.saveApiKey(value);
    _apiKeyController.clear();
    if (!mounted) return;
    setState(() => _hasSavedKey = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API anahtarı güvenli şekilde kaydedildi.')),
    );
  }

  Future<void> _clearApiKey() async {
    await SecureStorageService.instance.clearApiKey();
    if (!mounted) return;
    setState(() => _hasSavedKey = false);
  }

  Future<void> _importFile() async {
    setState(() => _importing = true);
    try {
      final imported = await _excelService.importExistingFile();
      if (!mounted) return;
      if (imported) {
        final path = await _excelService.localFilePath();
        setState(() {
          _hasWorkingFile = true;
          _excelPath = path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel dosyası içe aktarıldı. Yeni fişler mevcut başlıkların altına eklenecek.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _connectOneDrive() async {
    final link = _shareLinkController.text.trim();
    if (link.isEmpty) return;

    setState(() {
      _connectingOneDrive = true;
      _oneDriveError = null;
    });
    try {
      final token = await OneDriveAuthService.instance.signInInteractive();
      final ref = await OneDriveExcelService().resolveShareLink(link, token);
      await _oneDriveRefStore.save(ref);
      if (!mounted) return;
      setState(() {
        _oneDriveRef = ref;
        _shareLinkController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OneDrive dosyasına bağlanıldı. Fişler artık doğrudan bu dosyaya yazılacak.')),
      );
    } on OneDriveAuthException catch (e) {
      if (mounted) setState(() => _oneDriveError = e.message);
    } on OneDriveExcelException catch (e) {
      if (mounted) setState(() => _oneDriveError = e.message);
    } catch (_) {
      if (mounted) setState(() => _oneDriveError = 'Bağlanırken beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _connectingOneDrive = false);
    }
  }

  Future<void> _disconnectOneDrive() async {
    await _oneDriveRefStore.clear();
    try {
      await OneDriveAuthService.instance.signOut();
    } catch (_) {
      // Not fatal — the local reference is already cleared either way.
    }
    if (mounted) setState(() => _oneDriveRef = null);
  }

  Future<void> _exportCopy() async {
    setState(() => _exportingCopy = true);
    try {
      final path = await _excelService.saveExtraCopy();
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kopya kaydedildi.')),
        );
      }
    } on ExcelServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _exportingCopy = false);
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _shareLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.bgDark,
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Ayarlar',
                      style: AppText.processingTitle.copyWith(fontSize: 22)),
                  const SizedBox(height: 24),

                  _SectionLabel('Google AI Studio API Anahtarı'),
                  const SizedBox(height: 8),
                  if (_hasSavedKey)
                    _SavedKeyCard(onClear: _clearApiKey)
                  else
                    _ApiKeyForm(
                      controller: _apiKeyController,
                      obscure: _obscureKey,
                      onToggleObscure: () => setState(() => _obscureKey = !_obscureKey),
                      onSave: _saveApiKey,
                    ),
                  const SizedBox(height: 28),

                  _SectionLabel('Excel Dosyası'),
                  const SizedBox(height: 8),
                  if (_oneDriveRef != null) ...[
                    _DestinationTile(
                      title: 'OneDrive — bağlı (${_oneDriveRef!.name ?? 'Excel dosyası'})',
                      subtitle: 'Fişler doğrudan bu dosyaya, gerçek zamanlı yazılıyor',
                      icon: Icons.cloud_done_outlined,
                      selected: true,
                      onTap: null,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _disconnectOneDrive,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Bağlantıyı Kaldır'),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ] else ...[
                    Text(
                      'OneDrive / SharePoint\'teki gerçek Excel dosyanıza doğrudan yazmak için '
                      'düzenleme izinli bir paylaşım bağlantısı yapıştırın ve Microsoft '
                      'hesabınızla giriş yapın.',
                      style: AppText.navLabelInactive.copyWith(fontSize: 11.5, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _shareLinkController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'https://1drv.ms/... veya SharePoint bağlantısı',
                        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_oneDriveError != null) ...[
                      const SizedBox(height: 8),
                      Text(_oneDriveError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _connectingOneDrive ? null : _connectOneDrive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _connectingOneDrive
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.cloud_outlined, size: 18),
                        label: const Text('Microsoft ile Bağlan'),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  _SectionLabel(_oneDriveRef != null ? 'Yerel Yedek Dosya' : 'Yerel Dosya (OneDrive Bağlı Değilse)'),
                  const SizedBox(height: 8),
                  _DestinationTile(
                    title: _hasWorkingFile
                        ? 'Dosya bağlı — yeni fişler başlıkların altına ekleniyor'
                        : 'Henüz dosya seçilmedi',
                    subtitle: _excelPath ?? '',
                    icon: Icons.description_outlined,
                    selected: _hasWorkingFile,
                    onTap: null,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _importing ? null : _importFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.folder_open, size: 18),
                      label: Text(_hasWorkingFile ? 'Farklı Dosya Seç' : 'Mevcut Excel Dosyasını Seç'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Seçtiğiniz dosyanın başlık satırı olduğu gibi kopyalanır; taranan '
                    'her fiş bu başlıkların altına eklenir. Mobil işletim sistemleri bir '
                    'uygulamanın dış bir dosyaya kalıcı olarak otomatik yazmasına izin '
                    'vermediği için değişiklikler önce uygulama içinde tutulur — "Excel '
                    'Dosyasını Kaydet" ile istediğiniz an orijinal dosyanın üzerine yazıp '
                    'güncelleyebilirsiniz.',
                    style: AppText.navLabelInactive.copyWith(fontSize: 11.5, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _exportingCopy || !_hasWorkingFile ? null : _exportCopy,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: _exportingCopy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share, size: 18),
                      label: const Text('Excel Dosyasını Kaydet'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DestinationTile(
                    title: 'Google Drive',
                    subtitle: 'Yakında kullanılabilir olacak',
                    icon: Icons.cloud_outlined,
                    selected: false,
                    enabled: false,
                    onTap: null,
                  ),
                  const SizedBox(height: 28),

                  _SectionLabel('Gizlilik'),
                  const SizedBox(height: 8),
                  Text(
                    'API anahtarınız cihazınızda şifrelenerek saklanır ve yalnızca '
                    'Google AI Studio ile iletişim için kullanılır. Fiş görselleri '
                    'yalnızca analiz sırasında HTTPS üzerinden gönderilir, sunucuda '
                    'saklanmaz.',
                    style: AppText.navLabelInactive.copyWith(height: 1.5, fontSize: 12.5),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppText.fieldLabel.copyWith(color: AppColors.textMuted, letterSpacing: 0.5),
    );
  }
}

class _ApiKeyForm extends StatelessWidget {
  const _ApiKeyForm({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'AIza...',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textMuted, size: 18),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Kaydet'),
          ),
        ),
      ],
    );
  }
}

class _SavedKeyCard extends StatelessWidget {
  const _SavedKeyCard({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('API anahtarı kayıtlı', style: TextStyle(color: Colors.white)),
          ),
          TextButton(onPressed: onClear, child: const Text('Kaldır')),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppText.navLabelInactive.copyWith(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check, color: AppColors.primary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
