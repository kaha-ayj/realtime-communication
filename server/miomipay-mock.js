/**
 * MiomiPay Mock Server
 * Express server on port 4000 simulating QRIS payment flow.
 *
 * Endpoints:
 *   GET  /health                     — health check
 *   POST /v1/payments                — create a charge/QR
 *   GET  /v1/payments/:ref           — get payment status
 *   POST /v1/payments/:ref/pay       — simulate successful payment
 *   POST /v1/payments/:ref/cancel    — simulate cancelled payment
 */

const express = require('express');
const crypto = require('crypto');

const app = express();
app.use(express.json());

// In-memory store: ref → payment record
const payments = new Map();

// ── Helpers ──────────────────────────────────────────────────────────────────

function generateRef() {
  return 'MIOMI-' + crypto.randomBytes(6).toString('hex').toUpperCase();
}

function generateQrString(ref, amount) {
  // Minimal QRIS-like string for QR rendering; in production this would be a
  // real QRIS payload from the payment network.
  return `00020101021226580014com.miomipay.qris0136${ref}520400005303360540${amount}5802ID5916POS Sederhana6007Jakarta6304ABCD`;
}

function now() {
  return new Date().toISOString();
}

// ── Routes ───────────────────────────────────────────────────────────────────

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'miomipay-mock', time: now() });
});

// Create payment / charge
app.post('/v1/payments', (req, res) => {
  const { reference, amount, description, currency = 'IDR' } = req.body;

  if (!reference || !amount) {
    return res.status(400).json({ error: 'reference and amount are required' });
  }

  const ref = reference;
  const record = {
    reference: ref,
    amount: Number(amount),
    currency,
    description: description || '',
    status: 'pending',
    qr_string: generateQrString(ref, amount),
    created_at: now(),
    paid_at: null,
  };

  payments.set(ref, record);
  console.log(`[CREATE] ${ref}  Rp ${amount}`);

  return res.status(201).json(record);
});

// Get payment status
app.get('/v1/payments/:ref', (req, res) => {
  const record = payments.get(req.params.ref);
  if (!record) {
    return res.status(404).json({ error: 'Payment not found' });
  }
  return res.json(record);
});

// Simulate successful payment (sandbox)
app.post('/v1/payments/:ref/pay', (req, res) => {
  const record = payments.get(req.params.ref);
  if (!record) {
    return res.status(404).json({ error: 'Payment not found' });
  }
  if (record.status === 'paid') {
    return res.json(record); // idempotent
  }

  record.status = 'paid';
  record.paid_at = now();
  payments.set(req.params.ref, record);
  console.log(`[PAY]    ${req.params.ref}  → paid`);

  return res.json(record);
});

// Simulate cancelled payment (sandbox)
app.post('/v1/payments/:ref/cancel', (req, res) => {
  const record = payments.get(req.params.ref);
  if (!record) {
    return res.status(404).json({ error: 'Payment not found' });
  }

  record.status = 'cancelled';
  payments.set(req.params.ref, record);
  console.log(`[CANCEL] ${req.params.ref}  → cancelled`);

  return res.json(record);
});

// ── Start ─────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
  console.log(`MiomiPay Mock Server running on http://localhost:${PORT}`);
  console.log('Endpoints:');
  console.log(`  GET  http://localhost:${PORT}/health`);
  console.log(`  POST http://localhost:${PORT}/v1/payments`);
  console.log(`  GET  http://localhost:${PORT}/v1/payments/:ref`);
  console.log(`  POST http://localhost:${PORT}/v1/payments/:ref/pay`);
  console.log(`  POST http://localhost:${PORT}/v1/payments/:ref/cancel`);
});
