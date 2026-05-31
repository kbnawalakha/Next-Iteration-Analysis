import Foundation

enum Formatting {
    static func weight(_ value: Double, unit: WeightUnit) -> String {
        "\(value.clean) \(unit.rawValue)"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}

extension Double {
    var clean: String {
        rounded() == self ? String(Int(self)) : String(format: "%.1f", self)
    }
}

extension Date {
    var shortLiftDate: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
