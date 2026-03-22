import SwiftUI

enum AppTab: Hashable {
    case items
    case capture
    case find
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: AppTab = .items

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ItemLibraryView()
            }
            .tabItem {
                Label("Items", systemImage: "square.stack.3d.up")
            }
            .tag(AppTab.items)

            NavigationStack {
                CaptureTimelineView()
            }
            .tabItem {
                Label("Capture", systemImage: "camera.viewfinder")
            }
            .tag(AppTab.capture)

            NavigationStack {
                FindItemView()
            }
            .tabItem {
                Label("Find", systemImage: "magnifyingglass")
            }
            .tag(AppTab.find)
        }
        .tint(.indigo)
    }
}
