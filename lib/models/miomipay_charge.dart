enum MiomiPayStatus {
  pending,
  paid,
  expired,
  failed;

  String get label => switch (this) {
    MiomiPayStatus.pending => 'Menunggu pembayaran',
    MiomiPayStatus.paid => 'Pembayaran berhasil',
    MiomiPayStatus.expired => 'Kedaluwarsa',
    MiomiPayStatus.failed => 'Gagal',
  };

  static MiomiPayStatus fromString(String? value) {
    return switch (value?.toUpperCase()) {
      'PAID' || 'SUCCESS' || 'SUCCEEDED' || 'SETTLED' => MiomiPayStatus.paid,
      'EXPIRED' => MiomiPayStatus.expired,
      'FAILED' || 'FAILURE' || 'CANCELLED' || 'CANCELED' =>
        MiomiPayStatus.failed,
      _ => MiomiPayStatus.pending,
    };
  }
}

class MiomiPayCharge {
  const MiomiPayCharge({
    required this.reference,
    required this.transactionId,
    required this.amount,
    required this.status,
    required this.qrString,
    this.snapToken,
    this.invoiceReference,
    this.qrImageUrl,
    this.checkoutUrl,
    this.expiresAt,
    this.sandbox = true,
    this.offlineSimulation = false,
  });

  /// Referensi transaksi MiomiPay, contoh: `MP-SB-ABC123XYZ` atau
  /// `MP-INV-20261121-ZZLEIY`. Dipakai untuk cek status dan disimpan sebagai
  /// referensi pembayaran pada pesanan.
  final String reference;

  /// Snap token dari gateway. Dipakai untuk simulasi sandbox dan halaman
  /// checkout. Tidak selalu tersedia pada respons API terbaru.
  final String? snapToken;

  /// ID transaksi internal gateway.
  final String transactionId;

  /// Nomor invoice MiomiPay, contoh: `INV-20261107-XXXX`.
  final String? invoiceReference;

  final int amount;
  final MiomiPayStatus status;

  /// Payload QRIS mentah (ISO 18004) yang bisa dirender menjadi QR.
  final String qrString;

  /// URL gambar QR dari gateway.
  final String? qrImageUrl;

  /// Halaman checkout gateway (berguna untuk membuka di browser).
  final String? checkoutUrl;

  final DateTime? expiresAt;

  /// True bila tagihan berasal dari lingkungan sandbox.
  final bool sandbox;

  /// True bila API tidak dapat dihubungi sehingga aplikasi memakai simulasi
  /// lokal agar demo tetap berjalan.
  final bool offlineSimulation;

  bool get isPaid => status == MiomiPayStatus.paid;
  bool get isFinished =>
      status == MiomiPayStatus.paid ||
      status == MiomiPayStatus.expired ||
      status == MiomiPayStatus.failed;

  MiomiPayCharge copyWith({MiomiPayStatus? status}) {
    return MiomiPayCharge(
      reference: reference,
      snapToken: snapToken,
      transactionId: transactionId,
      invoiceReference: invoiceReference,
      amount: amount,
      status: status ?? this.status,
      qrString: qrString,
      qrImageUrl: qrImageUrl,
      checkoutUrl: checkoutUrl,
      expiresAt: expiresAt,
      sandbox: sandbox,
      offlineSimulation: offlineSimulation,
    );
  }
}
