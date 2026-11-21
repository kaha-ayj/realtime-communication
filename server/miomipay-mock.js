/**
 * MiomiPay Mock Server
 *
 * Meniru kontrak API MiomiPay (https://pg.miomidev.com/api/v1) sehingga
 * aplikasi dapat dijalankan tanpa internet:
 *
 *   GET  /health
 *   POST /api/v1/payment/create                    (Bearer API key)
 *   GET  /api/v1/payment/:reference/status         (Bearer API key)
 *   POST /api/v1/sandbox/:snap/simulate-pay
 *   POST /api/v1/sandbox/:snap/simulate-expire
 *   GET  /api/v1/webhook/test
 *
 * Endpoint lama /transactions tetap tersedia sebagai alias.
 *
 * Jika MIOMIPAY_WEBHOOK_URL diisi, setiap perubahan status PAID/EXPIRED akan
 * mengirim webhook bertanda tangan HMAC-SHA256 ke URL tersebut.
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
const loadDotEnv = require('./load-env');

loadDotEnv();

const app = express();

const PORT = Number(process.env.PORT || 4000);
const API_KEY = process.env.MIOMIPAY_API_KEY || 'miomipay_sandbox_key';
const WEBHOOK_URL = process.env.MIOMIPAY_WEBHOOK_URL || '';
const WEBHOOK_SECRET = process.env.MIOMIPAY_WEBHOOK_SECRET || '';

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
      `${req.method.padEnd(6)} ${req.originalUrl.padEnd(48)} ` +
        `${res.statusCode}  ${Date.now() - started}ms`
    );
  });
  next();
});

// ── State ────────────────────────────────────────────────────────────────────
/** @type {Map<string, object>} reference → transaction */
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

function findTransaction(value) {
  const key = String(value || '');
  if (transactions.has(key)) return transactions.get(key);

  for (const tx of transactions.values()) {
    if (tx.snap_token === key || tx.invoice_number === key) return tx;
  }
  return null;
}

function buildQrString(amount) {
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

function refreshStatus(tx) {
  if (
    tx.status === 'PENDING' &&
    new Date(tx.expires_at).getTime() < Date.now()
  ) {
    tx.status = 'EXPIRED';
  }
  return tx;
}

function publicTransaction(tx) {
  return {
    reference: tx.reference,
    invoice_number: tx.invoice_number,
    external_id: tx.external_id,
    amount: tx.amount,
    unique_amount: tx.unique_amount,
    payable_amount: tx.payable_amount,
    final_amount: tx.final_amount,
    environment: tx.environment,
    payment_method: tx.payment_method,
    status: tx.status,
    checkout_url: tx.checkout_url,
    qr_image_url: tx.qr_image_url,
    qr_string: tx.qr_string,
    snap_token: tx.snap_token,
    created_at: tx.created_at,
    expires_at: tx.expires_at,
    expired_at: tx.expires_at,
    paid_at: tx.paid_at,
    customer_name: tx.customer_name,
    customer_email: tx.customer_email,
    customer_phone: tx.customer_phone,
    description: tx.description,
  };
}

async function notifyWebhook(tx, eventName) {
  const payload = JSON.stringify({
    event: eventName,
    data: publicTransaction(tx),
  });

  webhookLog.push({
    event: eventName,
    reference: tx.reference,
    status: tx.status,
    payload,
    sent_at: nowIso(),
  });

  if (!WEBHOOK_URL) return;
  if (!WEBHOOK_SECRET) {
    console.warn(
      '[WEBHOOK] MIOMIPAY_WEBHOOK_SECRET belum diisi; webhook tidak dikirim.'
    );
    return;
  }

  const signature = crypto
    .createHmac('sha256', WEBHOOK_SECRET)
    .update(payload)
    .digest('hex');

  try {
    const response = await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-MiomiPay-Event': eventName,
        'X-MiomiPay-Signature': signature,
      },
      body: payload,
    });
    console.log(
      `[WEBHOOK] ${eventName} → ${WEBHOOK_URL} (HTTP ${response.status})`
    );
  } catch (error) {
    console.warn(`[WEBHOOK] gagal mengirim ${eventName}: ${error.message}`);
  }
}

// ── Routes ───────────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'miomipay-mock',
    environment: 'sandbox',
    transactions: transactions.size,
    webhook_url: WEBHOOK_URL || null,
    time: nowIso(),
  });
});

