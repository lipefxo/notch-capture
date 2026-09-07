import SwiftUI

@main
struct NotchCaptureMobileApp: App {
    @State private var model = MobileCaptureModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView(model: model)
                .task { await model.start() }
        }
    }
}
