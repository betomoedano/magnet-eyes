import SwiftUI

@main
struct MagnetEyesApp: App {
    @StateObject private var model = MagnetometerModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EyesView(model: model)
                .preferredColorScheme(.light)
                .statusBarHidden()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.start() } else { model.stop() }
                }
                .onAppear { model.start() }
                .onDisappear { model.stop() }
        }
    }
}
