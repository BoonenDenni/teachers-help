import { google } from 'googleapis';

import { env } from './env.js';

/** Default: full Drive access so uploads/downloads and Picker work reliably. Override with GOOGLE_DRIVE_SCOPE. */
const DEFAULT_DRIVE_SCOPES = ['https://www.googleapis.com/auth/drive'];

/**
 * Parses GOOGLE_DRIVE_SCOPE (space- or comma-separated URLs). If unset/empty, uses DEFAULT_DRIVE_SCOPES.
 * A single env value must not be wrapped in an extra array entry — that breaks OAuth and can yield broken tokens.
 */
export function driveScopesFromEnv() {
  const raw = process.env.GOOGLE_DRIVE_SCOPE;
  if (raw === undefined || String(raw).trim() === '') {
    return DEFAULT_DRIVE_SCOPES;
  }
  return String(raw)
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

export function createOAuthClient() {
  return new google.auth.OAuth2(
    env('GOOGLE_CLIENT_ID'),
    env('GOOGLE_CLIENT_SECRET'),
    env('GOOGLE_REDIRECT_URI'),
  );
}

export function buildAuthUrl({ teacherId }) {
  const oauth2 = createOAuthClient();
  const scopes = driveScopesFromEnv();

  return oauth2.generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: scopes,
    state: teacherId,
  });
}

export async function exchangeCodeForTokens(code) {
  const oauth2 = createOAuthClient();
  const { tokens } = await oauth2.getToken(code);
  return tokens;
}

export async function driveClientFromRefreshToken(refreshToken) {
  const oauth2 = createOAuthClient();
  oauth2.setCredentials({ refresh_token: refreshToken });
  // Ensure we have an access token now (googleapis will refresh as needed too).
  await oauth2.getAccessToken();
  return google.drive({ version: 'v3', auth: oauth2 });
}

export async function accessTokenFromRefreshToken(refreshToken) {
  const oauth2 = createOAuthClient();
  oauth2.setCredentials({ refresh_token: refreshToken });
  const tokenRes = await oauth2.getAccessToken();
  const token = tokenRes?.token;
  if (!token) throw new Error('Could not mint access token.');
  return token;
}

