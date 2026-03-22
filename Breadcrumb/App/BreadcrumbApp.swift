import SwiftUI
import SwiftData

@main
struct BreadcrumbApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var appModel: AppModel

    init() {
        do {
            let schema = Schema([
                ObjectCandidate.self,
                TrackedObject.self,
                LastKnownObjectState.self,
                HandInteractionRecord.self,
                TrackingSession.self,
                ObservationRecord.self,
                ObjectObservationEvent.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(
                for: schema,
                configurations: configuration
            )
            modelContainer = container
            _appModel = StateObject(wrappedValue: AppModel(container: container))
        } catch {
            fatalError("Failed to create Breadcrumb model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .modelContainer(modelContainer)
                .task {
                    appModel.loadIfNeeded()
                }
        }
    }
}
