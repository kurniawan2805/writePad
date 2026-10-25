import SwiftUI

@main
struct WritePadApp: App {
    @State private var resources = LibraryResources()

    var body: some Scene {
        WindowGroup(for: NotebookWindowRequest.self) { request in
            LibrarySceneView(resources: resources, request: request)
        }
    }
}
