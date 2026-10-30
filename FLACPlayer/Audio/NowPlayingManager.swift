import MediaPlayer
import UIKit

/// Schermata di blocco, Centro di Controllo e comandi delle cuffie.
final class NowPlayingManager {
    struct Commands {
        let play: () -> Void
        let pause: () -> Void
        let toggle: () -> Void
        let next: () -> Void
        let previous: () -> Void
        let seek: (TimeInterval) -> Void
    }

    private var targets: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?
    private var artworkCoverID: String?

    func install(_ commands: Commands) {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand, commands.play)
        register(center.pauseCommand, commands.pause)
        register(center.togglePlayPauseCommand, commands.toggle)
        register(center.nextTrackCommand, commands.next)
        register(center.previousTrackCommand, commands.previous)

        center.changePlaybackPositionCommand.isEnabled = true
        let target = center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            commands.seek(event.positionTime)
            return .success
        }
        targets.append((center.changePlaybackPositionCommand, target))
    }

    private func register(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
        command.isEnabled = true
        let target = command.addTarget { _ in
            action()
            return .success
        }
        targets.append((command, target))
    }

    func update(track: Track, coverURL: URL?, position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        if artworkCoverID != track.coverID {
            artworkCoverID = track.coverID
            artwork = coverURL.flatMap(Self.makeArtwork)
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        artwork = nil
        artworkCoverID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Funzione statica: iOS chiama il blocco su un thread qualsiasi, che non deve
    /// ereditare alcun isolamento dal chiamante.
    private static func makeArtwork(url: URL) -> MPMediaItemArtwork? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
