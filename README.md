# Panel Scanner V3

<div align="center">

[![iOS](https://img.shields.io/badge/iOS-17.0+-007AFF.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-15.0+-147EFB.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

**Real-time electrical panel detection & inventory powered by YOLOv8-Large**

On-device machine learning • AR visualization • Professional data capture

[Features](#features) • [Quick Start](#quick-start) • [Documentation](#documentation) • [License](#license)

</div>

---

## Overview

**Panel Scanner V3** is a professional iOS application designed for electrical contractors. It leverages computer vision and OCR to automatically detect, identify, and catalog electrical panels and circuit breakers in real-time.

### Key Capabilities

- **30 FPS On-Device Detection** — YOLOv8-Large CoreML model with Neural Engine acceleration
- **Smart OCR** — Extracts panel part numbers with confidence scoring and user confirmation
- **Video + Data Export** — Synchronized MP4 recordings with structured JSON/CSV output
- **AR Mode** — Floating 3D labels in augmented reality for hands-free inspection
- **Cloud Sync** — Optional OneDrive integration for team collaboration
- **Electrical Guru AI** — AI-powered assistant for NEC codes and electrical questions

---

## Features

### Scanning Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Panel Mode** | Focus on panel label detection only | Quick panel identification |
| **Full Mode** | Detects panels + all breakers | Complete inventory capture |
| **AR Mode** | Augmented reality overlay (In Dev) | Hands-free inspection(In Dev) |

### Detection Intelligence

- **Real-time tracking** — Spatial deduplication prevents duplicate entries
- **Dwell-time validation** — Only captures stable detections (configurable threshold)
- **Cooldown system** — Prevents re-detecting the same items
- **OCR confirmation** — Review and verify panel labels before saving

### Export Options

| Format | Description |
|--------|-------------|
| **JSON** | Structured data with timestamps and confidence scores |
| **CSV** | Spreadsheet-ready breaker inventory |
| **MP4** | Video recording of entire scan session |
| **ZIP** | All files bundled for easy sharing |
| **OneDrive** | Direct cloud upload (optional) |

---

## Quick Start

### Prerequisites

- macOS with Xcode 15.0+
- iPhone 11 or newer (Neural Engine recommended)
- iOS 17.0+
- Valid Apple Developer account

### Installation

```bash
# Clone the repository
git clone https://github.com/CummingsElec/Panel_Capture_Pipeline.git
cd Panel_Capture_Pipeline/PanelScannerApp/PanelScanner

# Open in Xcode
open PanelScanner.xcodeproj

# Build and run (⌘R)
```

### First Launch

1. **Grant Permissions** — Camera access required
2. **Sign In** — Use SSO or enable Local Mode for testing
3. **Start Scanning** — Point camera at electrical panel
4. **Record** — Tap record button when detections appear
5. **Export** — Stop recording and share your data

---

## Architecture

### Tech Stack

| Component | Technology |
|-----------|------------|
| **Framework** | SwiftUI + Combine |
| **Pattern** | MVVM (Model-View-ViewModel) |
| **ML** | CoreML with YOLOv8-Large |
| **OCR** | Vision Framework |
| **AR** | ARKit + RealityKit |
| **Auth** | Microsoft Entra ID / Okta SSO |
| **Storage** | Core Data + FileManager |
| **Cloud** | OneDrive SDK |

### Project Structure

```
PanelScanner/
├── PanelScannerApp.swift          # App entry point
├── Config/
│   └── AppConfig.swift            # Default settings
├── Models/
│   ├── Detection.swift            # Detection data model
│   ├── SessionManager.swift       # Session tracking
│   └── AuthModels.swift           # SSO configuration
├── Views/
│   ├── MainView.swift             # Tab navigation
│   ├── CameraView.swift           # Camera preview
│   ├── AROverlayView.swift        # AR visualization
│   ├── CircuitBreakerGameView.swift
│   ├── ChatView.swift             # AI Guru chat
│   └── SplashScreenView.swift     # Launch screen
├── ViewModels/
│   ├── ScannerViewModel.swift     # Main app logic
│   ├── GameViewModel.swift        # Game logic
│   └── ChatViewModel.swift        # AI chat logic
├── Services/
│   ├── CameraService.swift        # Camera capture
│   ├── DetectionService.swift     # ML inference
│   ├── OCRService.swift           # Text extraction
│   ├── TrackingService.swift      # Deduplication
│   ├── AROverlayService.swift     # AR rendering
│   ├── CloudChatEngine.swift      # AI chat (OpenAI/xAI)
│   ├── OneDriveService.swift      # Cloud sync
│   └── AuthCoordinator.swift      # Authentication
└── best.mlpackage/                # YOLOv8L model
```

---

## Configuration

### Detection Settings

Adjust in-app via **Settings** tab or modify `AppConfig.swift`:

```swift
// Confidence thresholds
panelThreshold: 0.3        // Panel detection (30%)
breakerThreshold: 0.4      // Breaker detection (40%)
ocrThreshold: 0.7          // OCR confidence (70%)

// Tracking parameters
dwellFrames: 5             // Stability requirement
cooldownFrames: 30         // Re-detection delay
maxFPS: 10                 // Performance vs battery
```

### Authentication Setup

**Option 1: Local Mode (No Configuration Required)**
- Enable "Local Mode" in app Settings
- No authentication required for basic functionality

**Option 2: Azure Entra ID (Enterprise SSO)**

Update `Models/AuthModels.swift` with your Azure AD credentials:

```swift
entraClientId: "YOUR_AZURE_CLIENT_ID"
entraTenantId: "YOUR_AZURE_TENANT_ID"
entraRedirectURI: "msauth.com.cummingselectrical.panelscanner://auth"
```

**Option 3: AI Assistant Setup (Optional)**

Create `PanelScannerApp/PanelScanner/PanelScanner/Config/APIKeys.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>OpenAI_API_Key</key>
    <string>YOUR_OPENAI_KEY_HERE</string>
    <key>xAI_API_Key</key>
    <string>YOUR_XAI_KEY_HERE</string>
</dict>
</plist>
```

OR enter your API key in app Settings → AI Assistant.

> **Note**: `APIKeys.plist` is gitignored for security. Users must create their own.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Model not loading** | Check `best.mlpackage` target membership in Xcode |
| **Black camera screen** | Grant camera permissions in Settings → Privacy |
| **Authentication fails** | Enable Local Mode or verify Azure/Okta config |
| **Low FPS / Lag** | Reduce Max FPS in Settings, close background apps |
| **OCR not working** | Ensure good lighting, hold device steady |
| **Duplicate detections** | Increase cooldown frames in Settings |


## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** — see the [LICENSE](LICENSE) file for details.

### Why AGPL-3.0?

This project uses **YOLOv8** by Ultralytics, which is licensed under AGPL-3.0. As required by the license terms, any derivative work that incorporates YOLOv8 must also be distributed under AGPL-3.0. This ensures that improvements and modifications remain open source and available to the community.

### Third-Party Licenses

- **YOLOv8** by [Ultralytics](https://github.com/ultralytics/ultralytics) — AGPL-3.0 License
- **Apple Frameworks** (Vision, ARKit, CoreML) — Proprietary Apple Software License

---

## Credits

**Developed by**: Cummings Electrical  
**ML Model**: YOLOv8-Large by [Ultralytics](https://ultralytics.com) (AGPL-3.0)  
**Frameworks**: Apple Vision, ARKit, CoreML, SwiftUI  

---

<div align="center">

**Built with Swift • Powered by CoreML • Made for Electricians**

</div>
