import crypto from 'crypto';

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing env var: ${name}`);
  return value;
}

function getKey() {
  const raw = requireEnv('TOKEN_ENCRYPTION_KEY');
  const buf = Buffer.from(raw, 'base64');
  if (buf.length !== 32) {
    throw new Error(
      'TOKEN_ENCRYPTION_KEY must be base64 for 32 bytes (256-bit key).',
    );
  }
  return buf;
}

export function encryptString(plaintext) {
  const key = getKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(Buffer.from(plaintext, 'utf8')),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  // Pack as base64: iv.tag.ciphertext
  return [
    iv.toString('base64'),
    tag.toString('base64'),
    ciphertext.toString('base64'),
  ].join('.');
}

export function decryptString(packed) {
  const key = getKey();
  const [ivB64, tagB64, ctB64] = packed.split('.');
  if (!ivB64 || !tagB64 || !ctB64) throw new Error('Bad token payload');

  const iv = Buffer.from(ivB64, 'base64');
  const tag = Buffer.from(tagB64, 'base64');
  const ciphertext = Buffer.from(ctB64, 'base64');

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const plaintext = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]).toString('utf8');
  return plaintext;
}

