import SwiftUI

@main
struct ReplayApp: App {
    @StateObject private var store = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).tint(Palette.ink).preferredColorScheme(.light)
                .task { await store.recoverRecordings() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.pause() }
                    if phase == .active { store.resumeReviews() }
                }
        }
    }
}
