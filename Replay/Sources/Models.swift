import Foundation
import SwiftUI

enum Activity: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    // Retain legacy values so existing saved videos can still be opened.
    case tennis = "Tennis"
    case workout = "Workout"
    case presentation = "Presentation"
    case other = "Something else"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "video"
        case .tennis: return "tennis.racket"
        case .workout: return "figure.strengthtraining.traditional"
        case .presentation: return "person.wave.2"
        case .other: return "sparkles"
        }
    }
}

enum SessionStatus: String, Codable {
    case draft, uploading, paused, queued, processing, analyzing, verifying, complete, failed
    var label: String {
        switch self {
        case .draft: return "Ready to review"
        case .uploading: return "Uploading"
        case .paused: return "Upload paused"
        case .queued: return "In the queue"
        case .processing: return "Preparing video"
        case .analyzing: return "Reviewing your session"
        case .verifying: return "Checking the evidence"
        case .complete: return "Feedback ready"
        case .failed: return "Needs your attention"
        }
    }
    var isRemoteBusy: Bool { [.queued, .processing, .analyzing, .verifying].contains(self) }
}

struct ReviewReport: Codable, Equatable {
    let verdict: String
    let headline: String
    let summary: String
    let confidence: String
    let strengths: [String]
    let improvements: [String]
    let moments: [ReviewMoment]
    let criteria: [ReviewCriterion]
    let nextPractice: String
    let limitations: [String]
    // Older saved reports predate structured issues.
    var issues: [ReviewIssue]? = nil
    var verification: ReviewVerification? = nil

    var verdictLabel: String {
        switch verdict {
        case "on_track": return "On track"
        case "needs_work": return "Needs attention"
        default: return "Not enough evidence"
        }
    }
}

struct ReviewVerification: Codable, Equatable {
    let status: String
    let model: String
    let candidateIssueCount: Int
    let confirmedIssueCount: Int
    let removedIssueCount: Int
    let summary: String
    let completedAt: String
    var decisions: [VerificationDecision]? = nil
}

struct VerificationDecision: Codable, Identifiable, Equatable {
    let candidateIndex: Int
    let decision: String
    let reason: String
    var id: Int { candidateIndex }

    var label: String {
        switch decision {
        case "confirmed": return "Supported by the video"
        case "unsupported": return "Removed — not supported"
        default: return "Removed — uncertain"
        }
    }
}

struct ReviewIssue: Codable, Identifiable, Equatable {
    let seconds: Double?
    let title: String
    let observation: String
    let whyItMatters: String
    let howToFix: String
    var id: String { "\(seconds ?? -1)-\(title)" }
}

struct ReviewMoment: Codable, Identifiable, Equatable {
    let seconds: Double
    let title: String
    let observation: String
    let suggestion: String
    let kind: String
    var id: String { "\(seconds)-\(title)" }
}

struct ReviewCriterion: Codable, Identifiable, Equatable {
    let name: String
    let assessment: String
    let evidence: String
    var id: String { name }
    var label: String {
        switch assessment {
        case "met": return "Met"
        case "partly_met": return "Partly met"
        case "not_met": return "Needs work"
        default: return "Not visible"
        }
    }
}

struct VideoSession: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var title: String
    var activity: Activity
    var goal: String
    var criteria: String
    let durationSeconds: Double
    let byteCount: Int64
    let mimeType: String
    let filename: String
    let thumbnailFilename: String?
    var status: SessionStatus = .draft
    var uploadedBytes: Int64 = 0
    var serverOrigin: String?
    var report: ReviewReport?
    var error: String?

    var progress: Double { byteCount > 0 ? min(1, Double(uploadedBytes) / Double(byteCount)) : 0 }
    var duration: String { durationSeconds.clockString }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
}

struct RemoteSession: Decodable {
    let id: String
    let status: SessionStatus
    let byteCount: Int64
    let uploadedBytes: Int64
    let report: ReviewReport?
    let error: String?
}

struct ServerConfiguration: Decodable {
    let configured: Bool
    let model: String
    let maxBytes: Int64
    let maxDurationSeconds: Int
    let chunkBytes: Int
}

extension Double {
    var clockString: String {
        let total = max(0, Int(isFinite ? self : 0))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

enum ReplayError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

enum VideoRules {
    static let maxBytes: Int64 = 2_000_000_000
    static let maxDuration: Double = 3600

    static func validate(duration: Double, bytes: Int64) throws {
        guard duration.isFinite, duration > 0, bytes > 0 else {
            throw ReplayError.message("This video is empty or could not be read. Choose another recording.")
        }
        guard duration <= maxDuration + 1 else {
            throw ReplayError.message("Choose a video up to 60 minutes long, or trim it in Photos first.")
        }
        guard bytes <= maxBytes else {
            throw ReplayError.message("This video is larger than 2 GB. Export a 720p copy or trim it in Photos, then import it again.")
        }
    }
}

extension ReviewReport {
    static let example = ReviewReport(
        verdict: "needs_work",
        headline: "Check the alignment before moving on.",
        summary: "In this example assembly task, the panel is secured while its edges are uneven. The final check also leaves the back of the assembly out of view.",
        confidence: "medium",
        strengths: ["The parts are laid out before assembly begins."],
        improvements: ["Check that the panel edges line up before securing them.", "Show the completed assembly from both sides during the final check."],
        moments: [
            ReviewMoment(seconds: 15, title: "Parts prepared", observation: "The parts are arranged before the first step.", suggestion: "Keep this preparation for the next task.", kind: "strength"),
            ReviewMoment(seconds: 42, title: "Uneven panel edges", observation: "The panel is secured while one edge sits higher than the other.", suggestion: "Align the edges before securing the panel.", kind: "improvement"),
            ReviewMoment(seconds: 138, title: "Final check is incomplete", observation: "Only the front of the finished assembly is shown.", suggestion: "Check and show both sides before calling the task complete.", kind: "improvement")
        ],
        criteria: [
            ReviewCriterion(name: "Parts aligned before fastening", assessment: "not_met", evidence: "The panel edges are visibly uneven at 00:42."),
            ReviewCriterion(name: "Completed result checked", assessment: "not_visible", evidence: "The recording does not show the back of the assembly.")
        ],
        nextPractice: "Recheck the panel alignment, then show both sides of the finished work in one clear shot.",
        limitations: ["This is a sample report, not an analysis of your video.", "The back of the assembly cannot be assessed from this camera angle."],
        issues: [
            ReviewIssue(seconds: 42, title: "The panel was secured out of alignment", observation: "One edge sits higher than the adjoining panel when it is fastened.", whyItMatters: "An uneven fit can prevent the next part from lining up correctly.", howToFix: "Check the instructions, align both edges, and verify the fit before securing the panel."),
            ReviewIssue(seconds: 138, title: "The final check does not show the whole result", observation: "The recording ends after showing only the front.", whyItMatters: "The back connections cannot be verified from the available footage.", howToFix: "Inspect the completed work from both sides and include that check in the recording.")
        ]
    )
}
