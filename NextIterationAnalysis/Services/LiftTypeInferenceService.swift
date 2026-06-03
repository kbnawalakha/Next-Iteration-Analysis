import Foundation

final class LiftTypeInferenceService {
    func inferLiftType(
        selectedLiftType: LiftType,
        path: [TrackedPoint],
        poseFrames: [PoseFrame]
    ) -> LiftType {
        guard selectedLiftType.isVideoInferred else { return selectedLiftType }
        guard path.count > 2 else { return .other }

        let first = path.first ?? path[0]
        let last = path.last ?? path[path.count - 1]
        let ys = path.map(\.y)
        let verticalRange = (ys.max() ?? first.y) - (ys.min() ?? first.y)
        let netVertical = first.y - last.y
        let averageY = ys.reduce(0, +) / Double(max(ys.count, 1))
        let startsVeryHigh = first.y < 0.28
        let staysVeryHigh = averageY < 0.30

        if averageY > 0.62, netVertical > 0.08 {
            return .deadlift
        }

        if poseFrames.contains(where: hasHorizontalTorso), verticalRange > 0.06 {
            return .benchPress
        }

        if verticalRange > 0.10, !startsVeryHigh {
            return .squat
        }

        if staysVeryHigh, verticalRange > 0.08 {
            return .overheadPress
        }

        if verticalRange > 0.12 {
            return .squat
        }

        return .other
    }

    private func hasHorizontalTorso(_ frame: PoseFrame) -> Bool {
        guard let leftShoulder = frame.joints["leftShoulder"] ?? frame.joints["VNHumanBodyPoseObservationJointNameLeftShoulder"],
              let rightShoulder = frame.joints["rightShoulder"] ?? frame.joints["VNHumanBodyPoseObservationJointNameRightShoulder"],
              let leftHip = frame.joints["leftHip"] ?? frame.joints["VNHumanBodyPoseObservationJointNameLeftHip"],
              let rightHip = frame.joints["rightHip"] ?? frame.joints["VNHumanBodyPoseObservationJointNameRightHip"] else {
            return false
        }

        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let hipY = (leftHip.y + rightHip.y) / 2
        return abs(shoulderY - hipY) < 0.18
    }
}
