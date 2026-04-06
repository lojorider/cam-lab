# Cam Lab

macOS time-lapse camera app built with SwiftUI and AVFoundation.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.0-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Camera Selection** — choose from built-in or external cameras with live preview
- **Time-lapse Capture** — configurable 1–60 snapshots per minute
- **Output FPS** — export at 24, 30, or 60 FPS
- **HEVC Export** — high-quality H.265 `.mp4` video via `AVAssetWriter`
- **Focus Lock** — lock autofocus to prevent hunting during long captures
- **Auto Cleanup** — temporary frames are cleaned up automatically, even after crashes

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+
- Camera access permission

## Build & Run

```bash
# Clone
git clone https://github.com/lojorider/cam-lab.git
cd cam-lab

# Build
xcodebuild -project CamLab.xcodeproj -scheme CamLab -configuration Debug build

# Run
open ~/Library/Developer/Xcode/DerivedData/CamLab-*/Build/Products/Debug/Cam\ Lab.app
```

Or open `CamLab.xcodeproj` in Xcode and press `Cmd+R`.

## Project Structure

```
cam-lab/
├── CamLab.xcodeproj
├── CamLabApp.swift               # App entry point
├── Info.plist                     # Camera permission
├── CamLab.entitlements            # Sandbox + Camera + File access
├── Assets.xcassets/               # App icon
├── Models/
│   └── CaptureSettings.swift     # Settings, RecordingState, OutputFPS
├── ViewModels/
│   ├── CameraManager.swift       # AVCaptureSession, camera discovery, focus lock
│   └── TimeLapseViewModel.swift  # Recording logic, timer, export orchestration
├── Views/
│   ├── ContentView.swift         # Main layout (preview + sidebar)
│   ├── CameraPreviewView.swift   # NSViewRepresentable for camera preview
│   └── ControlPanelView.swift    # Controls, status dashboard, record button
└── Services/
    └── VideoExporter.swift       # AVAssetWriter HEVC encoder
```

## How It Works

1. **Record** — captures JPEG frames at the configured interval into a temp directory
2. **Export** — stitches all frames into an HEVC `.mp4` at the selected FPS
3. **Save** — prompts to save the video, then cleans up temp files

## License

MIT
