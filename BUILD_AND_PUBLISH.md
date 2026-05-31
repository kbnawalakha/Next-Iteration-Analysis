# Build and Publish Next Iteration Analysis

## 1. Requirements

- macOS with full Xcode installed.
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
- Automatic plate detection service boundary.
- Velocity-colored bar path overlay.
- Movement metrics.
- Rule-based technique critique.
- Next-weight recommendation.
- Local analysis history.
- CSV export.
- Annotated video export hook.
- Side-by-side comparison.
- AI video-understanding service boundary.

Important MVP notes:

- Automatic plate detection currently uses a heuristic placeholder. Replace `AutomaticPlateDetectionService` with a Vision/Core ML model.
- Bar path tracking currently simulates an end-to-end path. Replace `BarPathTracker` with optical flow, template tracking, or a Core ML detector.
- Annotated video export currently copies the original video. Replace `AnnotatedVideoExportService` with an `AVAssetExportSession` plus `AVVideoCompositionCoreAnimationTool`.
- Full AI video understanding is represented by `AIAnalysisService`. Connect it to a backend before sending raw videos to any model.

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

1. Replace simulated bar tracking with real frame extraction and optical flow.
2. Add Vision body pose extraction with `VNDetectHumanBodyPoseRequest`.
3. Train or integrate a plate/barbell detector for automatic detection.
4. Render annotated video exports with the actual velocity-colored path.
5. Add a backend endpoint for AI critique from structured metrics and optional raw video.
6. Add unit tests for recommendation logic and metrics calculations.
