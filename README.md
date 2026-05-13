<p align="center">
  <img src="./YOYO-Client/Yoyo/Assets.xcassets/Logo.imageset/logo.png" width="96" alt="YOYO Camera logo" />
</p>

<h1 align="center">YOYO Camera</h1>

<p align="center">
  <strong>Beyond the Lens.</strong><br />
  An open source AI-native camera stack for iOS.
</p>

<p align="center">
  <a href="https://github.com/Day1Labs/YOYO-Camera/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/Day1Labs/YOYO-Camera?style=social" /></a>
  <a href="./LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-black" /></a>
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-111111?logo=apple" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-F05138?logo=swift&logoColor=white" />
  <img alt="Cloudflare Workers" src="https://img.shields.io/badge/Cloudflare-Workers-F38020?logo=cloudflare&logoColor=white" />
</p>

<p align="center">
  <a href="https://day1-labs.com/yoyo/">Website</a> ·
  <a href="./YOYO-Client">iOS Client</a> ·
  <a href="./YOYO-Server">Cloudflare Server</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="./CONTRIBUTING.md">Contribute</a>
</p>

YOYO Camera is a full-stack reference implementation for the next generation of mobile photography: pro camera controls, real-time film rendering, context-aware automation, and generative AI workflows in one native iOS app.

If you are building camera apps, AI creative tools, mobile rendering pipelines, or Cloudflare-backed consumer products, this repo is designed to be studied, forked, and improved.

## Highlights

- **Real app architecture, not a toy demo**: native iOS client, edge backend, auth, subscriptions, credits, tests, localization, and production-style modules.
- **AI before and after capture**: scene-aware inspiration while shooting, plus AI darkroom workflows after capture.
- **Automation-first camera UX**: build rules that react to scene, lighting, composition, color, motion, time, location, and capture events.
- **Film rendering with character**: LUTs, Core Image, Metal shaders, grain, halation, bloom, vignette, and film-inspired presets.
- **Useful for makers**: a practical codebase for learning AVFoundation, SwiftUI camera UX, Core ML/Vision analysis, and Cloudflare Workers APIs.

## At A Glance

| Area | What YOYO Includes |
| --- | --- |
| Camera | Manual exposure, focus, ISO, shutter, white balance, zoom, photo, video, Live Photo, histogram, and quick capture |
| Intelligence | Scene classification, object detection, composition scoring, lighting analysis, color analysis, and motion-aware rules |
| Automation | Rule engine for context-aware camera behavior |
| Rendering | Built-in filter recipes, film presets, LUT assets, custom filters, and Metal-powered film effects |
| AI | Inspiration generation, AI image generation, object removal, portrait enhancement, blur repair, ID photo, color grading, and closed-eye fixes |
| Backend | Apple Sign In, JWT auth, subscriptions, credits, automation share codes, Google GenAI integration, D1 schema, and App Store notifications |

## Product Ideas Inside

YOYO explores a simple question:

> What if the camera understood what you are trying to shoot and helped you make better creative decisions in real time?

That idea shows up in four product loops:

- **Shoot with intent**: pro controls, gesture-friendly camera UI, quick actions, widgets, and App Intents.
- **Understand the scene**: analyze composition, light, color, objects, histograms, and context on device.
- **Automate the setup**: trigger camera actions from rules instead of repeatedly adjusting settings by hand.
- **Create with AI**: get visual inspiration from the current scene, then refine images with AI darkroom operations.

## Features

### Native iOS Camera

- SwiftUI camera interface built on AVFoundation capture sessions.
- Manual exposure, shutter speed, ISO, focus, white balance, lens, zoom, and audio/video controls.
- Real-time preview pipeline with live filters, histogram support, timers, guidelines, and orientation handling.
- Photo, video, and Live Photo capture with metadata and save services.
- Quick launch through home screen shortcuts, App Intents, and WidgetKit.

### Camera Automation

- "If this, then that" rule system for camera behavior.
- Conditions for scene type, lighting, composition, subject, object count, motion, histogram state, color, time, date, location, altitude, and capture events.
- Actions for camera settings, filter changes, exposure behavior, focus behavior, and UI feedback.
- Shareable automation rules backed by short codes from the server.

