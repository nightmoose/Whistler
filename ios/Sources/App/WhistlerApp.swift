import SwiftUI

@main
struct WhistlerApp: App {
    @State private var session = WhistleSession()
    @State private var pro = ProStatus(source: StoreKitSource())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(pro)
                .task {
                    // Starts the Transaction.updates listener and reads
                    // Transaction.currentEntitlements at launch.
                    await pro.start()
                }
                .onChange(of: pro.isPro, initial: true) { _, isPro in
                    session.isPro = isPro
                }
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
