/// Category suggestion the AI is constrained to choose between, per the
/// exact prompt contract.
enum ReceiptCategory { yemek, diger }

extension ReceiptCategoryX on ReceiptCategory {
  String get label => this == ReceiptCategory.yemek ? 'Yemek' : 'Diğer';

  static ReceiptCategory? fromString(String? raw) {
    switch (raw) {
      case 'Yemek':
        return ReceiptCategory.yemek;
      case 'Diğer':
        return ReceiptCategory.diger;
      default:
        return null;
    }
  }
}

/// Mirrors the exact JSON contract the Gemini prompt is instructed to
/// return. Every field is nullable because the prompt explicitly tells the
/// model to return `null` for unreadable/missing fields — the UI must
/// handle that gracefully rather than assuming complete data.
class ReceiptData {
  ReceiptData({
    this.tarih,
    this.fisNo,
    this.firmaAdi,
    this.matrah,
    this.brut,
    this.kdvTutari,
    this.kategoriOnerisi,
  });

  final String? tarih; // DD.MM.YYYY
  final String? fisNo;
  final String? firmaAdi;
  final double? matrah;
  final double? brut;
  final double? kdvTutari;
  final ReceiptCategory? kategoriOnerisi;

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      tarih: json['tarih'] as String?,
      fisNo: json['fis_no'] as String?,
      firmaAdi: json['firma_adi'] as String?,
      matrah: _asDouble(json['matrah']),
      brut: _asDouble(json['brut']),
      kdvTutari: _asDouble(json['kdv_tutarı'] ?? json['kdv_tutari']),
      kategoriOnerisi: ReceiptCategoryX.fromString(json['kategori_onerisi'] as String?),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  ReceiptData copyWith({
    String? tarih,
    String? fisNo,
    String? firmaAdi,
    double? matrah,
    double? brut,
    double? kdvTutari,
    ReceiptCategory? kategoriOnerisi,
  }) {
    return ReceiptData(
      tarih: tarih ?? this.tarih,
      fisNo: fisNo ?? this.fisNo,
      firmaAdi: firmaAdi ?? this.firmaAdi,
      matrah: matrah ?? this.matrah,
      brut: brut ?? this.brut,
      kdvTutari: kdvTutari ?? this.kdvTutari,
      kategoriOnerisi: kategoriOnerisi ?? this.kategoriOnerisi,
    );
  }

  static ReceiptData empty() => ReceiptData();
}
