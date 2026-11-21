# Integrasi MiomiPay

Aplikasi POS ini terintegrasi dengan **MiomiPay Payment Gateway**
(`https://pg.miomidev.com/api/v1`) untuk pembayaran QRIS.

| Lingkungan | API key | Uang nyata? |
| --- | --- | --- |
| Sandbox | `MP-SB-...` | Tidak |
| Live | `MP-LIVE-...` | **Ya** |

---

## 1. Autentikasi

Setiap request ke API MiomiPay menyertakan Bearer Token:

```http
Authorization: Bearer MP-SB-...
Content-Type: application/json
Accept: application/json
```

API key dibaca dari `--dart-define` / `--dart-define-from-file` (lihat
`dart_defines.sandbox.json`). **Jangan** menaruh key di kode sumber.

---

## 2. Kontrak API yang dipakai

### a. Buat tagihan QRIS

```http
POST /api/v1/payment/create
Authorization: Bearer MP-SB-...
Content-Type: application/json

{
  "external_id": "POS202611210001",
  "amount": 25000,
  "customer_name": "Budi Santoso",
  "customer_email": "budi@example.com",
  "customer_phone": "081234567890",
  "description": "POS · POS202611210001",
  "success_redirect_url": "https://aplikasikamu.com/pembayaran/sukses"
}
```

`external_id` = kode pesanan POS. `amount` dalam rupiah (integer).
`customer_*` dan `success_redirect_url` bersifat opsional.

Respons sukses (`201 Created`) berisi objek `data`:

```json
{
  "success": true,
  "message": "Payment created successfully",
  "data": {
    "reference": "MP-SB-ABC123XYZ",
    "invoice_number": "INV-20261107-XXXX",
    "external_id": "POS202611210001",
    "amount": 25000,
    "unique_amount": 25000,
    "payable_amount": 25000,
    "environment": "sandbox",
    "payment_method": "qris",
    "status": "PENDING",
    "checkout_url": "https://pg.miomidev.com/pay/snap_xxx",
    "qr_image_url": "https://pg.miomidev.com/pay/snap_xxx/qr.png",
    "qr_string": "00020101021226660014ID.CO.GOPAY.WWW...",
    "created_at": "2026-11-07T06:00:00Z",
    "expires_at": "2026-11-07T06:15:00Z"
  }
}
```

> Respons sandbox saat ini juga mengirim `snap_token` dan memakai nama field
> `final_amount` / `expired_at`. Service sudah menangani kedua bentuk tersebut.
> `snap_token` diperlukan untuk simulasi sandbox.

### b. Cek status transaksi

```http
GET /api/v1/payment/{reference}/status
Authorization: Bearer MP-SB-...
Accept: application/json
```

`reference` adalah `reference` dari respons pembuatan tagihan
(contoh `MP-SB-ABC123XYZ` atau `MP-INV-20261121-ZZLEIY`).

Contoh respons:

```json
{
  "success": true,
  "data": {
    "reference": "MP-SB-ABC123XYZ",
    "status": "PAID",
    "paid_at": "2026-11-21T23:10:28+07:00",
    "environment": "sandbox"
  }
}
```

Nilai `status`: `PENDING` | `PAID` | `EXPIRED`. Service juga membaca
`is_paid` / `is_expired` bila tersedia.

### c. Simulasi (khusus sandbox)

```http
POST /api/v1/sandbox/{snap_token}/simulate-pay
POST /api/v1/sandbox/{snap_token}/simulate-expire
Authorization: Bearer MP-SB-...
```

Tidak ada endpoint pembatalan publik. Pembatalan hanya mengubah status pesanan
di Firestore.

---

## 3. Webhook & signature HMAC

Saat transaksi berubah menjadi `PAID` atau `EXPIRED`, MiomiPay mengirim
`POST` ke URL webhook yang didaftarkan di dashboard proyek:

```http
POST /miomipay/webhook
Content-Type: application/json
X-MiomiPay-Event: payment.success
X-MiomiPay-Signature: 7f9a2e34b...   # HMAC-SHA256 hex dari raw body
```

Signature dihitung dari **raw request body** memakai webhook secret:

```text
signature = HMAC-SHA256(raw_body, MIOMIPAY_WEBHOOK_SECRET)
```

Contoh payload:

```json
{
  "event": "payment.success",
  "data": {
    "reference": "MP-SB-ABC123XYZ",
    "external_id": "POS202611210001",
    "status": "PAID",
    "amount": 25000,
    "paid_at": "2026-11-21T23:10:28+07:00"
  }
}
```

### Penerima webhook lokal

```powershell
cd server
npm run webhook
```

Endpoint: `http://localhost:4100/miomipay/webhook`

Secret dan port dibaca dari `server/.env` (sudah masuk `.gitignore`):

```dotenv
MIOMIPAY_WEBHOOK_SECRET=whsec_...
WEBHOOK_PORT=4100
```

Handler akan:

1. Mengambil raw body (bukan JSON yang sudah di-*parse*).
2. Menghitung HMAC-SHA256 dengan secret.
3. Membandingkan memakai `crypto.timingSafeEqual`.
4. Menolak `401` bila signature tidak valid.
5. Mengembalikan `{ "received": true }` bila valid.

Aplikasi POS tetap memakai **polling status** sebagai sumber kebenaran.
Webhook berguna untuk backend yang ingin langsung memperbarui pesanan.

### Menguji signature secara manual

