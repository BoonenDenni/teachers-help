import { decryptString, encryptString } from './crypto.js';
import { Readable } from 'node:stream';
import {
  classContainsFileId,
  createAdminClient,
  createDatabases,
  deleteDriveConnections,
  getClassByPublicToken,
  getDriveConnection,
  logDeletedDriveItem,
  markDeletedDriveItemRestored,
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

function parseBodyJson(req) {
  if (req.bodyJson && typeof req.bodyJson === 'object') return req.bodyJson;
  const raw = req.body;
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  if (typeof raw !== 'string') return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
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

    // GET /drive/root -> { rootFolderId: string }
    if (req.method === 'GET' && path === '/drive/root') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      return json(res, 200, { rootFolderId: conn.rootFolderId || '' });
    }

    // POST /drive/root { rootFolderId } -> { ok: true }
    if (req.method === 'POST' && path === '/drive/root') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { rootFolderId } = body;
      if (typeof rootFolderId !== 'string' || rootFolderId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing rootFolderId.' });
      }
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      await databases.updateDocument(
        conn.$databaseId,
        conn.$collectionId,
        conn.$id,
        { rootFolderId: rootFolderId.trim() },
      );
      return json(res, 200, { ok: true });
    }

    // POST /drive/folder/ensure
    // body: { parentId?: string, name: string } -> { id, name }
    if (req.method === 'POST' && path === '/drive/folder/ensure') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { parentId, name } = body;
      if (typeof name !== 'string' || name.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing folder name.' });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);

      const p = typeof parentId === 'string' && parentId.trim() !== '' ? parentId.trim() : 'root';
      const folderName = name.trim();
      const esc = folderName.replace(/'/g, "\\'");
      const q = [
        `trashed=false`,
        `'${p}' in parents`,
        `mimeType='application/vnd.google-apps.folder'`,
        `name='${esc}'`,
      ].join(' and ');

      const listRes = await drive.files.list({
        q,
        fields: 'files(id,name)',
        pageSize: 5,
      });
      const existing = Array.isArray(listRes.data.files) ? listRes.data.files[0] : null;
      if (existing?.id) {
        return json(res, 200, { id: existing.id, name: existing.name || folderName });
      }

      const createRes = await drive.files.create({
        requestBody: {
          name: folderName,
          mimeType: 'application/vnd.google-apps.folder',
          parents: p === 'root' ? undefined : [p],
        },
        fields: 'id,name',
      });
      return json(res, 200, { id: createRes.data.id, name: createRes.data.name || folderName });
    }

    // POST /drive/folder/rename
    // body: { folderId: string, newName: string } -> { ok: true }
    if (req.method === 'POST' && path === '/drive/folder/rename') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { folderId, newName } = body;
      if (typeof folderId !== 'string' || folderId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing folderId.' });
      }
      if (typeof newName !== 'string' || newName.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing newName.' });
      }
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);
      await drive.files.update({
        fileId: folderId.trim(),
        requestBody: { name: newName.trim() },
      });
      return json(res, 200, { ok: true });
    }

    // POST /drive/shortcut/create
    // body: { parentId: string, targetFileId: string, name?: string } -> { file }
    if (req.method === 'POST' && path === '/drive/shortcut/create') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { parentId, targetFileId, name } = body;
      if (typeof parentId !== 'string' || parentId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing parentId.' });
      }
      if (typeof targetFileId !== 'string' || targetFileId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing targetFileId.' });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });

      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);

      const shortcutName =
        typeof name === 'string' && name.trim() !== '' ? name.trim() : 'Shortcut';
      const createRes = await drive.files.create({
        requestBody: {
          name: shortcutName,
          parents: [parentId.trim()],
          mimeType: 'application/vnd.google-apps.shortcut',
          shortcutDetails: { targetId: targetFileId.trim() },
        },
        fields: 'id,name,mimeType,shortcutDetails',
      });
      return json(res, 200, { file: createRes.data });
    }

    // POST /drive/item/trash
    // body: { fileId: string } -> { ok: true }
    if (req.method === 'POST' && path === '/drive/item/trash') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { fileId } = body;
      if (typeof fileId !== 'string' || fileId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing fileId.' });
      }
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);
      await drive.files.update({
        fileId: fileId.trim(),
        requestBody: { trashed: true },
      });
      return json(res, 200, { ok: true });
    }

    // POST /drive/item/restore
    // body: { fileId: string } -> { ok: true }
    if (req.method === 'POST' && path === '/drive/item/restore') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { fileId } = body;
      if (typeof fileId !== 'string' || fileId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing fileId.' });
      }
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);
      await drive.files.update({
        fileId: fileId.trim(),
        requestBody: { trashed: false },
      });
      return json(res, 200, { ok: true });
    }

    // POST /drive/item/trash_and_log
    // body: { fileId: string, name: string, kind: string } -> { ok: true }
    if (req.method === 'POST' && path === '/drive/item/trash_and_log') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { fileId, name, kind } = body;
      if (typeof fileId !== 'string' || fileId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing fileId.' });
      }
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);
      await drive.files.update({
        fileId: fileId.trim(),
        requestBody: { trashed: true },
      });
      await logDeletedDriveItem({
        databases,
        teacherId,
        driveFileId: fileId.trim(),
        name: typeof name === 'string' && name.trim() !== '' ? name.trim() : 'item',
        kind: typeof kind === 'string' && kind.trim() !== '' ? kind.trim() : 'unknown',
      });
      return json(res, 200, { ok: true });
    }

    // POST /drive/item/restore_and_mark
    // body: { fileId: string, deletedItemId: string } -> { ok: true }
    if (req.method === 'POST' && path === '/drive/item/restore_and_mark') {
      const teacherId = requireUserId(req, res);
      if (typeof teacherId !== 'string') return teacherId;
      const body = parseBodyJson(req) || {};
      const { fileId, deletedItemId } = body;
      if (typeof fileId !== 'string' || fileId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing fileId.' });
      }
      if (typeof deletedItemId !== 'string' || deletedItemId.trim() === '') {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing deletedItemId.' });
      }
      const client = createAdminClient();
      const databases = createDatabases(client);
      const conn = await getDriveConnection({ databases, teacherId });
      if (!conn) return json(res, 409, { error: 'NOT_CONNECTED', message: 'Google Drive not connected.' });
      const refreshToken = decryptString(conn.refreshTokenEnc);
      const drive = await driveClientFromRefreshToken(refreshToken);
      await drive.files.update({
        fileId: fileId.trim(),
        requestBody: { trashed: false },
      });
      await markDeletedDriveItemRestored({ databases, deletedItemId: deletedItemId.trim() });
      return json(res, 200, { ok: true });
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

