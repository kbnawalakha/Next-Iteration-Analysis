import Foundation

final class TechniqueRuleEngine {
    func critique(details: LiftDetails, metrics: LiftMetrics, trackingMode: TrackingMode) -> TechniqueCritique {
        var positives = ["Rep count and load were captured for progression tracking."]
        var issues: [TechniqueIssue] = []
        var focus = ["Repeat the camera setup for comparable data."]

        if (metrics.pathConsistencyScore) >= 85 {
            positives.append("The bar path stayed fairly consistent.")
        }

        if let horizontal = metrics.horizontalDisplacement, horizontal > 0.08 {
            issues.append(issue(
                "Horizontal bar drift",
                .medium,
                "The tracked point moved laterally enough to suggest the lift may be drifting off its strongest line.",
                "Keep pressure balanced and think about moving the bar through the same vertical window."
            ))
            focus.append("Bar path control")
        }

        if let minVelocity = metrics.minimumVelocity, let peakVelocity = metrics.peakVelocity, peakVelocity > 0, minVelocity / peakVelocity < 0.35 {
            issues.append(issue(
                "Possible sticking point",
                .low,
                "Velocity appears to slow sharply during part of the rep.",
                "Use pauses or tempo work around the slowest range."
            ))
            focus.append("Sticking point strength")
        }

        switch details.liftType {
        case .squat:
            focus.append("Depth and hip-shoulder timing")
            if metrics.techniqueScore < 78 {
                issues.append(issue("Squat timing check", .medium, "The path suggests a possible shift during the ascent.", "Brace hard and drive chest and hips together."))
            }
        case .benchPress:
            focus.append("Touch point consistency")
            if metrics.techniqueScore < 78 {
                issues.append(issue("Bench path consistency", .medium, "The press path appears less consistent than ideal.", "Touch in the same spot and press back toward the rack."))
            }
        case .deadlift:
            focus.append("Bar close to body")
            if metrics.techniqueScore < 78 {
                issues.append(issue("Deadlift drift", .medium, "The bar appears to drift away from the start point.", "Sweep the bar toward your legs as it leaves the floor."))
            }
        case .overheadPress:
            focus.append("Head-through lockout")
            if metrics.techniqueScore < 78 {
                issues.append(issue("Press path loop", .medium, "The path may be looping around the face.", "Move your head back, press straight, then bring your head through."))
            }
        default:
            focus.append("Consistent setup")
        }

        if trackingMode == .automaticPlateDetection {
            issues.append(issue(
                "Auto detection confidence",
                .low,
                "Automatic plate detection is in MVP mode and may need manual correction.",
                "Review the selected start point before trusting the numbers."
            ))
        }

        let summary = issues.isEmpty
            ? "This set looked controlled from the available tracking data."
            : "The lift is analyzable, with the main opportunity around bar path consistency."

        return TechniqueCritique(
            summary: summary,
            positives: positives,
            issues: issues,
            nextSessionFocus: Array(Set(focus)).sorted()
        )
    }

    private func issue(_ title: String, _ severity: IssueSeverity, _ explanation: String, _ cue: String) -> TechniqueIssue {
        TechniqueIssue(id: UUID(), title: title, severity: severity, explanation: explanation, cue: cue)
    }
}
