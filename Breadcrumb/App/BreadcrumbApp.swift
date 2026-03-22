import SwiftUI

@main
struct BreadcrumbApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .task {
                    appModel.loadIfNeeded()
                }
        }
    }
}
