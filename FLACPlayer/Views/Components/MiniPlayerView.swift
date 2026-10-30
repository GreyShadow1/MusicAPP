import SwiftUI

/// Lettore compatto sopra la barra inferiore. Un tocco apre "In riproduzione".
struct MiniPlayerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                MiniProgressBar(progress: player.progress)
                HStack(spacing: 12) {
                    Button {
                        appState.selectedTab = .nowPlaying
                    } label: {
                        HStack(spacing: 12) {
                            CoverArtView(coverID: track.coverID, side: 40, cornerRadius: 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pausa" : "Riproduci")

                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Brano successivo")
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Theme.surface)
        }
    }
}

private struct MiniProgressBar: View {
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        GeometryReader { geometry in
            let fraction = progress.duration > 0 ? progress.position / progress.duration : 0
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: 2)
    }
}
