# Next Iteration Analysis

Next Iteration Analysis is an iPhone-first SwiftUI app scaffold for analyzing weightlifting videos. It imports a lift video, captures lift details, tracks a selected or automatically detected plate/bar point, overlays a velocity-colored bar path, estimates movement metrics, generates technique feedback, recommends the next training weight, and saves history locally.

## MVP Features

- Photos video import with local storage and thumbnail generation.
- Lift details form for lift type, weight, unit, reps, RPE, goal, and notes.
- Manual tracking point selection plus an automatic plate-detection service boundary.
- Velocity-colored bar path overlay.
- Basic metrics: displacement, speed, path consistency, technique score, confidence.
- Rule-based critique with an AI-analysis service boundary for full video understanding.
- Next-weight recommendation logic with conservative and aggressive alternatives.
- CSV export and annotated-video export entry points.
- Side-by-side comparison for matching lift types.
- Local history storage.

## Notes

Automatic plate detection, annotated video rendering, and full AI video understanding are scaffolded as replaceable services. The current implementation uses deterministic MVP heuristics so the app can be wired end to end before adding a Core ML detector, optical flow tracker, AVVideoComposition overlay renderer, or remote video-understanding backend.
