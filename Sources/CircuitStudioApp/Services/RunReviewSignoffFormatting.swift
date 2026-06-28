import Foundation

extension RunReviewService {
    func isPassingStatus(_ status: String) -> Bool {
        switch status.lowercased() {
        case "passed", "pass", "succeeded", "success", "ok", "accepted", "clean", "complete", "completed":
            true
        default:
            false
        }
    }

    func optionalFormatted(_ value: Double?) -> String {
        guard let value else {
            return "nil"
        }
        return formatted(value)
    }

    func formatted(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}
