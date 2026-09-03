/// Mirrors the real spreadsheet's exact column set (order given by the
/// user): TARİH, FİŞ NO, FİRMA ADI, MATRAH, BRÜT, %20, %10, %1, YEMEK,
/// DİĞER, MASRAFI YAPAN.
///
/// - tarih/fisNo/firmaAdi/matrah/brut: extracted by the AI from the photo.
/// - kdv20/kdv10/kdv1: the AI extracts a single VAT rate + amount from the
///   receipt; whichever rate matches gets the amount, the other two stay
///   null. All three remain independently editable on screen regardless.
/// - yemek/diger: NOT written automatically — per product decision, these
///   are purely user-controlled fields on the Processing screen. The AI's
///   category suggestion is used only to pre-fill one of them (with the
///   brüt amount) as a convenience starting point; whatever ends up in
///   the field when exporting is what gets written to Excel.
/// - masrafiYapan ("who made the expense"): can never be read from a
///   receipt photo — always starts empty and is filled in manually on the
///   Processing screen.
class ReceiptData {
  ReceiptData({
    this.tarih,
    this.fisNo,
    this.firmaAdi,
    this.matrah,
    this.brut,
    this.kdv20,
    this.kdv10,
    this.kdv1,
    this.yemek,
    this.diger,
    this.masrafiYapan,
  });

  final String? tarih; // DD.MM.YYYY
  final String? fisNo;
  final String? firmaAdi;
  final double? matrah;
  final double? brut;
  final double? kdv20;
  final double? kdv10;
  final double? kdv1;
  final double? yemek;
  final double? diger;
  final String? masrafiYapan;

  /// Builds a [ReceiptData] from the AI service's raw JSON contract (see
  /// AiService._prompt) — this is a distinct step from the Excel column
  /// mapping above; the AI never returns yemek/diger/masrafiYapan
  /// directly, those are derived/entered separately.
  factory ReceiptData.fromAiJson(Map<String, dynamic> json) {
    final rate = _asDouble(json['kdv_orani'])?.round();
    final vatAmount = _asDouble(json['kdv_tutari']);
    final category = ReceiptCategoryX.fromString(json['kategori_onerisi'] as String?);
    final brut = _asDouble(json['brut']);

    return ReceiptData(
      tarih: json['tarih'] as String?,
      fisNo: json['fis_no'] as String?,
      firmaAdi: json['firma_adi'] as String?,
      matrah: _asDouble(json['matrah']),
      brut: brut,
      kdv20: rate == 20 ? vatAmount : null,
      kdv10: rate == 10 ? vatAmount : null,
      kdv1: rate == 1 ? vatAmount : null,
      // Convenience pre-fill only — both fields stay user-editable and
      // whatever value is on screen at export time is what's used.
      yemek: category == ReceiptCategory.yemek ? brut : null,
      diger: category == ReceiptCategory.diger ? brut : null,
      masrafiYapan: null,
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  /// Sentinel distinguishing "field not passed" from "field explicitly
  /// cleared to null" — plain `value ?? this.value` copyWith can't tell
  /// these apart, which would silently ignore a user clearing a field
  /// (e.g. blanking out "%20 KDV" because it doesn't apply) and keep the
  /// old value instead. Every field below must support being cleared.
  static const _unset = Object();

  ReceiptData copyWith({
    Object? tarih = _unset,
    Object? fisNo = _unset,
    Object? firmaAdi = _unset,
    Object? matrah = _unset,
    Object? brut = _unset,
    Object? kdv20 = _unset,
    Object? kdv10 = _unset,
    Object? kdv1 = _unset,
    Object? yemek = _unset,
    Object? diger = _unset,
    Object? masrafiYapan = _unset,
  }) {
    return ReceiptData(
      tarih: identical(tarih, _unset) ? this.tarih : tarih as String?,
      fisNo: identical(fisNo, _unset) ? this.fisNo : fisNo as String?,
      firmaAdi: identical(firmaAdi, _unset) ? this.firmaAdi : firmaAdi as String?,
      matrah: identical(matrah, _unset) ? this.matrah : matrah as double?,
      brut: identical(brut, _unset) ? this.brut : brut as double?,
      kdv20: identical(kdv20, _unset) ? this.kdv20 : kdv20 as double?,
      kdv10: identical(kdv10, _unset) ? this.kdv10 : kdv10 as double?,
      kdv1: identical(kdv1, _unset) ? this.kdv1 : kdv1 as double?,
      yemek: identical(yemek, _unset) ? this.yemek : yemek as double?,
      diger: identical(diger, _unset) ? this.diger : diger as double?,
      masrafiYapan: identical(masrafiYapan, _unset) ? this.masrafiYapan : masrafiYapan as String?,
    );
  }

  /// Maps this record onto the real spreadsheet's exact header names, for
  /// [ExcelService] to place by column lookup (not fixed position — see
  /// ExcelService doc). Numbers are formatted as plain decimal strings;
  /// null/empty fields are simply omitted (left blank).
  Map<String, String> toExcelRowByHeader() {
    String? num(double? v) => v == null ? null : v.toStringAsFixed(2);
    final map = <String, String?>{
      'TARİH': tarih,
      'FİŞ NO': fisNo,
      'FİRMA ADI': firmaAdi,
      'MATRAH': num(matrah),
      'BRÜT': num(brut),
      '%20': num(kdv20),
      '%10': num(kdv10),
      '%1': num(kdv1),
      'YEMEK': num(yemek),
      'DİĞER': num(diger),
      'MASRAFI YAPAN': masrafiYapan,
    };
    map.removeWhere((key, value) => value == null || value.isEmpty);
    // removeWhere doesn't change the map's static type (still
    // Map<String, String?>) even though every remaining value is
    // guaranteed non-null at this point — cast explicitly so this
    // actually returns Map<String, String> as declared.
    return map.cast<String, String>();
  }

  static ReceiptData empty() => ReceiptData();
}

/// Only used to decide which of YEMEK/DİĞER gets the initial pre-fill —
/// not written to Excel directly (see class doc above).
enum ReceiptCategory { yemek, diger }

extension ReceiptCategoryX on ReceiptCategory {
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
