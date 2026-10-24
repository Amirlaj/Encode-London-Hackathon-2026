import XCTest
import AVFoundation
@testable import Replay

final class ReplayTests: XCTestCase {
    func testHourLongVideoWithinUploadLimitIsAccepted() throws {
        XCTAssertNoThrow(try VideoRules.validate(duration: 3600, bytes: 1_100_000_000))
        XCTAssertThrowsError(try VideoRules.validate(duration: 3602, bytes: 1_100_000_000))
        XCTAssertThrowsError(try VideoRules.validate(duration: 300, bytes: 2_000_000_001))
        XCTAssertThrowsError(try VideoRules.validate(duration: .nan, bytes: 10))
        XCTAssertThrowsError(try VideoRules.validate(duration: 0, bytes: 10))
    }

    func testConnectionRequiresHTTPSOutsideLocalNetwork() throws {
        XCTAssertNoThrow(try APIClient(address: "https://coach.example.com", token: "test-token"))
        XCTAssertNoThrow(try APIClient(address: "http://192.168.1.10:8787", token: "test-token"))
        XCTAssertNoThrow(try APIClient(address: "http://172.16.1.10:8787", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "http://coach.example.com", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "http://172.40.0.2:8787", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "http://10.attacker.example", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "http://192.168.attacker.example", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "http://10.1.2.3.attacker.example", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "https://user:pass@coach.example.com", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "https://coach.example.com?token=secret", token: "test-token"))
        XCTAssertThrowsError(try APIClient(address: "https://coach.example.com", token: ""))
    }

    func testSessionPreservesResumeStateAndReport() throws {
        var session = VideoSession(id: UUID(), createdAt: Date(), title: "Forehand", activity: .tennis,
                                   goal: "Recover earlier", criteria: "Return to the centre", durationSeconds: 3600,
                                   byteCount: 1_100_000_000, mimeType: "video/quicktime", filename: "video.mov", thumbnailFilename: nil)
        session.uploadedBytes = 100_000_000
        session.serverOrigin = "https://coach.example.com"
        session.status = .paused
        session.report = .example
        let restored = try JSONDecoder().decode(VideoSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.uploadedBytes, 100_000_000)
        XCTAssertEqual(restored.serverOrigin, session.serverOrigin)
        XCTAssertEqual(restored.status, .paused)
        XCTAssertEqual(restored.report, .example)
        XCTAssertEqual(restored.duration, "1:00:00")
    }

    func testProblemDetailsRoundTripAndOlderReportsStillOpen() throws {
        let encoded = try JSONEncoder().encode(ReviewReport.example)
        let current = try JSONDecoder().decode(ReviewReport.self, from: encoded)
        XCTAssertEqual(current.issues?.first?.seconds, 42)
        XCTAssertFalse(try XCTUnwrap(current.issues?.first?.howToFix).isEmpty)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "issues")
        let restored = try JSONDecoder().decode(ReviewReport.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.issues)
        XCTAssertEqual(restored.improvements, ReviewReport.example.improvements)
    }

    func testTimestampFormattingAndUnknownVerdict() {
        XCTAssertEqual(42.0.clockString, "00:42")
        XCTAssertEqual(3599.0.clockString, "59:59")
        XCTAssertEqual(Double.infinity.clockString, "00:00")
        XCTAssertEqual((-5.0).clockString, "00:00")
    }

    func testImportCopiesPlayableVideoAndCreatesThumbnail() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("replay-test-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: source) }
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame), 180, CVPixelBufferGetDataSize(frame))
        CVPixelBufferUnlockBaseAddress(frame, [])
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(index), timescale: 15)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 600))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let imported = try await VideoLibrary.importVideo(from: source, activity: .tennis)
        let copied = VideoLibrary.videos.appendingPathComponent(imported.filename)
        defer {
            try? FileManager.default.removeItem(at: copied)
            if let name = imported.thumbnailFilename { try? FileManager.default.removeItem(at: VideoLibrary.videos.appendingPathComponent(name)) }
        }
        XCTAssertEqual(imported.durationSeconds, 2, accuracy: 0.1)
        XCTAssertGreaterThan(imported.byteCount, 0)
        XCTAssertEqual(imported.mimeType, "video/quicktime")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertNotNil(imported.thumbnailFilename)
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: copied))
        let moved = try await VideoLibrary.importVideo(from: source, activity: .tennis, moveSource: true)
        defer {
            try? FileManager.default.removeItem(at: VideoLibrary.videos.appendingPathComponent(moved.filename))
            if let name = moved.thumbnailFilename { try? FileManager.default.removeItem(at: VideoLibrary.videos.appendingPathComponent(name)) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotNil(moved.thumbnailFilename)
        XCTAssertEqual(moved.durationSeconds, 2, accuracy: 0.1)
    }

    func testInvalidRecordingIsKeptForRecovery() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-recording-\(UUID().uuidString).mov")
        try Data("unfinished video".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        do {
            _ = try await VideoLibrary.importVideo(from: source, activity: .tennis, moveSource: true)
            XCTFail("An invalid recording should be rejected")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }
}
