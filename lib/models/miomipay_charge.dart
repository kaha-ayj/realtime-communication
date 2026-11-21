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
    return switch (value?.toLowerCase()) {
      'paid' || 'success' || 'succeeded' || 'settled' => MiomiPayStatus.paid,
      'expired' => MiomiPayStatus.expired,
      'failed' || 'failure' || 'cancelled' || 'canceled' => MiomiPayStatus.failed,
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
    this.expiresAt,
    this.sandbox = true,
    this.offlineSimulation = false,
  });

  final String reference;
  final String transactionId;
  final int amount;
  final MiomiPayStatus status;
  final String qrString;
  final DateTime? expiresAt;

  /// True bila respons berasal dari API/mock server MiomiPay.
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
      transactionId: transactionId,
      amount: amount,
      status: status ?? this.status,
      qrString: qrString,
      expiresAt: expiresAt,
      sandbox: sandbox,
      offlineSimulation: offlineSimulation,
    );
  }
}
