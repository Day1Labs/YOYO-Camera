# YOYO Client

YOYO Client is a SwiftUI camera app for iOS, combining manual controls, live film and LUT rendering, intelligent camera automation, and AI-assisted post-processing.

## Highlights

- Manual camera controls for exposure, ISO, shutter speed, focus, white balance, zoom, and audio/video capture
- Live filters and film emulation powered by LUT assets and Metal shaders
- Automation workflows driven by scene, lighting, composition, color, time, and location
- AI features for inspiration, gallery workflows, and darkroom-style enhancements
- Apple Sign In, subscription paywall, widget support, and App Intent quick launch

## Tech Stack

- SwiftUI and Combine
- AVFoundation for camera and media capture
- Core Image and Metal for rendering
- Core ML and Vision for on-device intelligence
- StoreKit, WidgetKit, App Intents, and Firebase

## Project Layout

```text
YOYO-Client/
├── Yoyo/                  # Main iOS app target
│   ├── Camera/            # Camera UI and controls
│   ├── Capture/           # Photo/video capture pipeline
│   ├── Device/            # Session and hardware management
│   ├── Automation/        # Rule engine and scene analysis
│   ├── Filter/            # LUT filters and configuration
│   ├── Film/              # Film emulation and Metal shaders
│   ├── Gallery/           # Gallery and AI darkroom flows
│   ├── Auth/              # Sign in, paywall, account logic
│   └── Assets.xcassets/   # App assets and LUT resources
├── YoyoControlWidget/     # Widget extension
├── YoyoTests/             # Unit tests
├── YoyoUITests/           # UI tests
└── scripts/               # Utility scripts
```

## Requirements

- Xcode 15 or later
- iOS 17 or later
- A valid Apple developer setup for running on device
- A valid `GoogleService-Info.plist` for Firebase-enabled builds

## Getting Started

1. Open `Yoyo.xcodeproj` in Xcode.
2. Select the `Yoyo` scheme.
3. Build and run on an iPhone or simulator.

Optional CLI commands:

```bash
xcodebuild -project Yoyo.xcodeproj -scheme Yoyo build
xcodebuild -project Yoyo.xcodeproj -scheme Yoyo test
```

## Localization

- English: `Yoyo/en.lproj`
- Simplified Chinese: `Yoyo/zh-Hans.lproj`

Localized accessors are generated from the strings files by `scripts/generate_localized_strings.py`.
