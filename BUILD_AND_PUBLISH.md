# Build and Publish Next Iteration Analysis

## 1. Requirements

- macOS with full Xcode 15 or newer installed.
- Xcode command line tools pointed at Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- An Apple Developer account if you want to run on a physical iPhone or submit to TestFlight/App Store.
- A GitHub account if you want to publish the source repo.

## 2. Open the App

Open:

```text
NextIterationAnalysis.xcodeproj
```

In Xcode:

1. Select the `NextIterationAnalysis` project.
2. Select the `NextIterationAnalysis` target.
3. Open `Signing & Capabilities`.
4. Choose your development team.
5. Change the bundle identifier from `com.example.NextIterationAnalysis` to something unique, such as:

```text
com.yourname.NextIterationAnalysis
```

## 3. Run in Simulator

1. Pick an iPhone simulator from the device menu.
2. Press `Cmd + R`.
3. Use the sample history on the home screen or import a video from Photos in a simulator that has media available.

## 4. Run on iPhone

1. Connect your iPhone.
2. Trust the Mac on the device if prompted.
3. Select your iPhone in Xcode.
4. Press `Cmd + R`.
5. Allow Photos access when prompted.

The app already includes these permission strings:

- Photos library access
- Camera access
- Microphone access

## 5. Current Feature Status

Implemented as an end-to-end app scaffold:

- Video import from Photos.
- Lift details form.
- Manual bar/plate point selection.
- Automatic plate detection with optional bundled Core ML model support and first-frame circular contrast fallback.
- Velocity-colored bar path overlay.
- Movement metrics.
- Rule-based technique critique.
- Next-weight recommendation.
- Local analysis history.
- CSV export.
- Annotated MP4 export with the actual velocity-colored path overlay.
- Side-by-side comparison.
- AI video-understanding backend client for structured metrics and optional raw video.
- Vision body pose extraction with `VNDetectHumanBodyPoseRequest`.
- Unit tests for recommendation and metrics logic.

Important MVP notes:

- Automatic plate detection first looks for a bundled `PlateBarbellDetector.mlmodelc`, then falls back to a lightweight on-device candidate scorer.
- Bar path tracking uses AVFoundation frame extraction plus template matching around the selected plate patch. This is suitable for an MVP and can be upgraded to Lucas-Kanade optical flow, Vision tracking, or a Core ML detector.
- Annotated video export uses `AVAssetExportSession` and `AVVideoCompositionCoreAnimationTool` to render the velocity-colored path into an MP4.
- Full AI video understanding is represented by `AIAnalysisService`. It posts structured metrics and pose summary to a backend, and raw video upload remains opt-in.

## 6. Publish to GitHub

Create a new empty GitHub repository named:

```text
NextIterationAnalysis
```

Then run these commands from this folder:

```sh
git remote add origin git@github.com:kbnawalakha/NextIterationAnalysis.git
git push -u origin main
```

If you prefer HTTPS:

```sh
git remote add origin https://github.com/kbnawalakha/NextIterationAnalysis.git
git push -u origin main
```

## 7. Prepare for TestFlight

1. In Xcode, set a real bundle identifier.
2. Add an app icon to `Assets.xcassets/AppIcon.appiconset`.
3. Select `Any iOS Device`.
4. Choose `Product > Archive`.
5. In Organizer, upload the archive to App Store Connect.
6. Create the app record in App Store Connect with the same bundle identifier.
7. Add TestFlight testers.

## 8. Suggested Next Engineering Iterations

1. Replace the template matcher with Lucas-Kanade optical flow or Vision object tracking.
2. Train a plate/barbell detector, compile it as `PlateBarbellDetector.mlmodelc`, and add it to the app bundle.
3. Add richer lift-specific pose rules using the saved `PoseFrame` data.
4. Host the AI critique endpoint and configure `AIAnalysisService` with its URL and API key.
5. Add UI tests around the import, analysis, export, and comparison flows.
