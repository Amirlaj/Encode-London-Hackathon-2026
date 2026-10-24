import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

struct ImportedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: target)
            return ImportedVideo(url: target)
        }
    }
}

enum VideoLibrary {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") { return base.appendingPathComponent("ReplayUITests", isDirectory: true) }
        #endif
        return base.appendingPathComponent("Replay", isDirectory: true)
    }
    static var videos: URL { root.appendingPathComponent("Videos", isDirectory: true) }
    static var recordings: URL { root.appendingPathComponent("Recordings", isDirectory: true) }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func importVideo(from source: URL, activity: Activity, moveSource: Bool = false) async throws -> VideoSession {
        try prepare()
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw ReplayError.message("This file does not contain a video track.") }
        let bytes = (try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        try VideoRules.validate(duration: duration, bytes: Int64(bytes))
        let ext = source.pathExtension.lowercased()
        guard ["mov", "mp4", "m4v"].contains(ext) else {
            throw ReplayError.message("Import an MP4 or MOV video. You can export a compatible copy from Photos.")
        }
        let id = UUID()
        let filename = "\(id.uuidString).\(ext)"
        let destination = videos.appendingPathComponent(filename)
        if moveSource { try FileManager.default.moveItem(at: source, to: destination) }
        else { try FileManager.default.copyItem(at: source, to: destination) }
        var thumbnailFilename: String?
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        if let (image, _) = try? await generator.image(at: CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)),
           let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) {
            let thumbnail = "\(id.uuidString).jpg"
            try? data.write(to: videos.appendingPathComponent(thumbnail), options: .atomic)
            thumbnailFilename = thumbnail
        }
        return VideoSession(id: id, createdAt: Date(), title: "\(activity.rawValue) session", activity: activity,
                            goal: "", criteria: "", durationSeconds: duration, byteCount: Int64(bytes),
                            mimeType: ext == "mov" ? "video/quicktime" : "video/mp4",
                            filename: filename, thumbnailFilename: thumbnailFilename)
    }
}
