import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/receipt_data.dart';
import '../services/ai_service/ai_service.dart';
import '../services/excel_service/excel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/screen_header.dart';

/// Matches Figma node `screen-processing` (56623:7602), wired to the real
/// AI + Excel pipeline. Receives the photos chosen on Camera/Gallery,
/// sends the currently-active one to [AiService] for extraction, lets the
/// user correct any field, then exports to the configured Excel file.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.images});

  final List<XFile> images;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

enum _Status { loading, ready, error }

class _ProcessingScreenState extends State<ProcessingScreen> {
  final _aiService = AiService();
  final _excelService = ExcelService();

  int _activeIndex = 0;
  double _zoom = 1.0;
  _Status _status = _Status.loading;
  String? _errorMessage;
  ReceiptData _data = ReceiptData.empty();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _status = _Status.loading;
      _errorMessage = null;
    });
    try {
      final result = await _aiService.analyzeReceipt([widget.images[_activeIndex]]);
      if (!mounted) return;
      setState(() {
        _data = result;
        _status = _Status.ready;
      });
    } on AiServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _status = _Status.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Beklenmeyen bir hata oluştu.';
        _status = _Status.error;
      });
    }
  }

  void _selectThumbnail(int index) {
    if (index == _activeIndex) return;
    setState(() => _activeIndex = index);
    _analyze();
  }

  /// Trash icon: clears all fields and re-analyzes the currently selected
  /// image, per spec.
  void _clearAndReanalyze() {
    setState(() => _data = ReceiptData.empty());
    _analyze();
  }

  Future<void> _editTextField({
    required String label,
    required String? currentValue,
    required void Function(String value) onSave,
  }) async {
    final controller = TextEditingController(text: currentValue ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _editCategory() async {
    final result = await showDialog<ReceiptCategory>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Kategori Önerisi'),
        children: ReceiptCategory.values
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c),
                  child: Text(c.label),
                ))
            .toList(),
      ),
    );
    if (result != null) {
      setState(() => _data = _data.copyWith(kategoriOnerisi: result));
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      // The running Excel file lives in the app's own sandboxed storage
      // (see ExcelService doc) — always writable, no picker/permission
      // step needed here. Users export/share a copy from Settings.
      await _excelService.exportReceipt(_data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel dosyasına aktarıldı.')),
        );
      }
    } on ExcelServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _aiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgDark,
      child: SafeArea(
        child: Column(
          children: [
            const StatusBarRow(),
            ScreenHeader(
              leftIcon: Icons.arrow_back,
              onLeftTap: () => Navigator.of(context).maybePop(),
              centeredTitle: 'İşlem',
              rightIcon: Icons.more_horiz,
              onRightTap: () {},
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _ViewportArea(
                      file: widget.images[_activeIndex],
                      zoom: _zoom,
                      onZoomIn: () => setState(() => _zoom = (_zoom + 0.2).clamp(1.0, 3.0)),
                      onZoomOut: () => setState(() => _zoom = (_zoom - 0.2).clamp(1.0, 3.0)),
                      onZoomReset: () => setState(() => _zoom = 1.0),
                      showOcrOverlay: _status == _Status.ready,
                    ),
                    if (widget.images.length > 1)
                      _ThumbnailTrack(
                        images: widget.images,
                        active: _activeIndex,
                        onSelect: _selectThumbnail,
                      ),
                    _FormPanel(
                      status: _status,
                      errorMessage: _errorMessage,
                      data: _data,
                      onRetry: _analyze,
                      onEditTarih: () => _editTextField(
                        label: 'Tarih',
                        currentValue: _data.tarih,
                        onSave: (v) => setState(() => _data = _data.copyWith(tarih: v)),
                      ),
                      onEditFisNo: () => _editTextField(
                        label: 'Fiş No',
                        currentValue: _data.fisNo,
                        onSave: (v) => setState(() => _data = _data.copyWith(fisNo: v)),
                      ),
                      onEditFirmaAdi: () => _editTextField(
                        label: 'Firma Adı',
                        currentValue: _data.firmaAdi,
                        onSave: (v) => setState(() => _data = _data.copyWith(firmaAdi: v)),
                      ),
                      onEditMatrah: () => _editTextField(
                        label: 'Matrah',
                        currentValue: _data.matrah?.toStringAsFixed(2),
                        onSave: (v) => setState(
                          () => _data = _data.copyWith(matrah: double.tryParse(v.replaceAll(',', '.'))),
                        ),
                      ),
                      onEditBrut: () => _editTextField(
                        label: 'Brüt',
                        currentValue: _data.brut?.toStringAsFixed(2),
                        onSave: (v) => setState(
                          () => _data = _data.copyWith(brut: double.tryParse(v.replaceAll(',', '.'))),
                        ),
                      ),
                      onEditKdv: () => _editTextField(
                        label: 'KDV Tutarı',
                        currentValue: _data.kdvTutari?.toStringAsFixed(2),
                        onSave: (v) => setState(
                          () => _data = _data.copyWith(kdvTutari: double.tryParse(v.replaceAll(',', '.'))),
                        ),
                      ),
                      onEditKategori: _editCategory,
                    ),
                  ],
                ),
              ),
            ),
            _BottomActionBar(
              onDelete: _clearAndReanalyze,
              onExport: _status == _Status.ready ? _exportExcel : null,
              exporting: _exporting,
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewportArea extends StatelessWidget {
  const _ViewportArea({
    required this.file,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.showOcrOverlay,
  });

  final XFile file;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final bool showOcrOverlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 280,
              height: 190,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Transform.scale(
                      scale: zoom,
                      child: Image.file(File(file.path), fit: BoxFit.cover),
                    ),
                  ),
                  if (showOcrOverlay) ...const [
                    Positioned(left: 38, top: 58, child: _OcrHighlight(width: 130, height: 20)),
                    Positioned(left: 148, top: 108, child: _OcrHighlight(width: 80, height: 20)),
                  ],
                ],
              ),
            ),
            _ZoomControls(
              onZoomIn: onZoomIn,
              onZoomOut: onZoomOut,
              onZoomReset: onZoomReset,
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrHighlight extends StatelessWidget {
  const _OcrHighlight({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.25),
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          _ZoomIconButton(icon: Icons.add, onTap: onZoomIn),
          const SizedBox(height: 8),
          _ZoomIconButton(icon: Icons.refresh, onTap: onZoomReset),
          const SizedBox(height: 8),
          _ZoomIconButton(icon: Icons.remove, onTap: onZoomOut),
        ],
      ),
    );
  }
}

