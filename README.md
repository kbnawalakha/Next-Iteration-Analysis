# Next Iteration Analysis

Next Iteration Analysis is an iPhone-first SwiftUI app scaffold for analyzing weightlifting videos. It imports a lift video, captures lift details, tracks a selected or automatically detected plate/bar point, overlays a velocity-colored bar path, estimates movement metrics, generates technique feedback, recommends the next training weight, and saves history locally.

## MVP Features

- Photos video import with local storage and thumbnail generation.
- Lift details form for lift type, weight, unit, reps, RPE, goal, and notes.
- Manual tracking point selection plus optional Core ML plate detection and automatic plate candidate scoring.
- Velocity-colored bar path overlay.
- Basic metrics: displacement, speed, path consistency, technique score, confidence.
- Rule-based critique with a backend-ready AI-analysis client for full video understanding.
- Next-weight recommendation logic with conservative and aggressive alternatives.
- CSV export and annotated-video export with velocity-colored path rendering.
- Side-by-side comparison for matching lift types.
- Local history storage.
- Vision body pose extraction.
- Unit tests for recommendation and metrics logic.

## Notes

Automatic plate detection, bar tracking, annotated video rendering, and full AI video understanding are implemented behind replaceable services. Bundle `PlateBarbellDetector.mlmodelc` to enable trained plate/barbell detection; otherwise the app falls back to first-frame candidate scoring. The current tracker uses AVFoundation frame extraction plus template matching, which is a practical MVP step before adding a Lucas-Kanade optical flow pipeline.
