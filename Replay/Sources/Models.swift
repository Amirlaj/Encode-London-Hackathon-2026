import Foundation
import SwiftUI

enum Activity: String, CaseIterable, Identifiable, Codable {
    case tennis = "Tennis"
    case workout = "Workout"
    case presentation = "Presentation"
    case other = "Something else"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .tennis: return "tennis.racket"
        case .workout: return "figure.strengthtraining.traditional"
        case .presentation: return "person.wave.2"
        case .other: return "sparkles"
        }
    }
    var placeholder: String {
        switch self {
        case .tennis: return "Help me improve my forehand and recovery between shots."
        case .workout: return "Check my technique and consistency throughout the session."
        case .presentation: return "Check whether my explanation is clear and well paced."
        case .other: return "Describe the task and what a good result looks like."
        }
    }
}

enum SessionStatus: String, Codable {
    case draft, uploading, paused, queued, processing, analyzing, complete, failed
    var label: String {
        switch self {
        case .draft: return "Ready to review"
        case .uploading: return "Uploading"
        case .paused: return "Upload paused"
        case .queued: return "In the queue"
        case .processing: return "Preparing video"
        case .analyzing: return "Reviewing your session"
        case .complete: return "Feedback ready"
        case .failed: return "Needs your attention"
        }
    }
    var isRemoteBusy: Bool { [.queued, .processing, .analyzing].contains(self) }
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

    var verdictLabel: String {
        switch verdict {
        case "on_track": return "On track"
        case "needs_work": return "Room to improve"
        default: return "Not enough evidence"
        }
    }
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
        headline: "A strong start. A steadier finish.",
        summary: "In this illustrative tennis report, early preparation helps the player find a clean contact point. Recovering sooner after each shot is the next thing to work on.",
        confidence: "medium",
        strengths: ["Good shoulder turn before the forward swing.", "Balanced contact on the slower incoming balls."],
        improvements: ["Recover toward the centre immediately after the follow-through.", "Start the split step as the opponent makes contact."],
        moments: [
            ReviewMoment(seconds: 42, title: "Early preparation", observation: "The racket is prepared before the ball bounces.", suggestion: "Keep this same preparation on faster balls.", kind: "strength"),
            ReviewMoment(seconds: 138, title: "A late recovery", observation: "The player stays wide after the forehand.", suggestion: "Use two quick recovery steps before the next shot.", kind: "improvement"),
            ReviewMoment(seconds: 265, title: "Better balance", observation: "A wider base keeps the body stable through contact.", suggestion: "Repeat this setup as the rally gets longer.", kind: "strength")
        ],
        criteria: [
            ReviewCriterion(name: "Preparation before contact", assessment: "met", evidence: "An early shoulder turn is visible in the example rally."),
            ReviewCriterion(name: "Recovery after each shot", assessment: "partly_met", evidence: "Recovery is less consistent when pulled wide.")
        ],
        nextPractice: "Try five minutes of forehand, recover, split step. Focus on getting ready for the next ball before adding power.",
        limitations: ["This is a sample report, not an analysis of your video.", "A single camera angle cannot show every detail of the racket or ball."]
    )
}
