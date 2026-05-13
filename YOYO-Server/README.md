# YOYO Server

Backend for the YOYO Camera app, built on Cloudflare Workers and D1.

## Stack

- Cloudflare Workers
- Cloudflare D1
- TypeScript
- Google Gemini
- Sign in with Apple
- App Store Server API

## What It Does

- Authenticates users with Sign in with Apple
- Issues JWT tokens for app requests
- Manages user profiles and soft deletion
- Validates Apple subscriptions and tracks Pro status
- Applies credit-based access to AI features
- Stores and resolves shared automation rules
- Exposes AI image inspiration and AI darkroom endpoints
- Handles App Store Server Notifications V2

## Main Endpoints

- `POST /api/auth/apple`
- `GET /api/user`
- `PUT /api/user`
- `DELETE /api/user`
- `POST /api/user/subscribe`
- `POST /api/automation/share`
- `GET /api/automation/share/:code`
- `POST /api/inspiration`
- `POST /api/inspiration/image`
- `POST /api/ai_darkroom/process`
- `POST /api/webhook/appstore`

## Environment

Set these values in Wrangler vars or secrets:

- `JWT_SECRET`
- `GEMINI_API_KEY`
- `IAP_SHARED_SECRET`
- `APP_STORE_PRIVATE_KEY`
- `APP_STORE_BUNDLE_ID`
- `APP_STORE_ISSUER_ID`
- `APP_STORE_KEY_ID`

## Local Development

```bash
npm install
npm run dev
```

Apply the database schema when needed:

```bash
wrangler d1 execute DB --file=schema.sql --local
```

## Deploy

```bash
npm run deploy
```

The Worker entrypoint is `src/index.ts`, and the database schema lives in `schema.sql`.
