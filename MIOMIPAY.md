# Integrasi MiomiPay

Aplikasi POS ini terintegrasi dengan **MiomiPay Payment Gateway**
(`https://pg.miomidev.com/api/v1`).

| Lingkungan | API key | Uang nyata? |
| --- | --- | --- |
| Sandbox | `MP-SB-...` | Tidak |
| Live | `MP-LIVE-...` | **Ya** |

---

## 1. Kontrak API yang dipakai

Semua request memakai `Accept: application/json`. Endpoint pembuatan transaksi
memerlukan `Authorization: Bearer <API_KEY>`.

### a. Buat transaksi

```http
POST /api/v1/transactions
Authorization: Bearer MP-SB-...
Content-Type: application/json

{
  "external_id": "POS202611210001",
  "amount": 25000,
  "description": "POS · POS202611210001",
  "callback_url": "https://domain-anda.com/miomipay/callback"
}
```

`external_id` = kode pesanan POS. `amount` dalam rupiah (integer).

Respons sukses:

```json
{
  "success": true,
  "data": {
    "reference": "MP-INV-20261120-G14S3B",
    "external_id": "POS202611210001",
    "environment": "sandbox",
    "amount": 25000,
    "final_amount": 25000,
    "status": "PENDING",
    "qr_string": "00020101021226660014ID.CO.GOPAY.WWW...",
    "qr_image_url": "https://pg.miomidev.com/pay/snap_xxx/qr.png",
    "snap_token": "snap_xxx",
    "checkout_url": "https://pg.miomidev.com/pay/snap_xxx",
    "expired_at": "2026-11-20T23:23:24+07:00"
  }
}
```

> **`snap_token`** adalah kunci untuk cek status dan disimpan sebagai
> `paymentReference` pada koleksi `orders`.

Kesalahan validasi mengembalikan `422`:

```json
{
  "message": "The amount field is required.",
  "errors": { "amount": ["The amount field is required."] }
}
```

### b. Cek status (publik, tanpa API key)

```http
GET /api/v1/transactions/{snap_token}/status
```

```json
{
  "success": true,
  "status": "PENDING",
  "is_paid": false,
  "is_expired": false,
  "paid_at": null,
  "environment": "sandbox"
}
```

Nilai `status`: `PENDING` | `PAID` | `EXPIRED`.

### c. Simulasi (khusus sandbox)

```http
POST /api/v1/sandbox/{snap_token}/simulate-pay
POST /api/v1/sandbox/{snap_token}/simulate-expire
```

Tidak ada endpoint pembatalan publik. Pembatalan hanya mengubah status pesanan
di Firestore.

---

## 2. Menjalankan aplikasi

### Sandbox (disarankan untuk demo)

```powershell
powershell -ExecutionPolicy Bypass -File .\run-dev.ps1
```

Atau manual:

```powershell
flutter run -d chrome --dart-define-from-file=dart_defines.sandbox.json
```

`dart_defines.sandbox.json`:

```json
{
  "MIOMIPAY_BASE_URL": "https://pg.miomidev.com/api/v1",
  "MIOMIPAY_API_KEY": "MP-SB-...",
  "MIOMIPAY_SANDBOX": true
}
```

### Live (uang nyata)

1. Salin template:

   ```powershell
   Copy-Item dart_defines.example.json dart_defines.live.json
   ```

2. Isi `MIOMIPAY_API_KEY` dengan kunci `MP-LIVE-...` dan set
   `"MIOMIPAY_SANDBOX": false`.
3. Jalankan:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -Defines dart_defines.live.json
   ```

> ⚠️ **Berkas `dart_defines.*.json` sudah masuk `.gitignore`.** Jangan pernah
> meng-commit API key. Untuk produksi, sebaiknya key disimpan di server/backend
> dan tidak ditanam di aplikasi klien.

### Tanpa internet (mock server)

```powershell
powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -UseMock
```

Mock server meniru kontrak API di atas pada `http://localhost:4000/api/v1`.

---

## 3. Alur di aplikasi

1. Kasir menekan **Proses Pembayaran** → `OrderService.createPendingOrder()`
   menulis dokumen `orders` (`status: pending`).
2. `PaymentScreen._createCharge()` memanggil `createCharge()` dengan
   `external_id = kode pesanan`.
3. QR `qr_string` dirender dengan `qr_flutter`; status di-*poll* tiap **5 detik**
   ke `GET /transactions/{snap_token}/status`.
4. Saat `PAID`:
   - `OrderService.markPaid()` → `status: paid`, `paidAt`, `paymentReference`.
   - Keranjang dikosongkan, struk digital dibuka.
5. Saat `EXPIRED` → tampil layar "Tagihan Kedaluwarsa" dengan opsi membuat
   tagihan baru.
6. Batal → `markCancelled()` di Firestore (tidak ada endpoint cancel di gateway).

### Indikator koneksi

Badge di layar QRIS:

- 🟢 **MiomiPay terhubung** — gateway merespons.
- 🟠 **Mode offline (simulasi lokal)** — gateway tidak dapat dijangkau; aplikasi
  memakai simulasi lokal agar demo tetap berjalan (hanya saat sandbox).

### Tombol simulasi

Tombol **Simulasi Pembayaran Berhasil** hanya muncul saat
`MIOMIPAY_SANDBOX=true`. Tombol ini memanggil endpoint `simulate-pay` sungguhan,
sehingga status di dashboard MiomiPay juga ikut berubah.

---

## 4. Berkas terkait

| Berkas | Peran |
| --- | --- |
| `lib/config.dart` | Base URL, API key, callback URL, flag sandbox |
| `lib/services/miomipay_service.dart` | HTTP client: create, status, simulate |
| `lib/models/miomipay_charge.dart` | Model tagihan + status |
| `lib/screens/payment_screen.dart` | UI QRIS, polling, simulasi |
| `lib/services/auth_service.dart` (`OrderService`) | Simpan status ke Firestore |
| `server/miomipay-mock.js` | Mock server dengan kontrak identik |
| `test/miomipay_service_test.dart` | Unit test kontrak API |

---

## 5. Troubleshooting

| Gejala | Penyebab | Solusi |
| --- | --- | --- |
| `API key MiomiPay belum diisi` | `--dart-define` tidak dipakai | Jalankan dengan `--dart-define-from-file=...` |
| `401 Missing API Key` | Header Authorization tidak terkirim | Pastikan key valid & diawali `MP-SB-`/`MP-LIVE-` |
| `422 external id required` | Body tidak memuat `external_id` | Sudah ditangani otomatis oleh service |
| Badge kuning "Mode offline" | Internet/gateway tidak terjangkau | Cek koneksi; atau pakai `-UseMock` |
| QR tidak terbaca | `qr_string` kosong | Cek respons API di log; parser fallback ke snap token |
| Status tetap PENDING | Belum dibayar | Sandbox: tekan tombol simulasi |
| `404 Transaction not found` | Snap token salah / mock server restart | Buat tagihan baru |

---

## 6. Catatan keamanan

- **Kunci `MP-LIVE-...` bersifat rahasia.** Jika pernah dibagikan (chat, commit,
  screenshot), segera rotasi di dashboard MiomiPay.
- Jangan menaruh key di `lib/config.dart` atau kode sumber.
- Untuk produksi, pertimbangkan backend perantara agar key tidak berada di
  perangkat kasir.
- Verifikasi webhook di backend sebelum menandai pesanan lunas (aplikasi ini
  memakai polling status sebagai sumber kebenaran).
