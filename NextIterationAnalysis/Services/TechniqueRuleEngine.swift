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

        if let efficiency = metrics.pathEfficiency, efficiency < 0.72 {
            issues.append(issue(
                "Inefficient bar path",
                .medium,
                "The tracked plate traveled much farther than the straight line between start and finish, which suggests a loop or S-curve.",
                "Aim for a cleaner vertical line and keep the plate from swinging around the strongest path."
            ))
            focus.append("Path efficiency")
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
            if let horizontal = metrics.horizontalDisplacement, horizontal > 0.06 {
                issues.append(issue("Forward drift", .medium, "The plate center shifted horizontally during the squat, a common sign of pressure moving toward the toes or heels.", "Keep pressure over midfoot and let the bar travel straight over the base of support."))
            }
            if metrics.techniqueScore < 78 {
                issues.append(issue("Squat timing check", .medium, "The path suggests a possible shift during the ascent.", "Brace hard and drive chest and hips together."))
            }
        case .benchPress:
            focus.append("Touch point consistency")
            if let horizontal = metrics.horizontalDisplacement, horizontal > 0.07 {
                issues.append(issue("Excessive horizontal travel", .medium, "The press path moved horizontally enough to suggest an inconsistent touch point or press-back angle.", "Touch the same point each rep and press back toward the rack without overcorrecting."))
            }
            if metrics.techniqueScore < 78 {
                issues.append(issue("Bench path consistency", .medium, "The press path appears less consistent than ideal.", "Touch in the same spot and press back toward the rack."))
            }
        case .deadlift:
            focus.append("Bar close to body")
            if let horizontal = metrics.horizontalDisplacement, horizontal > 0.06 {
                issues.append(issue("Bar drifting away", .high, "The plate center moved away from the start line, which often means the bar is drifting away from the body.", "Pull the slack out, keep lats tight, and sweep the bar back toward your legs."))
            }
            if metrics.techniqueScore < 78 {
                issues.append(issue("Deadlift drift", .medium, "The bar appears to drift away from the start point.", "Sweep the bar toward your legs as it leaves the floor."))
            }
        case .overheadPress:
            focus.append("Head-through lockout")
            if let efficiency = metrics.pathEfficiency, efficiency < 0.78 {
                issues.append(issue("Looping press path", .medium, "The path efficiency suggests the bar may be looping around the face instead of returning to a straight lockout line.", "Move your head back just enough for the bar to pass, then bring your head through under the bar."))
            }
            if metrics.techniqueScore < 78 {
                issues.append(issue("Press path loop", .medium, "The path may be looping around the face.", "Move your head back, press straight, then bring your head through."))
            }
        case .clean, .snatch:
            focus.append("Vertical extension path")
            if let horizontal = metrics.horizontalDisplacement, horizontal > 0.09 {
                issues.append(issue("Forward swing", .medium, "The plate center moved forward through the pull, which can create an inefficient looping trajectory.", "Stay balanced through midfoot and keep extension vertical before pulling under."))
            }
            if let efficiency = metrics.pathEfficiency, efficiency < 0.76 {
                issues.append(issue("Inefficient S-curve", .medium, "The path looks less direct than ideal for an Olympic lift.", "Keep the bar close and avoid letting it swing away after contact."))
            }
        default:
            focus.append("Consistent setup")
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