class _ZoomIconButton extends StatelessWidget {
  const _ZoomIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.iconChipBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _ThumbnailTrack extends StatelessWidget {
  const _ThumbnailTrack({required this.images, required this.active, required this.onSelect});
  final List<XFile> images;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(images.length, (i) {
            final isActive = i == active;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: Opacity(
                  opacity: isActive ? 1 : 0.5,
                  child: Container(
                    width: 44,
                    height: 44,
                    padding: EdgeInsets.all(isActive ? 0 : 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive ? AppColors.primary : AppColors.borderSofter,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(images[i].path), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.status,
    required this.errorMessage,
    required this.data,
    required this.onRetry,
    required this.onEditTarih,
    required this.onEditFisNo,
    required this.onEditFirmaAdi,
    required this.onEditMatrah,
    required this.onEditBrut,
    required this.onEditKdv,
    required this.onEditKategori,
  });

  final _Status status;
  final String? errorMessage;
  final ReceiptData data;
  final VoidCallback onRetry;
  final VoidCallback onEditTarih;
  final VoidCallback onEditFisNo;
  final VoidCallback onEditFirmaAdi;
  final VoidCallback onEditMatrah;
  final VoidCallback onEditBrut;
  final VoidCallback onEditKdv;
  final VoidCallback onEditKategori;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.panelWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Çıktı Kontrolü', style: AppText.formPanelTitle),
                if (status == _Status.ready)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('AI Analizi Tamam', style: AppText.accuracyPill),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (status == _Status.loading) const _LoadingRows(),
          if (status == _Status.error) _ErrorState(message: errorMessage, onRetry: onRetry),
          if (status == _Status.ready) ...[
            _FieldRow(label: 'Tarih', value: data.tarih, onEdit: onEditTarih),
            const SizedBox(height: 10),
            _FieldRow(label: 'Fiş No', value: data.fisNo, onEdit: onEditFisNo),
            const SizedBox(height: 10),
            _FieldRow(label: 'Firma Adı', value: data.firmaAdi, onEdit: onEditFirmaAdi),
            const SizedBox(height: 10),
            _FieldRow(
              label: 'Matrah',
              value: data.matrah != null ? '${data.matrah!.toStringAsFixed(2)} ₺' : null,
              onEdit: onEditMatrah,
            ),
            const SizedBox(height: 10),
            _FieldRow(
              label: 'Brüt',
              value: data.brut != null ? '${data.brut!.toStringAsFixed(2)} ₺' : null,
              onEdit: onEditBrut,
            ),
            const SizedBox(height: 10),
            _FieldRow(
              label: 'KDV Tutarı',
              value: data.kdvTutari != null ? '${data.kdvTutari!.toStringAsFixed(2)} ₺' : null,
              onEdit: onEditKdv,
            ),
            const SizedBox(height: 10),
            _FieldRow(label: 'Kategori Önerisi', value: data.kategoriOnerisi?.label, onEdit: onEditKategori),
          ],
        ],
      ),
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 41,
              decoration: BoxDecoration(
                color: AppColors.rowBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.rowBorder),
              ),
            ),
          ),
        const SizedBox(height: 4),
        const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
            SizedBox(width: 10),
            Text('Fiş analiz ediliyor...', style: TextStyle(color: AppColors.panelLabel)),
          ],
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message ?? 'Analiz sırasında bir hata oluştu.',
          style: const TextStyle(color: AppColors.danger, fontSize: 13),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value, required this.onEdit});
  final String label;
  final String? value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.rowBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.rowBorder),
      ),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: AppText.fieldLabel)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : '—',
              style: AppText.fieldValue.copyWith(
                color: value?.isNotEmpty == true ? AppColors.panelTextDark : AppColors.panelLabel,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onEdit,
            child: const Icon(Icons.edit_outlined, size: 16, color: AppColors.panelLabel),
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.onDelete, required this.onExport, required this.exporting});
  final VoidCallback onDelete;
  final VoidCallback? onExport;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.panelWhite,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.rowBorder)),
            ),
            child: Row(
              children: [
                Material(
                  color: AppColors.dangerBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.dangerBgBorder),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onDelete,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Opacity(
                    opacity: onExport == null ? 0.5 : 1,
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onExport,
                        child: SizedBox(
                          height: 48,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (exporting)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              else
                                const Icon(Icons.insert_drive_file_outlined, size: 20, color: Colors.white),
                              const SizedBox(width: 8),
                              Text("Excel'e Aktar", style: AppText.exportButton),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const HomeIndicator(dark: true),
        ],
      ),
    );
  }
}