### Film And Filters

- Data-driven built-in filter registry with dozens of named looks.
- Film preset model inspired by color negative, cinema, portrait, landscape, and instant film characteristics.
- Core Image and Metal rendering for cine tone, grain, halation, bloom, fog, vignette, channel mixing, and highlight rolloff.
- LUT-backed assets and custom filter management for extending the visual system.

### AI Workflows

- **AI Inspiration**: upload a scene preview and receive creative directions, generated images, and style prompts.
- **AI Darkroom**: process captured photos with operations such as object removal, portrait enhancement, professional photo, social avatar, blur repair, color grading, and eye fixes.
- **Credit-aware UX**: backend-managed credits and subscription status for paid AI features.
- **Bilingual product foundation**: English and Simplified Chinese localization assets.

## Tech Stack

| Client | Server |
| --- | --- |
| SwiftUI | TypeScript |
| AVFoundation | Cloudflare Workers |
| Core Image | Cloudflare D1 |
| Metal | Wrangler |
| Core ML and Vision | Google GenAI |
| StoreKit | JWT auth |
| App Intents and WidgetKit | Vitest |
| Firebase Analytics | App Store Server API |

## Quick Start

### Clone

```bash
git clone https://github.com/Day1Labs/YOYO-Camera.git
cd YOYO-Camera
```

### Run The iOS Client

Requirements:

- Xcode 15 or later
- iOS 17 or later
- Swift 5.9 or later
- A valid Apple developer setup for device testing
- A Firebase `GoogleService-Info.plist` if you enable analytics/auth-dependent flows

Open the project:

```bash
open YOYO-Client/Yoyo.xcodeproj
```

Then select the `Yoyo` scheme, configure signing, and build on a real device or simulator.

Optional CLI build:

```bash
cd YOYO-Client
xcodebuild -project Yoyo.xcodeproj -scheme Yoyo build
```

### Run The Server

Requirements:

- Node.js 18 or later
- Cloudflare account
- Wrangler access

Install and start:

```bash
cd YOYO-Server
npm install
npm run dev
```

Run tests:

```bash
npm run test
```

Deploy:

```bash
npm run deploy
```

Apply the local D1 schema when needed:

```bash
wrangler d1 execute DB --file=schema.sql --local
```

## Configuration

The server uses Wrangler vars/secrets for auth, billing, and AI features. Configure values such as:

- `JWT_SECRET`
- `GEMINI_API_KEY`
- `IAP_SHARED_SECRET`
- `APP_STORE_PRIVATE_KEY`
- `APP_STORE_BUNDLE_ID`
- `APP_STORE_ISSUER_ID`
- `APP_STORE_KEY_ID`

The app currently points AI services at `https://yoyo.day1-labs.com`. Update client service base URLs if you run your own backend.

## What You Can Learn

- Building a modern mobile camera experience with SwiftUI and AVFoundation.
- Designing real-time camera controls that feel native and responsive.
- Creating Core Image and Metal pipelines for live visual effects.
- Combining Core ML/Vision analysis with rule-based product automation.
- Structuring AI-powered mobile features across app and backend.
- Implementing Apple Sign In, subscriptions, credits, and feature gating.
- Shipping a Cloudflare-native backend for a consumer mobile product.

## Contributing

Issues, ideas, and pull requests are welcome. See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for development setup, pull request checklist, localization notes, and good first contribution areas.

## Links

- Website: https://day1-labs.com/yoyo/
- iOS client: [`YOYO-Client`](./YOYO-Client)
- Cloudflare backend: [`YOYO-Server`](./YOYO-Server)
- Contributing guide: [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- License: [`MIT`](./LICENSE)

## Star History

<a href="https://www.star-history.com/#Day1Labs/YOYO-Camera&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Day1Labs/YOYO-Camera&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Day1Labs/YOYO-Camera&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Day1Labs/YOYO-Camera&type=Date" />
  </picture>
</a>

## License

Released under the MIT License. See [`LICENSE`](./LICENSE) for details.

If YOYO Camera helps you learn, prototype, or ship faster, a star is appreciated and helps more makers discover the project.
