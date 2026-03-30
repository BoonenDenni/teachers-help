import { decryptString, encryptString } from './crypto.js';
import { Readable } from 'node:stream';
import {
  classContainsFileId,
  createAdminClient,
  createDatabases,
  deleteDriveConnections,
  getClassByPublicToken,
  getDriveConnection,
  upsertDriveConnection,
} from './appwrite.js';
import {
  accessTokenFromRefreshToken,
  buildAuthUrl,
  driveClientFromRefreshToken,
  exchangeCodeForTokens,
} from './google.js';

function json(res, status, body) {
  return res.json(body, status);
}

function getUserId(req) {
  // Appwrite injects the authenticated user ID when invoked with a user session.
  // Header casing can vary by runtime.
  return (
    req.headers['x-appwrite-user-id'] ||
    req.headers['X-Appwrite-User-Id'] ||
    req.headers['x-appwrite-userid'] ||
    null
  );
}

function requireUserId(req, res) {
  const userId = getUserId(req);
  if (!userId) {
    return json(res, 401, {
      error: 'UNAUTHENTICATED',
      message: 'Missing user context.',
    });
  }
  return userId;
}

export default async ({ req, res, log, error }) => {
  try {
    const path = req.path || '/';

    // GET /oauth/start -> { url }
    if (req.method === 'GET' && path === '/oauth/start') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const url = buildAuthUrl({ teacherId });
      return json(res, 200, { url });
    }

    // GET /oauth/callback?code=...&state=teacherId
    // Note: redirect URI must be configured to hit THIS function callback URL.
    if (req.method === 'GET' && path === '/oauth/callback') {
      const code = req.query?.code;
      const teacherIdFromState = req.query?.state;

      if (!code || !teacherIdFromState) {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing code/state.' });
      }

      const tokens = await exchangeCodeForTokens(code);
      if (!tokens.refresh_token) {
        return json(res, 400, {
          error: 'NO_REFRESH_TOKEN',
          message:
            'No refresh token returned. Ensure prompt=consent and access_type=offline.',
        });
      }

      const refreshTokenEnc = encryptString(tokens.refresh_token);

      const client = createAdminClient();
      const databases = createDatabases(client);

      await upsertDriveConnection({
        databases,
        teacherId: teacherIdFromState,
        googleUserId: tokens.id_token ? 'unknown' : 'unknown',
        refreshTokenEnc,
      });

      // For v1 we just show a success page; the Flutter app can poll status.
      return res.send(
        `<html><body><h2>Google Drive connected</h2><p>You can close this tab and return to the app.</p></body></html>`,
        200,
        { 'content-type': 'text/html' },
      );
    }

    // GET /status -> { connected: boolean }
    if (req.method === 'GET' && path === '/status') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const client = createAdminClient();
      const databases = createDatabases(client);
      const doc = await getDriveConnection({ databases, teacherId });
      return json(res, 200, { connected: !!doc });
    }

    // POST /disconnect -> { disconnected: boolean }
    if (req.method === 'POST' && path === '/disconnect') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const client = createAdminClient();
      const databases = createDatabases(client);
      const deleted = await deleteDriveConnections({ databases, teacherId });
      return json(res, 200, { disconnected: deleted > 0 });
    }

    // GET /oauth/token -> { accessToken }
    // Used by the web Drive Picker to browse existing files.
    if (req.method === 'GET' && path === '/oauth/token') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;

      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const accessToken = await accessTokenFromRefreshToken(refreshToken);
      return json(res, 200, { accessToken });
    }

    // POST /drive/upload
    // body: { name, mimeType, base64, parents?: string[] }
    if (req.method === 'POST' && path === '/drive/upload') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;

      const { name, mimeType, base64, parents } = req.bodyJson || {};
      if (!name || !mimeType || !base64) {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing name/mimeType/base64.' });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);

      const buffer = Buffer.from(base64, 'base64');
      const bodyStream = Readable.from(buffer);

      const createRes = await drive.files.create({
        requestBody: {
          name,
          parents: Array.isArray(parents) && parents.length > 0 ? parents : undefined,
        },
        media: {
          mimeType,
          body: bodyStream,
        },
        fields: 'id,name,mimeType,webViewLink,webContentLink',
      });

      return json(res, 200, { file: createRes.data });
    }

    // GET /drive/download?fileId=...
    // POST /drive/download { fileId } -> { mimeType, base64 }
    // (Appwrite Function executions work best with JSON responses.)
    if (req.method === 'POST' && path === '/drive/download') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;

      const { fileId } = req.bodyJson || {};
      if (!fileId) return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing fileId.' });

      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);

      const driveRes = await drive.files.get(
        { fileId, alt: 'media' },
        { responseType: 'arraybuffer' },
      );

      const contentType = driveRes.headers['content-type'] || 'application/octet-stream';
      const base64 = Buffer.from(driveRes.data).toString('base64');
      return json(res, 200, { mimeType: contentType, base64 });
    }

    // POST /public/download { publicToken, fileId } -> { mimeType, base64 }
    // Allows student access without an Appwrite session, while ensuring the fileId
    // belongs to the class identified by publicToken.
    if (req.method === 'POST' && path === '/public/download') {
      const { publicToken, fileId } = req.bodyJson || {};
      if (!publicToken || !fileId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/fileId.',
        });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Class not found.' });
      }

      const ok = await classContainsFileId({ databases, classId: clazz.$id, fileId });
      if (!ok) {
        return json(res, 403, { error: 'FORBIDDEN', message: 'File not part of this class.' });
      }

      const conn = await getDriveConnection({ databases, teacherId: clazz.teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Teacher Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);

      const driveRes = await drive.files.get(
        { fileId, alt: 'media' },
        { responseType: 'arraybuffer' },
      );

      const contentType = driveRes.headers['content-type'] || 'application/octet-stream';
      const base64 = Buffer.from(driveRes.data).toString('base64');
      return json(res, 200, { mimeType: contentType, base64 });
    }

    // GET /drive/download?fileId=... -> streams bytes (optional helper)
    if (req.method === 'GET' && path === '/drive/download') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;

      const fileId = req.query?.fileId;
      if (!fileId) return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing fileId.' });

      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);

      const driveRes = await drive.files.get(
        { fileId, alt: 'media' },
        { responseType: 'arraybuffer' },
      );

      const contentType = driveRes.headers['content-type'] || 'application/octet-stream';
      return res.send(Buffer.from(driveRes.data), 200, { 'content-type': contentType });
    }

    return json(res, 404, { error: 'NOT_FOUND', message: `No route for ${req.method} ${path}` });
  } catch (e) {
    error(e?.stack || String(e));
    const msg = String(e?.message ?? e);
    if (/insufficient authentication scopes/i.test(msg)) {
      return json(res, 403, {
        error: 'DRIVE_INSUFFICIENT_SCOPE',
        message:
          'Google blocked this request (OAuth scopes). Fix: (1) In Google Cloud: enable Drive API and add the same scope(s) as GOOGLE_DRIVE_SCOPE to the OAuth consent screen. (2) In the app: disconnect Google Drive and connect again so a new refresh token is stored.',
      });
    }
    return json(res, 500, { error: 'INTERNAL', message: String(e) });
  }
};

