import SwiftUI

struct MenuBarLabel: View {
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingRecording: Bool
    let isMeetingProcessing: Bool

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        Image("MenuBarIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .overlay(alignment: .bottomTrailing) {
                if isMeetingRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                        .opacity(pulseOpacity)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulseOpacity = 0.3
                            }
                        }
                        .onDisappear {
                            pulseOpacity = 1.0
                        }
                } else if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                } else if isProcessing || isMeetingProcessing {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                }
            }
    }
}
