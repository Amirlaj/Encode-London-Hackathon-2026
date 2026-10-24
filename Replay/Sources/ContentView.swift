import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var selectedTab = 0
    @State private var activity = Activity.tennis
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
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .navigationDestination(for: UUID.self) { id in SessionDetailView(id: id) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .sheet(isPresented: $showExample) { ExampleReportView() }
            .fullScreenCover(isPresented: $showCamera) {
                RecordingView(activity: activity) { url in
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
                        do { path.append(try await store.addVideo(url, activity: activity)) }
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
                        path.append(try await store.addVideo(video.url, activity: activity, removeSource: true))
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
                Eyebrow(text: "A fresh look at your practice")
                Text("A little better.\nEvery session.")
                    .font(.system(size: 37, weight: .semibold)).tracking(-1.6).lineSpacing(-1)
                    .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                Text("Record what you do. See what to do next.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
            }

            ZStack(alignment: .bottomLeading) {
                CourtArt()
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NEXT\nBREAKTHROUGH")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.9))
                    HStack(spacing: 5) {
                        Image(systemName: "viewfinder")
                        Text("Starts with a new perspective.")
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }.padding(20)
            }
            .frame(height: 173).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Circle().fill(Palette.accent).frame(width: 5, height: 5)
                    Text("UP TO 60 MIN").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                }.foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.black.opacity(0.15), in: Capsule()).padding(17)
            }

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "What are we working on?")
                ActivitySelector(selected: $activity)
            }

            VStack(spacing: 10) {
                Button { error = nil; showCamera = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle").font(.system(size: 21))
                        Text("Record a session")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 16))
                    }.padding(.horizontal, 20)
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("record-button")
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .videos, preferredItemEncoding: .current) {
                        Label("Upload a video", systemImage: "arrow.up.doc")
                    }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("import-photos")
                    Button { showFiles = true } label: {
                        Image(systemName: "folder").font(.system(size: 18))
                            .foregroundStyle(Palette.ink).frame(width: 54, height: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
                    }.accessibilityLabel("Import from Files").accessibilityIdentifier("import-files")
                }
            }

            Button { showExample = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(Palette.ink)
                        .frame(width: 42, height: 42).background(Palette.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Small details. Real progress.").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text("Take a look at an example review").font(.system(size: 11)).foregroundStyle(Palette.muted)
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
                Eyebrow(text: "Your progress, in perspective")
                Text("Your sessions").font(.system(size: 34, weight: .semibold)).tracking(-1.2).foregroundStyle(Palette.ink)
                Text("Every practice has something to teach you.").font(.subheadline).foregroundStyle(Palette.muted)
            }
            if store.sessions.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "rectangle.stack.badge.play").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.ink)
                        .frame(width: 100, height: 100).background(Palette.accent.opacity(0.25), in: Circle())
                    Text("Your first session starts here.").font(.headline).foregroundStyle(Palette.ink)
                    Text("Record or upload a video, then keep your feedback and next steps in one place.")
                        .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Start a session") { selectedTab = 0 }.buttonStyle(PrimaryButtonStyle())
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
            tab("Practice", symbol: "viewfinder", value: 0)
            tab("Sessions", symbol: "rectangle.stack", value: 1)
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
            do { path.append(try await store.addVideo(url, activity: activity, removeSource: removeSource)) }
            catch { self.error = error.localizedDescription }
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
