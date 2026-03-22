import SwiftUI

enum AppTab: Hashable {
    case objects
    case memory
    case observe
    case sessions
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .objects

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ItemLibraryView()
            }
            .tabItem {
                Label("Objects", systemImage: "shippingbox")
            }
            .tag(AppTab.objects)

            NavigationStack {
                FindItemView()
            }
            .tabItem {
                Label("Memory", systemImage: "brain.head.profile")
            }
            .tag(AppTab.memory)

            NavigationStack {
                CaptureTimelineView()
            }
            .tabItem {
                Label("Observe", systemImage: "record.circle")
            }
            .tag(AppTab.observe)

            NavigationStack {
                SessionHistoryView()
            }
            .tabItem {
                Label("Sessions", systemImage: "clock.arrow.circlepath")
            }
            .tag(AppTab.sessions)
        }
        .tint(.orange)
    }
}
