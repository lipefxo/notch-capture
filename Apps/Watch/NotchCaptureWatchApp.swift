import SwiftUI

@main
struct NotchCaptureWatchApp: App {
    @State private var model = WatchCaptureModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
                .task { await model.start() }
        }
    }
}