```powershell
$secret = "whsec_..."
$body = '{"event":"payment.success","data":{"reference":"TEST","status":"PAID"}}'
$sig = (New-Object System.Security.Cryptography.HMACSHA256(
  [Text.Encoding]::UTF8.GetBytes($secret)
)).ComputeHash([Text.Encoding]::UTF8.GetBytes($body)) |
  ForEach-Object { $_.ToString("x2") } | Join-String

Invoke-WebRequest -Uri "http://localhost:4100/miomipay/webhook" `
  -Method Post `
  -ContentType "application/json" `
  -Headers @{ "X-MiomiPay-Event" = "payment.success"; "X-MiomiPay-Signature" = $sig } `
  -Body $body
```

---

## 4. Menjalankan aplikasi

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

Tambahkan `MIOMIPAY_SUCCESS_REDIRECT_URL` bila memakai halaman checkout.

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

### Tanpa internet (mock server + webhook)

```powershell
powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -UseMock
```

Mock server meniru kontrak API di atas pada `http://localhost:4000/api/v1`,
termasuk mengirim webhook bertanda tangan ke receiver lokal di port 4100.

---

## 5. Alur di aplikasi

1. Kasir menekan **Proses Pembayaran** → `OrderService.createPendingOrder()`
   menulis dokumen `orders` (`status: pending`).
2. `PaymentScreen._createCharge()` memanggil `createCharge()` dengan
   `external_id = kode pesanan`.
3. Respons `reference` disimpan sebagai `paymentReference`; QR `qr_string`
   dirender dengan `qr_flutter`.
4. Status di-*poll* tiap **5 detik** ke
   `GET /payment/{reference}/status`. Semua request memakai Bearer token.
5. Saat `PAID`:
   - `OrderService.markPaid()` → `status: paid`, `paidAt`, `paymentReference`.
   - Keranjang dikosongkan, struk digital dibuka.
6. Saat `EXPIRED` → tampil layar "Tagihan Kedaluwarsa" dengan opsi membuat
   tagihan baru.
7. Batal → `markCancelled()` di Firestore (tidak ada endpoint cancel).

### Indikator koneksi

Badge di layar QRIS:

- 🟢 **MiomiPay terhubung** — gateway merespons.
- 🟠 **Mode offline (simulasi lokal)** — gateway tidak dapat dijangkau; aplikasi
  memakai simulasi lokal agar demo tetap berjalan (hanya saat sandbox).

### Tombol simulasi

Tombol **Simulasi Pembayaran Berhasil** hanya muncul saat
`MIOMIPAY_SANDBOX=true`. Tombol ini memanggil `simulate-pay` dengan
`snap_token` dari gateway, sehingga status di dashboard MiomiPay juga berubah.

---

## 6. Berkas terkait

| Berkas | Peran |
| --- | --- |
| `lib/config.dart` | Base URL, API key, success redirect, flag sandbox |
| `lib/services/miomipay_service.dart` | HTTP client: create, status, simulate |
| `lib/models/miomipay_charge.dart` | Model tagihan + status |
| `lib/screens/payment_screen.dart` | UI QRIS, polling, simulasi |
| `lib/services/auth_service.dart` (`OrderService`) | Simpan status ke Firestore |
| `server/miomipay-mock.js` | Mock server dengan kontrak identik |
| `server/miomipay-webhook.js` | Penerima webhook + verifikasi HMAC |
| `server/.env` | Secret webhook lokal (**gitignored**) |
| `test/miomipay_service_test.dart` | Unit test kontrak API |

---

## 7. Troubleshooting

| Gejala | Penyebab | Solusi |
| --- | --- | --- |
| `API key MiomiPay belum diisi` | `--dart-define` tidak dipakai | Jalankan dengan `--dart-define-from-file=...` |
| `401 Missing API Key` | Header Authorization tidak terkirim | Pastikan key valid & diawali `MP-SB-`/`MP-LIVE-` |
| `422 The amount field is required` | Body tidak memuat `amount` | Sudah ditangani otomatis oleh service |
| `404 Transaksi tidak ditemukan` | Reference salah / tagihan dibuat di server lain | Buat tagihan baru |
| Badge kuning "Mode offline" | Internet/gateway tidak terjangkau | Cek koneksi; atau pakai `-UseMock` |
| QR tidak terbaca | `qr_string` kosong | Cek respons API di log; parser fallback ke reference |
| Status tetap PENDING | Belum dibayar | Sandbox: tekan tombol simulasi |
| Webhook `401 Invalid signature` | Secret berbeda / body diubah sebelum verifikasi | Samakan `MIOMIPAY_WEBHOOK_SECRET`; verifikasi raw body |
| Webhook tidak terkirim dari mock | `MIOMIPAY_WEBHOOK_URL` kosong | Isi di `server/.env` lalu restart mock |

---

## 8. Catatan keamanan

- **Kunci `MP-LIVE-...` bersifat rahasia.** Jika pernah dibagikan (chat, commit,
  screenshot), segera rotasi di dashboard MiomiPay.
- Webhook secret juga rahasia. Simpan di `server/.env` (gitignored) atau secret
  manager, jangan di kode sumber.
- Jangan menaruh key di `lib/config.dart`.
- Untuk produksi, pertimbangkan backend perantara agar key tidak berada di
  perangkat kasir.
- Verifikasi signature webhook sebelum menandai pesanan lunas. Aplikasi ini
  memakai polling status sebagai sumber kebenaran, sehingga webhook bersifat
  pelengkap.
