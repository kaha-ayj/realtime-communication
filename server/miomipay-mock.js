/**
 * MiomiPay Mock Server
 *
 * Meniru kontrak API MiomiPay (https://pg.miomidev.com/api/v1) sehingga
 * aplikasi dapat dijalankan tanpa internet:
 *
 *   GET  /health
 *   POST /api/v1/transactions                      (Bearer API key)
 *   GET  /api/v1/transactions/:snap/status         (publik)
 *   POST /api/v1/sandbox/:snap/simulate-pay
 *   POST /api/v1/sandbox/:snap/simulate-expire
 *
 * Jalankan:
 *   cd server && npm install && npm start
 *
 * Lalu arahkan aplikasi ke mock:
 *   flutter run --dart-define=MIOMIPAY_BASE_URL=http://localhost:4000/api/v1 \
 *               --dart-define=MIOMIPAY_API_KEY=miomipay_sandbox_key
 */

const express = require('express');
const crypto = require('crypto');

const app = express();

const PORT = Number(process.env.PORT || 4000);
const API_KEY = process.env.MIOMIPAY_API_KEY || 'miomipay_sandbox_key';

// ── Middleware ───────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Accept, Authorization, X-API-Key, Idempotency-Key'
  );
  res.setHeader('Access-Control-Max-Age', '86400');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

app.use(express.json());

app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    console.log(
      `${req.method.padEnd(6)} ${req.originalUrl.padEnd(44)} ` +
        `${res.statusCode}  ${Date.now() - started}ms`
    );
  });
  next();
});

// ── State ────────────────────────────────────────────────────────────────────
/** @type {Map<string, object>} snap_token → transaction */
const transactions = new Map();
/** @type {Array<object>} */
const webhookLog = [];

// ── Helpers ──────────────────────────────────────────────────────────────────
const nowIso = () => new Date().toISOString();

function requiredBearer(req, res, next) {
  const raw = String(req.headers.authorization || '');
  if (!raw.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      message: 'Missing API Key in Bearer Token Authorization header',
    });
  }
  if (raw.slice(7).trim() !== API_KEY) {
    return res.status(401).json({ success: false, message: 'Invalid API Key' });
  }
  next();
}

function buildQrString(snapToken, amount) {
  return (
    '00020101021226' +
    '66' +
    '0014ID.CO.GOPAY.WWW' +
    '01189360091800000000000215SANDBOXMIOMIPAY' +
    '52' +
    '045499' +
    '5303360' +
    '54' +
    String(amount).padStart(3, '0') +
    '5802ID' +
    '5912MIOMIPAY_SB' +
    '6009INDRAMAYU' +
    '6304ABCD'
  );
}

function logWebhook(tx, event) {
  const payload = {
    event,
    reference: tx.reference,
    external_id: tx.external_id,
    snap_token: tx.snap_token,
    amount: tx.amount,
    status: tx.status,
    paid_at: tx.paid_at,
    sent_at: nowIso(),
  };
  webhookLog.push(payload);
  console.log(`[WEBHOOK] ${event} → ${tx.snap_token}`);
}

// ── Routes ───────────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'miomipay-mock',
    environment: 'sandbox',
    transactions: transactions.size,
    time: nowIso(),
  });
});

// Buat transaksi
app.post('/api/v1/transactions', requiredBearer, (req, res) => {
  const { external_id, amount, description = '' } = req.body || {};

  if (!external_id) {
    return res.status(422).json({
      message: 'The external id field is required.',
      errors: { external_id: ['The external id field is required.'] },
    });
  }

  const amountNumber = Number(amount);
  if (!Number.isFinite(amountNumber) || amountNumber <= 0) {
    return res.status(422).json({
      message: 'The amount field is required.',
      errors: { amount: ['The amount field is required.'] },
    });
  }

  const reference =
    'MP-INV-' +
    new Date().toISOString().slice(0, 10).replace(/-/g, '') +
    '-' +
    crypto.randomBytes(3).toString('hex').toUpperCase();
  const snapToken = 'snap_' + crypto.randomBytes(16).toString('hex');

  const tx = {
    reference,
    external_id,
    environment: 'sandbox',
    amount: amountNumber,
    final_amount: amountNumber,
    status: 'PENDING',
    qr_string: buildQrString(snapToken, amountNumber),
    qr_image_url: `http://localhost:${PORT}/pay/${snapToken}/qr.png`,
    snap_token: snapToken,
    checkout_url: `http://localhost:${PORT}/pay/${snapToken}`,
    expired_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    paid_at: null,
    description,
    created_at: nowIso(),
  };

  transactions.set(snapToken, tx);
  console.log(`[CREATE] ${reference}  Rp ${amountNumber.toLocaleString('id-ID')}`);

  return res.status(201).json({ success: true, data: tx });
});

