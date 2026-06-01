import Foundation

enum SampleData {
    static let sessions: [LiftSession] = [
        LiftSession(
            id: UUID(),
            createdAt: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now,
            videoURL: nil,
            thumbnailURL: nil,
            videoAspectRatio: 16 / 9,
            liftType: .squat,
            weight: 225,
            unit: .lb,
            reps: 5,
            rpe: 8,
            goal: .strength,
            notes: "Side angle, smooth descent.",
            analysis: LiftAnalysis(
                trackedPath: [],
                poseFrames: [],
                metrics: LiftMetrics(
                    verticalDisplacement: 0.61,
                    horizontalDisplacement: 0.07,
                    averageVelocity: 0.42,
                    peakVelocity: 0.71,
                    minimumVelocity: 0.22,
                    pathConsistencyScore: 82,
                    techniqueScore: 84
                ),
                critique: TechniqueCritique(
                    summary: "Solid set with mild forward drift during the ascent.",
                    positives: ["Depth looked consistent.", "Tempo stayed controlled."],
                    issues: [
                        TechniqueIssue(
                            id: UUID(),
                            title: "Forward bar drift",
                            severity: .medium,
                            explanation: "The path moved forward near mid-ascent, which can reduce efficiency.",
                            cue: "Keep pressure over midfoot and drive straight up."
                        )
                    ],
                    nextSessionFocus: ["Pause squats", "Brace before descent", "Midfoot pressure"]
                ),
                recommendation: WeightRecommendation(
                    suggestedWeight: 225,
                    recommendationType: .repeatLoad,
                    reason: "Repeat this load until the ascent path is cleaner.",
                    conservativeOption: 220,
                    aggressiveOption: 230
                ),
                confidenceScore: 78
            )
        )
    ]
}
