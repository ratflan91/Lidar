# LiDAR Depth Mapper

A real-time iOS app that overlays a topographic depth map on the live camera feed using the device's LiDAR scanner.

## Features

| Feature | Detail |
|---|---|
| **Gradient mode** | Camera + full color-ramp depth overlay (red = near, blue = far) |
| **Contour mode** | Camera + topographic contour bands every 0.3 m |
| **Combined mode** | Gradient overlay with contour lines on top |
| **Camera Only** | Raw camera feed, no overlay |
| **Depth readout** | Center-point distance displayed live (color-coded) |
| **Freeze** | Pause the AR session to inspect a captured frame |

## Requirements

- **Device**: iPhone 12 Pro / 13 Pro / 14 Pro / 15 Pro (any), or iPad Pro with LiDAR (2020+)
- **iOS**: 15.0 or later
- **Xcode**: 15 or later
- **XcodeGen** (recommended): `brew install xcodegen`

## Building

### Option A — XcodeGen (recommended)

```bash
# 1. Install XcodeGen if you haven't
brew install xcodegen

# 2. Generate the Xcode project
cd path/to/LidarDepthMapper-repo
xcodegen generate

# 3. Open and run
open LidarDepthMapper.xcodeproj
```

Select your device in Xcode, set your Apple Developer Team under  
**Signing & Capabilities**, then press **Run**.

### Option B — Manual Xcode project

1. Open Xcode → **File › New › Project** → **App**  
2. Product name: `LidarDepthMapper`, Interface: **Storyboard** (we replace AppDelegate anyway)  
3. Delete the generated `ViewController.swift`, `Main.storyboard`, `LaunchScreen.storyboard`  
4. Drag all files from `LidarDepthMapper/` into the project  
5. In **Build Phases › Compile Sources** confirm `Shaders.metal` is listed  
6. Under **General › Frameworks, Libraries…** add `ARKit`, `Metal`, `MetalKit`  
7. Set **Deployment Target** to iOS 15.0  

## Architecture

```
AppDelegate.swift        — Creates UIWindow + ViewController
ViewController.swift     — ARSession delegate, UI controls, depth label
DepthMapRenderer.swift   — MTKViewDelegate; manages Metal textures & uniforms
Shaders.metal            — Vertex passthrough + fragment depth visualizer
```

### Data flow

```
ARFrame ──► capturedImage (YCbCr CVPixelBuffer)
         │        └─► Y + CbCr Metal textures
         └► smoothedSceneDepth.depthMap (Float32 CVPixelBuffer)
                  └─► depth Metal texture

Per draw call:
  vertex shader  — full-screen quad, passes display-transformed UV
  fragment shader — YCbCr→RGB camera, depth→topographic color, contour edges
```

### Depth color scale

| Color  | Range     |
|--------|-----------|
| Red    | 0 – 1 m   |
| Orange | 1 – 2 m   |
| Yellow | 2 – 3 m   |
| Green  | 3 – 4 m   |
| Blue   | 4 – 5 m   |

Beyond 5 m the depth overlay fades out (configurable via `maxDepth` in `DepthMapRenderer`).

## Customisation

- **`maxDepth`** (default `5.0` m) — maximum depth mapped to the far end of the color ramp  
- **`alpha`** (default `0.70`) — opacity of the depth overlay (0 = transparent, 1 = opaque)  
- **`contourInterval`** (default `0.30` m) — spacing between contour lines  

All three are `Float` fields in `DepthMapRenderer.Uniforms` and are uploaded to the GPU each frame.