// Status transaksi (publik)
app.get('/api/v1/transactions/:snap/status', (req, res) => {
  const tx = transactions.get(req.params.snap);
  if (!tx) {
    return res.status(404).json({
      success: false,
      message: 'Transaction not found.',
    });
  }

  if (tx.status === 'PENDING' && new Date(tx.expired_at).getTime() < Date.now()) {
    tx.status = 'EXPIRED';
  }

  return res.json({
    success: true,
    status: tx.status,
    is_paid: tx.status === 'PAID',
    is_expired: tx.status === 'EXPIRED',
    paid_at: tx.paid_at,
    success_redirect_url: null,
    environment: 'sandbox',
  });
});

// Simulasi pembayaran sukses
app.post('/api/v1/sandbox/:snap/simulate-pay', (req, res) => {
  const tx = transactions.get(req.params.snap);
  if (!tx) {
    return res.status(404).json({
      success: false,
      message: 'Transaction not found.',
    });
  }

  if (tx.status !== 'PAID') {
    tx.status = 'PAID';
    tx.paid_at = nowIso();
    logWebhook(tx, 'transaction.paid');
  }

  console.log(`[PAID]   ${tx.snap_token}`);
  return res.json({
    success: true,
    message: 'Simulasi pembayaran sukses! Status transaksi kini PAID.',
  });
});

// Simulasi kedaluwarsa
app.post('/api/v1/sandbox/:snap/simulate-expire', (req, res) => {
  const tx = transactions.get(req.params.snap);
  if (!tx) {
    return res.status(404).json({
      success: false,
      message: 'Transaction not found.',
    });
  }

  tx.status = 'EXPIRED';
  logWebhook(tx, 'transaction.expired');
  return res.json({ success: true, message: 'Transaksi kini EXPIRED.' });
});

// Halaman checkout tiruan
app.get('/pay/:snap', (req, res) => {
  const tx = transactions.get(req.params.snap);
  if (!tx) return res.status(404).send('Transaction not found');
  res.type('html').send(`<!doctype html>
<html><head><meta charset="utf-8"><title>MiomiPay Mock</title></head>
<body style="font-family:system-ui;padding:32px">
  <h2>MiomiPay Sandbox</h2>
  <p>Invoice: <code>${tx.reference}</code></p>
  <p>External ID: <code>${tx.external_id}</code></p>
  <p>Amount: Rp ${tx.amount.toLocaleString('id-ID')}</p>
  <p>Status: <b>${tx.status}</b></p>
  <p>QR: <code style="word-break:break-all">${tx.qr_string}</code></p>
</body></html>`);
});

// QR gambar tiruan (placeholder 1x1 transparan)
app.get('/pay/:snap/qr.png', (_req, res) => {
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    'base64'
  );
  res.type('png').send(png);
});

// Debug webhook
app.get('/api/v1/webhook/test', (_req, res) => {
  res.json({ total: webhookLog.length, data: webhookLog.slice(-20) });
});

// ── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log('');
  console.log('  MiomiPay Mock Server');
  console.log(`  http://localhost:${PORT}`);
  console.log(`  api key : ${API_KEY}`);
  console.log('');
  console.log('  Arahkan aplikasi dengan:');
  console.log(
    `    --dart-define=MIOMIPAY_BASE_URL=http://localhost:${PORT}/api/v1`
  );
  console.log(`    --dart-define=MIOMIPAY_API_KEY=${API_KEY}`);
  console.log('');
});
