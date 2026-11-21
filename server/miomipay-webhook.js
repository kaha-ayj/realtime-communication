/**
 * Penerima webhook MiomiPay.
 *
 * Memverifikasi header `X-MiomiPay-Signature` (HMAC-SHA256 hex dari raw body)
 * memakai `MIOMIPAY_WEBHOOK_SECRET`, lalu mencatat event pembayaran.
 *
 * Jalankan:
 *   cd server && npm run webhook
 *
 * Daftarkan URL publik (mis. lewat ngrok):
 *   https://domain-anda.com/miomipay/webhook
 *
 * Konfigurasi tersedia melalui environment variable atau berkas server/.env:
 *   MIOMIPAY_WEBHOOK_SECRET=whsec_...
 *   WEBHOOK_PORT=4100
 */

const crypto = require('crypto');
const express = require('express');
const loadDotEnv = require('./load-env');

loadDotEnv();

const app = express();
const PORT = Number(process.env.WEBHOOK_PORT || 4100);
const SECRET = String(process.env.MIOMIPAY_WEBHOOK_SECRET || '').trim();

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'miomipay-webhook',
    secret_configured: SECRET.length > 0,
    time: new Date().toISOString(),
  });
});

app.post(
  '/miomipay/webhook',
  express.raw({ type: '*/*', limit: '1mb' }),
  (req, res) => {
    const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from('');

    if (!SECRET) {
      console.error('[WEBHOOK] MIOMIPAY_WEBHOOK_SECRET belum diisi.');
      return res.status(500).json({
        success: false,
        message: 'Webhook secret belum dikonfigurasi di server.',
      });
    }

    const incoming = String(req.get('X-MiomiPay-Signature') || '').trim();
    if (!incoming) {
      return res.status(401).json({
        success: false,
        message: 'Missing X-MiomiPay-Signature header.',
      });
    }

    const expected = crypto
      .createHmac('sha256', SECRET)
      .update(raw)
      .digest('hex');

    if (!safeEqual(expected, incoming.toLowerCase())) {
      console.warn(
        `[WEBHOOK] Signature tidak valid dari ${
          req.ip || 'unknown'
        } untuk event ${req.get('X-MiomiPay-Event') || '-'}`
      );
      return res.status(401).json({
        success: false,
        message: 'Invalid signature.',
      });
    }

    let event;
    try {
      event = JSON.parse(raw.toString('utf8'));
    } catch (_) {
      return res.status(400).json({
        success: false,
        message: 'Payload bukan JSON yang valid.',
      });
    }

    const eventName = req.get('X-MiomiPay-Event') || event.event || '-';
    const reference = event?.data?.reference;
    const status = event?.data?.status;

    console.log(
      `[WEBHOOK] ${eventName}  reference=${reference || '-'}  status=${
        status || '-'
      }`
    );

    // Di sini Anda dapat memperbarui pesanan di backend/Firestore.
    // Aplikasi POS memakai polling status sebagai sumber kebenaran, jadi
    // handler ini cukup memverifikasi signature dan mengembalikan 2xx.

    return res.status(200).json({ received: true });
  }
);

function safeEqual(expected, incoming) {
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(incoming, 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

app.listen(PORT, () => {
  console.log('');
  console.log('  MiomiPay Webhook Receiver');
  console.log(`  http://localhost:${PORT}/miomipay/webhook`);
  console.log(
    `  secret : ${SECRET ? '(terisi)' : '(BELUM DIISI — endpoint menolak event)'}`
  );
  console.log('');
});
