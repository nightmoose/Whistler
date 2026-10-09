import SwiftUI

@main
struct WhistlerApp: App {
    @State private var session = WhistleSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
