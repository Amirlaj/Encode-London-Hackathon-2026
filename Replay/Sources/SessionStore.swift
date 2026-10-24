import Foundation
import SwiftUI
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [VideoSession] = []
    @Published var storageError: String?
    @Published var importing = false
    @Published private(set) var activeID: UUID?
    @Published var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "serverAddress") }
    }
    private var operation: Task<Void, Never>?
    private var recoveredRecordings = false
    private let indexURL = VideoLibrary.root.appendingPathComponent("sessions.json")

    init() {
        #if targetEnvironment(simulator)
        let defaultAddress = "http://127.0.0.1:8787"
        #else
        let defaultAddress = ""
        #endif
        serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? defaultAddress
        do {
            try VideoLibrary.prepare()
            if FileManager.default.fileExists(atPath: indexURL.path) {
                sessions = try JSONDecoder().decode([VideoSession].self, from: Data(contentsOf: indexURL))
                for index in sessions.indices where sessions[index].status == .uploading {
                    sessions[index].status = .paused
                }
            }
        } catch { storageError = "Your saved sessions could not be read. \(error.localizedDescription)" }
    }

    func session(_ id: UUID) -> VideoSession? { sessions.first { $0.id == id } }
    func videoURL(_ session: VideoSession) -> URL { VideoLibrary.videos.appendingPathComponent(session.filename) }
    func thumbnailURL(_ session: VideoSession) -> URL? {
        session.thumbnailFilename.map { VideoLibrary.videos.appendingPathComponent($0) }
    }

    private func save() {
        do { try JSONEncoder().encode(sessions).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { storageError = "Replay could not save your session. Free some storage and try again." }
    }

    private func update(_ id: UUID, _ change: (inout VideoSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
        save()
    }

    func addVideo(_ url: URL, activity: Activity, removeSource: Bool = false) async throws -> UUID {
        importing = true
        defer { importing = false }
        let session = try await Task.detached(priority: .userInitiated) {
            try await VideoLibrary.importVideo(from: url, activity: activity, moveSource: removeSource)
        }.value
        sessions.insert(session, at: 0)
        save()
        return session.id
    }

    func recoverRecordings() async {
        guard !recoveredRecordings else { return }
        recoveredRecordings = true
        let files = (try? FileManager.default.contentsOfDirectory(at: VideoLibrary.recordings, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "mov" {
            do { _ = try await addVideo(file, activity: .general, removeSource: true) }
            catch { storageError = "An interrupted recording could not be recovered. Its original file has been kept on this iPhone." }
        }
    }

    func edit(_ id: UUID, title: String, activity: Activity, goal: String, criteria: String) {
        update(id) { session in
            guard session.serverOrigin == nil else { return }
            session.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            if session.title.isEmpty { session.title = activity == .general ? "Video review" : "\(activity.rawValue) session" }
            session.activity = activity
            session.goal = String(goal.prefix(2000))
            session.criteria = String(criteria.prefix(4000))
        }
    }

    func review(_ id: UUID) {
        guard operation == nil, session(id) != nil else { return }
        activeID = id
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.operation = nil; self.activeID = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let client = try APIClient(address: serverAddress, token: TokenStore.read())
                let configuration = try await client.configuration()
                guard configuration.configured else {
                    throw ReplayError.message("The server is connected. Add GEMINI_API_KEY to its .env file to turn on reviews.")
                }
                guard let saved = session(id) else { return }
                if let origin = saved.serverOrigin, origin != client.baseURL.absoluteString {
                    throw ReplayError.message("This session belongs to a different server. Restore its address in Settings to resume.")
                }
                update(id) { $0.error = nil }
                var remote: RemoteSession
                if saved.serverOrigin != nil {
                    do { remote = try await client.status(id) }
                    catch let error as APIError where error.status == 404 {
                        remote = try await client.create(saved)
                    }
                } else {
                    remote = try await client.create(saved)
                    update(id) { $0.serverOrigin = client.baseURL.absoluteString }
                }
                apply(remote, to: id)
                if remote.status == .uploading {
                    UIApplication.shared.isIdleTimerDisabled = true
                    let file = try FileHandle(forReadingFrom: videoURL(saved))
                    defer { try? file.close() }
                    let chunkSize = min(max(1, configuration.chunkBytes), 8 * 1024 * 1024)
                    var failures = 0
                    while remote.uploadedBytes < saved.byteCount {
                        try Task.checkCancellation()
                        try file.seek(toOffset: UInt64(remote.uploadedBytes))
                        guard let data = try file.read(upToCount: chunkSize), !data.isEmpty else {
                            throw ReplayError.message("The saved video could not be read. Import the original again.")
                        }
                        do {
                            remote = try await client.upload(id, data: data, offset: remote.uploadedBytes)
                            failures = 0
                            apply(remote, to: id)
                        } catch {
                            try Task.checkCancellation()
                            failures += 1
                            guard failures <= 3 else { throw error }
                            // A lost response can still mean the bytes reached the server.
                            try await Task.sleep(for: .seconds(failures * 2))
                            remote = try await client.status(id)
                            apply(remote, to: id)
                        }
                    }
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                try Task.checkCancellation()
                if remote.status == .uploading || remote.status == .failed {
                    remote = try await client.analyze(id)
                    apply(remote, to: id)
                }
                var consecutiveErrors = 0
                while remote.status.isRemoteBusy {
                    try await Task.sleep(for: .seconds(4))
                    do {
                        remote = try await client.status(id)
                        consecutiveErrors = 0
                        apply(remote, to: id)
                    } catch {
                        try Task.checkCancellation()
                        consecutiveErrors += 1
                        if consecutiveErrors >= 3 { throw error }
                    }
                }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    update(id) { if $0.status == .uploading { $0.status = .paused } }
                } else {
                    update(id) {
                        if !$0.status.isRemoteBusy { $0.status = $0.serverOrigin != nil ? .paused : .draft }
                        $0.error = error.localizedDescription
                    }
                }
            }
        }
    }

    private func apply(_ remote: RemoteSession, to id: UUID) {
        update(id) {
            $0.status = remote.status
            $0.uploadedBytes = remote.uploadedBytes
            $0.report = remote.report
            $0.error = remote.error
        }
    }

    func pause() { operation?.cancel() }
    func resumeReviews() {
        if operation == nil, let pending = sessions.first(where: { $0.status.isRemoteBusy }) { review(pending.id) }
    }

    func delete(_ id: UUID) async throws {
        guard let saved = session(id), activeID != id, !saved.status.isRemoteBusy else {
            throw ReplayError.message("Pause the upload or wait for the review to finish before removing this session.")
        }
        if let origin = saved.serverOrigin {
            let client = try APIClient(address: origin, token: TokenStore.read())
            do { try await client.delete(id) }
            catch let error as APIError where error.status == 404 { /* Already expired on the server. */ }
        }
        try? FileManager.default.removeItem(at: videoURL(saved))
        if let thumbnail = thumbnailURL(saved) { try? FileManager.default.removeItem(at: thumbnail) }
        sessions.removeAll { $0.id == id }
        save()
    }
}
