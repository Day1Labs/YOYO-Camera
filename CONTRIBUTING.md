# Contributing to YOYO Camera

Thanks for your interest in improving YOYO Camera. This project combines a native iOS camera app with a Cloudflare Workers backend, so contributions can range from small documentation fixes to camera, rendering, automation, AI, and server changes.

## Good First Contributions

- Improve camera UX, gestures, onboarding, accessibility, or empty states.
- Add or refine automation conditions, actions, presets, or import/export flows.
- Tune filter behavior, film presets, grain, halation, bloom, and rendering quality.
- Expand AI inspiration and darkroom workflows.
- Improve test coverage for automation, backend APIs, and formatting utilities.
- Add screenshots, demos, examples, setup notes, or troubleshooting guides.

## Development Setup

### iOS Client

Requirements:

- Xcode 15 or later
- iOS 17 or later
- Swift 5.9 or later
- Apple developer signing if you run on a physical device
- Firebase configuration if you use analytics or auth-dependent flows

Open the project:

```bash
open YOYO-Client/Yoyo.xcodeproj
```

Build from the command line:

```bash
cd YOYO-Client
xcodebuild -project Yoyo.xcodeproj -scheme Yoyo build
```

Run tests when your change touches logic that has coverage:

```bash
cd YOYO-Client
xcodebuild -project Yoyo.xcodeproj -scheme Yoyo test
```

### Server

Requirements:

- Node.js 18 or later
- Cloudflare account
- Wrangler access

Install dependencies:

```bash
cd YOYO-Server
npm install
```

Run the development server:

```bash
npm run dev
```

Run tests:

```bash
npm run test
```

Apply the local D1 schema when needed:

```bash
wrangler d1 execute DB --file=schema.sql --local
```

## Configuration

The server expects Wrangler vars or secrets for auth, billing, and AI features. Depending on your change, you may need:

- `JWT_SECRET`
- `GEMINI_API_KEY`
- `IAP_SHARED_SECRET`
- `APP_STORE_PRIVATE_KEY`
- `APP_STORE_BUNDLE_ID`
- `APP_STORE_ISSUER_ID`
- `APP_STORE_KEY_ID`

The iOS app currently points AI services at `https://yoyo.day1-labs.com`. If you run your own Worker, update the relevant client service base URLs.

## Localization

The app supports English and Simplified Chinese.

- English strings live in `YOYO-Client/Yoyo/en.lproj`.
- Simplified Chinese strings live in `YOYO-Client/Yoyo/zh-Hans.lproj`.
- If you change `YOYO-Client/Yoyo/en.lproj/Localizable.strings`, run:

```bash
cd YOYO-Client
python3 scripts/generate_localized_strings.py
```

Do not edit `YOYO-Client/Yoyo/Generated/String+Localized.swift` by hand.

## Pull Request Checklist

- Keep changes focused and easy to review.
- Update documentation when behavior, setup, or configuration changes.
- Add or update tests when the change affects non-trivial logic.
- Verify the iOS app builds when changing client code.
- Run `npm run test` when changing server code.
- Avoid committing local secrets, generated build outputs, or private configuration.
- Explain user-facing behavior changes clearly in the PR description.

## Issue Reports

When reporting a bug, include:

- What you expected to happen.
- What actually happened.
- Steps to reproduce the issue.
- Device, iOS version, Xcode version, or Worker environment when relevant.
- Screenshots, logs, or sample payloads if they help explain the problem.

## Design Principles

- Keep the camera fast and responsive.
- Prefer clear, native-feeling interactions over feature density.
- Make AI assist the creative flow instead of hiding the camera experience.
- Keep automation understandable and reversible.
- Treat rendering quality and performance as product features.
