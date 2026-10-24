import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraManager()
    let onRecorded: (URL) -> Void

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            if camera.ready { CameraPreview(session: camera.session).ignoresSafeArea() }
            LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle())
                    }.disabled(camera.recording).accessibilityLabel("Close camera")
                    Spacer()
                    Label("Record your work", systemImage: "video").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("720p").font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 44, height: 44)
                }
                if camera.recording {
                    HStack(spacing: 9) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text(camera.elapsed.clockString).font(.system(size: 20, weight: .medium, design: .monospaced)).monospacedDigit()
                    }.padding(.horizontal, 20).padding(.vertical, 12).background(.black.opacity(0.35), in: Capsule())
                }
                Spacer()
                if let error = camera.error {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash").font(.system(size: 36, weight: .light))
                        Text(error).font(.body).multilineTextAlignment(.center)
                        Button("Back to review") { dismiss() }.buttonStyle(PrimaryButtonStyle(light: true))
                    }.padding(24).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                } else if !camera.ready {
                    ProgressView("Starting camera…").tint(.white)
                } else if !camera.recording {
                    VStack(spacing: 10) {
                        Image(systemName: "viewfinder").font(.system(size: 42, weight: .ultraLight))
                        Text("Keep the work in view.").font(.title3.weight(.semibold))
                        Text("Show the important steps and the finished result.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    }
                }
                Spacer()
                VStack(spacing: 18) {
                    if !camera.hasAudio { Label("Recording without sound", systemImage: "mic.slash").font(.caption) }
                    Text(camera.recording ? "Keep Replay open. Tap to finish." : "Up to 60 minutes · Keep Replay open")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    Button {
                        if camera.recording { camera.stop() } else { camera.start() }
                    } label: {
                        ZStack {
                            Circle().stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 82, height: 82)
                            if camera.recording {
                                RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 30, height: 30)
                            } else { Circle().fill(.white).frame(width: 68, height: 68) }
                        }
                    }.disabled(!camera.ready || camera.error != nil)
                        .accessibilityLabel(camera.recording ? "Stop recording" : "Start recording")
                    Text(camera.recording ? "RECORDING" : "RECORD")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                }.padding(.bottom, 22)
            }.padding(.horizontal, 24).padding(.top, 12).foregroundStyle(.white)
        }
        .task { await camera.prepare() }
        .onDisappear { camera.shutDown() }
        .onChange(of: camera.completedURL) { _, url in if let url { onRecorded(url) } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { camera.stop() } }
        .interactiveDismissDisabled(camera.recording)
    }
}
