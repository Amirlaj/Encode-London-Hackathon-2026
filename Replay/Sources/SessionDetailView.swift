import SwiftUI
import AVKit

struct SessionDetailView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var title = ""
    @State private var activity = Activity.general
    @State private var goal = ""
    @State private var criteria = ""
    @State private var player: AVPlayer?
    @State private var showSettings = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        Group {
            if let session = store.session(id) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            videoHeader(session).id("video")
                            if let report = session.report {
                                ReportContent(report: report) { seconds in
                                    player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                                    player?.play()
                                    withAnimation { proxy.scrollTo("video", anchor: .top) }
                                }
                            } else if store.activeID == id || session.status.isRemoteBusy || session.status == .uploading || session.status == .paused || session.serverOrigin != nil {
                                progressCard(session)
                            } else { reviewForm(session) }
                            if let message = session.error { ErrorNotice(message: message) }
                            if let error { ErrorNotice(message: error) }
                        }.padding(22).padding(.bottom, 20)
                    }
                }
            } else { ContentUnavailableView("Session not found", systemImage: "video.slash") }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(store.session(id)?.report == nil ? "Your video" : "Your feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Connection settings", systemImage: "slider.horizontal.3") { showSettings = true }
                    Button("Delete session", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .disabled(deleting || store.activeID == id || store.session(id)?.status.isRemoteBusy == true)
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Session options")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .confirmationDialog("Delete this session and its saved video?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                Task {
                    deleting = true
                    defer { deleting = false }
                    do { try await store.delete(id); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .task {
            guard let session = store.session(id) else { return }
            title = session.title; activity = session.activity; goal = session.goal; criteria = session.criteria
            player = AVPlayer(url: store.videoURL(session))
            if session.status.isRemoteBusy { store.review(id) }
        }
        .onDisappear {
            player?.pause()
            store.edit(id, title: title, activity: activity, goal: goal, criteria: criteria)
        }
    }

    private func videoHeader(_ session: VideoSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VideoPlayer(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 22))
            HStack {
                Label("Your video", systemImage: "video")
                Spacer()
                Text("\(session.duration) · \(session.sizeLabel)").monospacedDigit()
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
        }
    }

    private func reviewForm(_ session: VideoSession) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Ready when you are")
                Text("Get feedback\non your work.").font(.system(size: 29, weight: .semibold)).tracking(-1).foregroundStyle(Palette.ink)
            }
            field("Task or expected result (optional)", placeholder: "Describe what you were trying to do…", text: $goal, axis: .vertical)
            Button {
                store.edit(id, title: title, activity: activity, goal: goal, criteria: criteria)
                player?.pause()
                store.review(id)
            } label: {
                Label("Get feedback", systemImage: "sparkles")
            }.buttonStyle(PrimaryButtonStyle()).disabled(store.activeID != nil)
                .accessibilityIdentifier("review-button")
            Text("Your video will be sent to your review server and Google Gemini for analysis. Feedback is based on what can be seen and heard.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
            Button("Connection settings") { showSettings = true }.font(.system(size: 13, weight: .semibold))
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 15)).lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line, lineWidth: 1))
        }
    }

    private func progressCard(_ session: VideoSession) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: session.status.isRemoteBusy ? "sparkles" : "arrow.up.circle")
                        .font(.system(size: 24)).foregroundStyle(Palette.ink)
                    Spacer()
                    if store.activeID == id { ProgressView().tint(Palette.ink) }
                }
                Text(session.status == .draft ? "Starting your review" : session.status.label).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 10) {
                    if session.status == .uploading || session.status == .paused {
                        ProgressView(value: session.progress).tint(Palette.ink)
                        Text("\(Int(session.progress * 100))% uploaded · \(ByteCountFormatter.string(fromByteCount: session.uploadedBytes, countStyle: .file)) of \(session.sizeLabel)")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Text(session.status.isRemoteBusy
                         ? "Looking for mistakes, missed steps, and ways to improve your work. You can leave the app; your review will continue."
                         : "Keep Replay open while uploading. If you leave or lose connection, resume here without starting over.")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3)
                }
                if store.activeID == id && !session.status.isRemoteBusy {
                    Button(session.status == .draft ? "Cancel" : "Pause upload") { store.pause() }.buttonStyle(SecondaryButtonStyle())
                } else if store.activeID == nil {
                    Button(session.status.isRemoteBusy ? "Check for feedback" : session.status == .failed ? "Retry review" : "Resume upload & review") {
                        store.review(id)
                    }.buttonStyle(PrimaryButtonStyle())
                }
                if session.error != nil { Button("Connection settings") { showSettings = true }.font(.subheadline.weight(.semibold)) }
            }
        }
    }
}
