import SwiftUI

@Observable
@MainActor
final class AppState {
    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false
    var modelLoadingProgress: Double = 0
}