// Buat tagihan QRIS
async function createPayment(req, res) {
  const {
    external_id,
    amount,
    description = '',
    customer_name,
    customer_email,
    customer_phone,
  } = req.body || {};

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

  const now = new Date();
  const dateCode = now.toISOString().slice(0, 10).replace(/-/g, '');
  const suffix = crypto.randomBytes(4).toString('hex').toUpperCase();
  const reference = `MP-SB-${suffix}`;
  const invoiceNumber = `INV-${dateCode}-${suffix.slice(0, 4)}`;
  const snapToken = 'snap_' + crypto.randomBytes(16).toString('hex');
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

  const tx = {
    reference,
    invoice_number: invoiceNumber,
    external_id: String(external_id),
    environment: 'sandbox',
    amount: amountNumber,
    unique_amount: amountNumber,
    payable_amount: amountNumber,
    final_amount: amountNumber,
    payment_method: 'qris',
    status: 'PENDING',
    qr_string: buildQrString(amountNumber),
    qr_image_url: `http://localhost:${PORT}/pay/${snapToken}/qr.png`,
    snap_token: snapToken,
    checkout_url: `http://localhost:${PORT}/pay/${snapToken}`,
    expires_at: expiresAt,
    paid_at: null,
    description,
    customer_name: customer_name || null,
    customer_email: customer_email || null,
    customer_phone: customer_phone || null,
    created_at: nowIso(),
  };

  transactions.set(reference, tx);
  console.log(
    `[CREATE] ${reference}  ${tx.external_id}  Rp ${amountNumber.toLocaleString(
      'id-ID'
    )}`
  );

  return res.status(201).json({
    success: true,
    message: 'Payment created successfully',
    data: publicTransaction(tx),
  });
}

app.post('/api/v1/payment/create', requiredBearer, createPayment);
// Alias kontrak lama.
app.post('/api/v1/transactions', requiredBearer, createPayment);

// Status transaksi
function paymentStatus(req, res) {
  const tx = findTransaction(req.params.reference || req.params.snap);
  if (!tx) {
    return res.status(404).json({
      success: false,
      message: 'Transaksi tidak ditemukan',
    });
  }

  refreshStatus(tx);
  const data = publicTransaction(tx);

  return res.json({
    success: true,
    status: tx.status,
    is_paid: tx.status === 'PAID',
    is_expired: tx.status === 'EXPIRED',
    paid_at: tx.paid_at,
    environment: tx.environment,
    data,
  });
}

app.get('/api/v1/payment/:reference/status', requiredBearer, paymentStatus);
// Alias kontrak lama.
app.get('/api/v1/transactions/:snap/status', requiredBearer, paymentStatus);

// Simulasi pembayaran sukses
app.post('/api/v1/sandbox/:token/simulate-pay', requiredBearer, async (req, res) => {
  const tx = findTransaction(req.params.token);
  if (!tx) {
    return res.status(404).json({
      success: false,
      message: 'Transaksi tidak ditemukan',
    });
  }

  if (tx.status !== 'PAID') {
    tx.status = 'PAID';
    tx.paid_at = nowIso();
    await notifyWebhook(tx, 'payment.success');
  }

  console.log(`[PAID]   ${tx.reference} (${tx.snap_token})`);
  return res.json({
    success: true,
    message: 'Simulasi pembayaran sukses! Status transaksi kini PAID.',
  });
});

// Simulasi kedaluwarsa
app.post(
  '/api/v1/sandbox/:token/simulate-expire',
  requiredBearer,
  async (req, res) => {
    const tx = findTransaction(req.params.token);
    if (!tx) {
      return res.status(404).json({
        success: false,
        message: 'Transaksi tidak ditemukan',
      });
    }

    tx.status = 'EXPIRED';
    await notifyWebhook(tx, 'payment.expired');
    return res.json({ success: true, message: 'Transaksi kini EXPIRED.' });
  }
);

// Halaman checkout tiruan
app.get('/pay/:snap', (req, res) => {
  const tx = findTransaction(req.params.snap);
  if (!tx) return res.status(404).send('Transaction not found');
  res.type('html').send(`<!doctype html>
<html><head><meta charset="utf-8"><title>MiomiPay Mock</title></head>
<body style="font-family:system-ui;padding:32px">
  <h2>MiomiPay Sandbox</h2>
  <p>Invoice: <code>${tx.invoice_number}</code></p>
  <p>Reference: <code>${tx.reference}</code></p>
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
  console.log(`  webhook : ${WEBHOOK_URL || '(belum diatur)'}`);
  console.log('');
  console.log('  Arahkan aplikasi dengan:');
  console.log(
    `    --dart-define=MIOMIPAY_BASE_URL=http://localhost:${PORT}/api/v1`
  );
  console.log(`    --dart-define=MIOMIPAY_API_KEY=${API_KEY}`);
  console.log('');
});
