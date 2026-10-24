import AVFoundation
import UIKit
import SwiftUI

final class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    @Published var ready = false
    @Published var recording = false
    @Published var elapsed: Double = 0
    @Published var error: String?
    @Published var hasAudio = true
    @Published var completedURL: URL?

    private let queue = DispatchQueue(label: "com.replay.camera", qos: .userInitiated)
    private let output = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private var startedAt: Date?
    private var configured = false
    private var observation: NSObjectProtocol?

    override init() {
        super.init()
        observation = NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        timer?.invalidate()
    }

    func prepare() async {
        #if targetEnvironment(simulator)
        await MainActor.run { error = "The simulator has no camera. Run Replay on your iPhone to record, or import a video here." }
        return
        #else
        let cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraAllowed else {
            await MainActor.run { error = "Camera access is off. Enable it for Replay in iPhone Settings, then try again." }
            return
        }
        let audioAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run { hasAudio = audioAllowed }
        queue.async { [weak self] in self?.configure(audio: audioAllowed) }
        #endif
    }

    private func configure(audio: Bool) {
        if configured { session.startRunning(); return }
        var configurationOpen = false
        do {
            session.beginConfiguration()
            configurationOpen = true
            session.sessionPreset = .hd1280x720
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw ReplayError.message("The camera is not available right now.")
            }
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw ReplayError.message("Could not start the camera.") }
            session.addInput(input)
            if audio, let microphone = AVCaptureDevice.default(for: .audio), let micInput = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(micInput) {
                session.addInput(micInput)
            }
            guard session.canAddOutput(output) else { throw ReplayError.message("Could not start video recording.") }
            session.addOutput(output)
            output.maxRecordedDuration = CMTime(seconds: 3600, preferredTimescale: 600)
            output.maxRecordedFileSize = 1_950_000_000
            output.minFreeDiskSpaceLimit = 250_000_000
            output.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                let codec: AVVideoCodecType = output.availableVideoCodecTypes.contains(.hevc) ? .hevc : .h264
                var settings: [String: Any] = [AVVideoCodecKey: codec]
                if output.supportedOutputSettingsKeys(for: connection).contains(AVVideoCompressionPropertiesKey) {
                    settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: 2_200_000]
                }
                output.setOutputSettings(settings, for: connection)
            }
            session.commitConfiguration()
            configurationOpen = false
            configured = true
            session.startRunning()
            DispatchQueue.main.async { self.ready = true }
        } catch {
            if configurationOpen { session.commitConfiguration() }
            DispatchQueue.main.async { self.error = error.localizedDescription }
        }
    }

    func start() {
        guard ready, !recording else { return }
        do {
            try VideoLibrary.prepare()
            let capacity = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            guard capacity >= 2_200_000_000 else {
                error = "Free at least 2.2 GB on your iPhone before recording a long session."
                return
            }
        } catch { self.error = "Could not check available storage. Please try again."; return }
        let url = VideoLibrary.recordings.appendingPathComponent("recording-\(UUID().uuidString).mov")
        queue.async { [weak self] in
            guard let self, self.session.isRunning, !self.output.isRecording else { return }
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.output.isRecording else { return }
            self.output.stopRecording()
        }
    }

    func shutDown() {
        stop()
        queue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } }
        timer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.recording = true
            self.elapsed = 0
            self.startedAt = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, let started = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(started)
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.recording = false
            UIApplication.shared.isIdleTimerDisabled = false
            if let error = error as NSError?, error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                self.error = "Recording stopped: \(error.localizedDescription)"
            } else {
                self.completedURL = outputFileURL
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
