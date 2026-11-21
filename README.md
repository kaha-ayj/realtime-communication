# POS Sederhana

Aplikasi Point of Sale (POS) berbasis Flutter dengan **Firebase** (Auth + Firestore)
dan **MiomiPay** sebagai payment gateway QRIS.

## Fitur

**Admin**
- Dashboard analitik: pendapatan, jumlah transaksi, menu terlaris
- CRUD menu (nama, kategori, harga, deskripsi, emoji, ketersediaan)
- Riwayat seluruh pesanan dari semua kasir

**Kasir**
- Katalog menu dengan pencarian & filter kategori
- Keranjang belanja dengan kontrol kuantitas
- Checkout dan pembayaran QRIS MiomiPay
- Struk digital (rincian item, total, referensi pembayaran)
- Riwayat pesanan pribadi

## Akun demo

| Role | Email | Password |
| --- | --- | --- |
| Admin | `admin@pos.id` | `Admin123!` |
| Kasir | `kasir@pos.id` | `Kasir123!` |

## Menjalankan

Cara cepat (memakai API MiomiPay sandbox):

```powershell
powershell -ExecutionPolicy Bypass -File .\run-dev.ps1
```

Atau manual:

```powershell
flutter run -d chrome --dart-define-from-file=dart_defines.sandbox.json
```

Tanpa internet (mock server lokal):

```powershell
powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -UseMock
```

Transaksi uang nyata (live):

```powershell
Copy-Item dart_defines.example.json dart_defines.live.json
# isi MIOMIPAY_API_KEY dengan kunci MP-LIVE-... dan set MIOMIPAY_SANDBOX=false
powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -Defines dart_defines.live.json
```

> API key disimpan di `dart_defines.*.json` yang sudah masuk `.gitignore`.
> Jangan pernah meng-commit kunci tersebut.

## Integrasi MiomiPay

Dokumentasi lengkap: **[MIOMIPAY.md](MIOMIPAY.md)**

Ringkasan:
- Gateway: `https://pg.miomidev.com/api/v1`
- Buat tagihan: `POST /transactions` (Bearer API key)
- Cek status: `GET /transactions/{snap_token}/status`
- Simulasi sandbox: `POST /sandbox/{snap_token}/simulate-pay`
- Bila gateway tidak terjangkau dan mode sandbox aktif, aplikasi memakai
  simulasi lokal agar demo tetap berjalan.

## Struktur proyek

```
lib/
  main.dart                  # bootstrap + routing berdasarkan role
  config.dart                # konfigurasi Firebase & MiomiPay
  thema.dart                 # tema Material 3
  models/                    # AppUser, MenuItem, CartItem, PosOrder, MiomiPayCharge
  services/                  # Auth, Menu, Order, MiomiPay
  providers/app_provider.dart# state keranjang & sesi
  screens/                   # login, dashboard, admin, kasir, cart, payment, receipt
  widgets/                   # komponen UI bersama
server/
  miomipay-mock.js           # mock API QRIS (Express)
test/                        # unit test service & util
```

## Kualitas kode

```powershell
flutter analyze   # 0 issues
flutter test      # 10 test lulus
```
