/// Full-screen countdown / alignment-cue overlay shown while preparing to film an animation.
import SwiftUI

enum FilmingPhase: Equatable {
    case countdown(secondsRemaining: Int)
    case playingCue
}

struct FilmingCountdownOverlay: View {
    let phase: FilmingPhase
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                switch phase {
                case .countdown(let secondsRemaining):
                    Text("\(secondsRemaining)")
                        .font(.system(size: 160, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Text(
                        secondsRemaining == 0
                            ? "Alignment starting" : "Starting in \(secondsRemaining)"
                    )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                case .playingCue:
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Text("Playing Alignment Sound")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.red)
            }
            .padding(40)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .shadow(radius: 24)
        }
    }
}
