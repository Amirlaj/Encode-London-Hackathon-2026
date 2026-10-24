import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var selectedTab = 0
    @State private var taskDescription = ""
    @State private var taskCriteria = ""
    @State private var path: [UUID] = []
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var showExample = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    header
                    if selectedTab == 0 { home } else { library }
                    if let error { ErrorNotice(message: error) }
                    if let error = store.storageError { ErrorNotice(message: error) }
                }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .navigationDestination(for: UUID.self) { id in SessionDetailView(id: id) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .sheet(isPresented: $showExample) { ExampleReportView() }
            .fullScreenCover(isPresented: $showCamera) {
                RecordingView { url in
                    showCamera = false
                    importVideo(url, removeSource: true)
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    Task {
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        do { try await prepareReview(url, removeSource: false) }
                        catch { self.error = error.localizedDescription }
                    }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    store.importing = true
                    defer { store.importing = false; photoItem = nil }
                    do {
                        guard let video = try await item.loadTransferable(type: ImportedVideo.self) else {
                            throw ReplayError.message("This video could not be imported. Try choosing it from Files.")
                        }
                        try await prepareReview(video.url, removeSource: true)
                    } catch { self.error = error.localizedDescription }
                }
            }
            .overlay {
                if store.importing {
                    ZStack {
                        Palette.ink.opacity(0.22).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().tint(Palette.ink)
                            Text("Getting your video ready").font(.headline)
                            Text("Long videos can take a moment.").font(.subheadline).foregroundStyle(Palette.muted)
                        }.padding(28).background(Palette.background, in: RoundedRectangle(cornerRadius: 24))
                    }.accessibilityIdentifier("import-progress")
                }
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "play.square.stack.fill").font(.system(size: 24, weight: .semibold))
                Text("replay").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-1.2)
            }.foregroundStyle(Palette.ink).accessibilityElement(children: .combine)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.ink).frame(width: 44, height: 44)
                    .background(.white, in: Circle()).overlay(Circle().stroke(Palette.line, lineWidth: 1))
            }.accessibilityLabel("Settings").accessibilityIdentifier("settings-button")
        }
    }

    private var home: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Feedback on your work")
                Text("See what\nneeds fixing.")
                    .font(.system(size: 37, weight: .semibold)).tracking(-1.6).lineSpacing(-1)
                    .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                Text("Upload a video of any task. Find out what went wrong and how to improve it.")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(4)
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("What is the task?").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("Optional").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    TextField("Describe the work or the result you wanted…", text: $taskDescription, axis: .vertical)
                        .font(.system(size: 14)).lineLimit(2...4)
                        .accessibilityIdentifier("task-description")
                        .onChange(of: taskDescription) { _, value in
                            if value.count > 2000 { taskDescription = String(value.prefix(2000)) }
                        }
                    DisclosureGroup("Add a checklist (optional)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What should be done correctly? Add one instruction per line.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            TextField("Add the steps or checks to review…", text: $taskCriteria, axis: .vertical)
                                .font(.system(size: 14)).lineLimit(3...7)
                                .accessibilityIdentifier("task-criteria")
                                .onChange(of: taskCriteria) { _, value in
                                    if value.count > 4000 { taskCriteria = String(value.prefix(4000)) }
                                }
                        }.padding(.top, 10)
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .videos, preferredItemEncoding: .current) {
                        Label("Upload & get feedback", systemImage: "arrow.up.doc")
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("import-photos")
                    Button { showFiles = true } label: {
                        Image(systemName: "folder").font(.system(size: 18))
                            .foregroundStyle(Palette.ink).frame(width: 56, height: 56)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
                    }.accessibilityLabel("Upload from Files & get feedback").accessibilityIdentifier("import-files")
                }
                Button { error = nil; showCamera = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle").font(.system(size: 21))
                        Text("Record a video")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 16))
                    }.padding(.horizontal, 20)
                }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("record-button")
                Text("Up to 60 minutes · MP4 or MOV")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).padding(.top, 4)
            }.disabled(store.activeID != nil)

            if let activeID = store.activeID {
                Button { path.append(activeID) } label: {
                    Label("Open your current review", systemImage: "arrow.right.circle")
                }.font(.subheadline.weight(.semibold))
            }

            Text("Choosing or finishing a video starts a review. It is sent to your review server and Google Gemini for analysis.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)

            Card {
                VStack(alignment: .leading, spacing: 17) {
                    feedbackStep("What needs fixing", detail: "Mistakes and missed steps visible in your work.", symbol: "exclamationmark.bubble")
                    feedbackStep("Where it happened", detail: "Timestamps to see the problem for yourself.", symbol: "play.rectangle")
                    feedbackStep("How to improve it", detail: "Clear, practical changes to make next.", symbol: "checkmark.circle")
                }
            }

            Button { showExample = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(Palette.ink)
                        .frame(width: 42, height: 42).background(Palette.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("See an example review").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text("A problem, an explanation, a fix.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").foregroundStyle(Palette.muted).font(.system(size: 13))
                }.padding(14).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).accessibilityIdentifier("example-button")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Your work and feedback")
                Text("Your videos").font(.system(size: 34, weight: .semibold)).tracking(-1.2).foregroundStyle(Palette.ink)
                Text("Revisit the problems and the next steps.").font(.subheadline).foregroundStyle(Palette.muted)
            }
            if store.sessions.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "rectangle.stack.badge.play").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.ink)
                        .frame(width: 100, height: 100).background(Palette.accent.opacity(0.25), in: Circle())
                    Text("No videos yet.").font(.headline).foregroundStyle(Palette.ink)
                    Text("Record or upload a video, then keep your feedback and next steps in one place.")
                        .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Add a video") { selectedTab = 0 }.buttonStyle(PrimaryButtonStyle())
                }.padding(24).padding(.vertical, 28).background(.white, in: RoundedRectangle(cornerRadius: 26))
            } else {
                ForEach(store.sessions) { session in
                    NavigationLink(value: session.id) { SessionRow(session: session) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var tabBar: some View {
        HStack {
            tab("Review", symbol: "viewfinder", value: 0)
            tab("Your videos", symbol: "rectangle.stack", value: 1)
        }.padding(.top, 12).padding(.bottom, 6)
            .background(Palette.background.opacity(0.98))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func tab(_ title: String, symbol: String, value: Int) -> some View {
        Button { selectedTab = value } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 19, weight: selectedTab == value ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: .semibold))
            }.frame(maxWidth: .infinity).frame(minHeight: 42)
                .foregroundStyle(selectedTab == value ? Palette.ink : Palette.muted.opacity(0.8))
        }.accessibilityIdentifier("tab-\(title)").accessibilityAddTraits(selectedTab == value ? .isSelected : [])
    }

    private func importVideo(_ url: URL, removeSource: Bool) {
        Task {
            do { try await prepareReview(url, removeSource: removeSource) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func prepareReview(_ url: URL, removeSource: Bool) async throws {
        let context = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try await store.addVideo(url, activity: .general, removeSource: removeSource)
        store.edit(id, title: context.isEmpty ? "Video review" : String(context.prefix(80)), activity: .general, goal: context, criteria: taskCriteria.trimmingCharacters(in: .whitespacesAndNewlines))
        error = nil
        path.append(id)
        store.review(id)
    }

    private func feedbackStep(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36).background(Palette.accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject private var store: SessionStore
    let session: VideoSession
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let url = store.thumbnailURL(session), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else { Palette.ink.overlay(Image(systemName: session.activity.symbol).foregroundStyle(Palette.accent)) }
            }.frame(width: 72, height: 88).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(session.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("\(session.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(session.duration)")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text(session.status.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(Palette.accent.opacity(0.3), in: Capsule())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 22))
    }
}
