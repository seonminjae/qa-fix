import SwiftUI

@main
struct QAFixMacApp: App {
    @State private var showCrashRecovery: Bool = false
    @State private var fixSessionStore = FixSessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(fixSessionStore)
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    if let store = try? SessionStore(), !store.crashedSessions().isEmpty {
                        showCrashRecovery = true
                    }
                }
                .sheet(isPresented: $showCrashRecovery) {
                    CrashRecoveryView()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
