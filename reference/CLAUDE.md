# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Open in Xcode
open reference.xcodeproj

# Build via command line
xcodebuild -project reference.xcodeproj -scheme reference -configuration Debug build

# Run tests (when added)
xcodebuild -project reference.xcodeproj -scheme reference test
```

## Architecture

**Reference** is a SwiftUI + SwiftData app for macOS/iOS/visionOS that helps artists manage reference photos with crop regions, rotation, and 3D head pose angles.

### Data Layer
- **SwiftData** for persistence with `Photo` and `Tag` models
- `Photo` stores: filename, normalized crop rect (0.0-1.0), rotation, and optional head rotation (yaw/pitch/roll in degrees)
- Photos saved as JPEGs in `Documents/Photos/` with UUID filenames

### Services
- `PhotoStorageService` - File I/O for image persistence
- `ImageCropService` - Applies crop rect + rotation to image data using CoreGraphics

### Key Views
- `GalleryView` - Main grid with tag and angle filtering, drag-drop import
- `CropView` - Interactive crop editor with rotation handle and 3D head model
- `HeadModelView` - SceneKit 3D head for pose visualization (loads `asaro.obj`)
- `PhotoDetailView` - Single photo view with edit capabilities

### Coordinate System
All crop coordinates are normalized (0.0-1.0) for resolution independence. Head rotation uses Euler angles in degrees with quaternion math for angular distance calculations.

## Cross-Platform

Uses conditional compilation (`#if os(macOS)`) for platform differences:
- NSImage/UIImage
- NSPanGestureRecognizer/UIPanGestureRecognizer
- NSViewRepresentable/UIViewRepresentable

## Data Flow

Import workflow: File picker/drag-drop → CropView (set crop + head angle) → TagSelectionSheet → Save

Filtering: `filteredPhotos` computed property applies tag filter then angle filter (±20° tolerance).
