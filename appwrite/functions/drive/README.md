# Appwrite Function: `drive`

Server-side helper for Google Drive OAuth + uploads/downloads.

## Routes

- `GET /oauth/start` → `{ url }` (teacher must be signed-in; uses Appwrite function user context)
- `GET /oauth/callback?code=...&state=...` → stores refresh token for `state = teacherId`
- `GET /status` → `{ connected: boolean }`
- `POST /drive/upload` → `{ file }` where body is `{ name, mimeType, base64, parents? }`
- `GET /drive/download?fileId=...` → streams bytes

## Environment variables (required)

- `APPWRITE_ENDPOINT`
- `APPWRITE_PROJECT_ID`
- `APPWRITE_API_KEY` (server API key with DB read/write)
- `APPWRITE_DATABASE_ID` (default `teachers_help`)
- `APPWRITE_DRIVE_CONNECTIONS_COLLECTION_ID` (default `drive_connections`)

- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REDIRECT_URI` (must point to this function’s `/oauth/callback` URL)
- `GOOGLE_DRIVE_SCOPE` (optional; space- or comma-separated URLs. Default: `https://www.googleapis.com/auth/drive` so uploads and Drive Picker work without “insufficient authentication scopes”. For stricter access use e.g. `https://www.googleapis.com/auth/drive.file`.)

- `TOKEN_ENCRYPTION_KEY` (base64 for 32 bytes; used for AES-256-GCM encryption of refresh tokens)

## Notes

- The Flutter Web client should call this function via Appwrite Functions (authenticated) to avoid handling long-lived Google tokens in the browser.
- **After changing `GOOGLE_DRIVE_SCOPE`:** add the same scope(s) under **Google Cloud → APIs & Services → OAuth consent screen → Scopes**, redeploy if needed, then in the app **disconnect Google Drive and connect again** (existing refresh tokens keep old scopes until re-consent).
- Using **`drive.file` only** is stricter (files the app created/opened) but can be finicky with some flows; full **`drive`** scope is the default for reliability in this project.

