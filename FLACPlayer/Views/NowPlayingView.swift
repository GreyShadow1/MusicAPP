import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayer

    @State private var isShowingQueue = false

    var body: some View {
        Group {
            if let track = player.currentTrack {
                GeometryReader { geometry in
                    let side = max(min(geometry.size.width - 56, geometry.size.height * 0.48), 1)
                    VStack(spacing: 0) {
                        Spacer(minLength: 8)
                        CoverArtView(coverID: track.coverID, side: side, cornerRadius: 12)
                            .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
                        Spacer(minLength: 12)
                        details(for: track)
                        Spacer(minLength: 12)
                        PlaybackSlider(progress: player.progress)
                        Spacer(minLength: 8)
                        transportControls
                        Spacer(minLength: 8)
                        secondaryControls(for: track)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(
                    systemImage: "music.note",
                    title: "Nessun brano in riproduzione",
                    message: "Scegli un brano dalla libreria."
                )
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $isShowingQueue) {
            QueueView()
        }
    }

    private func details(for track: Track) -> some View {
        VStack(spacing: 4) {
            Text(track.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(track.artist)
                .font(.body)
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
            Text(track.album)
                .font(.subheadline)
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
            formatLine(for: track)
        }
    }

    /// Mostra il formato reale del file e dell'uscita, senza promesse di bit-perfect.
    @ViewBuilder
    private func formatLine(for track: Track) -> some View {
        VStack(spacing: 1) {
            if let info = player.formatInfo {
                Text(info.sourceDescription)
                Text(info.outputDescription)
            } else {
                Text("FLAC \(track.qualityDescription)")
            }
        }
        .font(.caption2)
        .foregroundColor(Theme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.top, 4)
    }

    private var transportControls: some View {
        HStack(spacing: 44) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Brano precedente")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .frame(width: 72, height: 72)
            }
            .accessibilityLabel(player.isPlaying ? "Pausa" : "Riproduci")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Brano successivo")
        }
        .foregroundColor(.primary)
    }

    private func secondaryControls(for track: Track) -> some View {
        HStack {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundColor(player.queue.isShuffled ? .accentColor : Theme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.queue.isShuffled ? "Disattiva riproduzione casuale" : "Attiva riproduzione casuale")

            Spacer()

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.queue.repeatMode.systemImage)
                    .foregroundColor(player.queue.repeatMode == .off ? Theme.secondaryText : .accentColor)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.queue.repeatMode.accessibilityLabel)

            Spacer()

            FavoriteButton(trackID: track.id, font: .title3)

            Spacer()

            Button {
                isShowingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Coda di riproduzione")
        }
        .font(.title3)
    }
}

/// Barra di avanzamento: durante il trascinamento mostra il punto scelto e sposta
/// la riproduzione solo al rilascio.
private struct PlaybackSlider: View {
    @ObservedObject var progress: PlaybackProgress

    @EnvironmentObject var player: AudioPlayer
    @State private var isDragging = false
    @State private var draggedPosition: TimeInterval = 0

    private var shownPosition: TimeInterval {
        isDragging ? draggedPosition : progress.position
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { shownPosition }, set: { draggedPosition = $0 }),
                in: 0...max(progress.duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        draggedPosition = progress.position
                        isDragging = true
                    } else {
                        player.seek(to: draggedPosition)
                        isDragging = false
                    }
                }
            )
            .disabled(progress.duration <= 0)
            .accessibilityLabel("Avanzamento del brano")

            HStack {
                Text(TimeFormatting.string(shownPosition))
                Spacer()
                Text(TimeFormatting.string(progress.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(Theme.secondaryText)
        }
    }
}
