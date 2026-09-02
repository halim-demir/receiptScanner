import 'dart:io';

import 'package:flutter/material.dart';
import '../services/excel_service/excel_service.dart';
import '../services/permission_service.dart';
import '../services/storage/secure_storage_service.dart';
import '../theme/app_theme.dart';

/// The side menu opened from the gear icon on Camera/Gallery headers.
/// Holds:
///  - Google AI Studio API key entry (stored via [SecureStorageService])
///  - Excel file connection: the user picks their own existing .xlsx once
///    (its headers are preserved); every scan is appended to an in-app
///    working copy, which the user explicitly saves back over the
///    original file whenever they want (see ExcelService doc for why
///    silent, always-on writes to an arbitrary external file aren't
///    reliably possible on mobile right now).
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  final _apiKeyController = TextEditingController();
  final _excelService = ExcelService();
  bool _obscureKey = true;
  bool _hasSavedKey = false;
  String? _excelPath;
  bool _hasTargetFile = false;
  bool _exportingCopy = false;
  bool _importing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasKey = await SecureStorageService.instance.hasApiKey();
    final hasFile = await _excelService.hasTargetFile();
    final path = await _excelService.localFilePath();
    if (!mounted) return;
    setState(() {
      _hasSavedKey = hasKey;
      _excelPath = path;
      _hasTargetFile = hasFile;
      _loading = false;
    });
  }

  String _formatDisplayPath(String path) {
    if (Platform.isIOS && path.contains('/Documents/')) {
      final fileName = path.split('/').last;
      return 'Dosyalar > receiptscanner > $fileName';
    }
    return path;
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
    final permission = await PermissionService.ensureStoragePermission();
    if (permission != PermissionState.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(permission == PermissionState.permanentlyDenied
                ? 'Dosya seçmek için depolama izni gerekiyor. Ayarlardan izin verebilirsiniz.'
                : 'Depolama izni reddedildi.'),
            action: permission == PermissionState.permanentlyDenied
                ? SnackBarAction(label: 'Ayarlar', onPressed: PermissionService.openSettings)
                : null,
          ),
        );
      }
      return;
    }

    setState(() => _importing = true);
    try {
      final selected = await _excelService.selectTargetFile();
      if (!mounted) return;
      if (selected) {
        final path = await _excelService.localFilePath();
        setState(() {
          _hasTargetFile = true;
          _excelPath = path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel dosyası başarıyla seçildi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportCopy() async {
    setState(() => _exportingCopy = true);
    try {
      final path = await _excelService.saveAs();
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dosya farklı kaydedildi: $path')),
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
                  _DestinationTile(
                    title: 'Excel Dosya Yolu',
                    subtitle: _excelPath != null ? _formatDisplayPath(_excelPath!) : 'Henüz dosya seçilmedi',
                    icon: Icons.folder_open,
                    selected: _hasTargetFile,
                    onTap: _importing ? null : _importFile,
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.info_outline,
                    text: Platform.isIOS
                        ? 'iOS Güvenlik Kısıtlaması: Apple, uygulamaların dış klasörlerdeki (İndirilenler gibi) dosyalara doğrudan ve sessizce yazmasına izin vermez. \n\n"Dosyalar > iPhone\'umda > receiptscanner" klasörü uygulamanın tam yetkili alanıdır. Orijinal dosyanızı buraya taşıyıp oradan seçerseniz, tüm işlemleriniz anında ve doğrudan o dosya üzerine kaydedilir.'
                        : 'Android 11+ Bilgi: Cihazınızdaki "İndirilenler" veya diğer sistem klasörlerindeki dosyalara doğrudan yazabilmek için "Tüm dosyalara erişim" izni gereklidir. Bu izin verildiğinde, seçtiğiniz orijinal dosya anında güncellenir.',
                  ),
                  const SizedBox(height: 16),
                  if (_hasTargetFile) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _exportingCopy ? null : _exportCopy,
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
                        label: const Text('Excel Dosyasını Farklı Kaydet'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Taranan fişler Ayarlar\'dan seçtiğiniz orijinal dosyaya doğrudan eklenir. Gerektiğinde dosyanın bir yedeğini yukarıdaki butonu kullanarak alabilirsiniz.',
                      style: AppText.navLabelInactive.copyWith(fontSize: 11.5, height: 1.4),
                    ),
                  ],
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppText.navLabelInactive.copyWith(
                fontSize: 12,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ),
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
