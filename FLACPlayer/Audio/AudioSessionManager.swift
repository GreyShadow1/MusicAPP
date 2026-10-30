import AVFoundation

/// Gestisce AVAudioSession e traduce le notifiche di sistema in eventi semplici.
final class AudioSessionManager {
    enum Event {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case outputDeviceRemoved
        case mediaServicesReset
    }

    /// Chiamato sul main thread.
    var onEvent: ((Event) -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                self?.handleInterruption(note)
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
                self?.handleRouteChange(note)
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                self?.configureCategory()
                self?.onEvent?(.mediaServicesReset)
            }
        ]
        configureCategory()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// `.playback` continua con schermo bloccato e silenzioso disattivato, e
    /// include Bluetooth A2DP e AirPlay senza opzioni aggiuntive.
    private func configureCategory() {
        try? session.setCategory(.playback, mode: .default)
    }

    /// Chiede a iOS di portare l'uscita alla frequenza del brano. È una
    /// preferenza: se il dispositivo non la supporta, la frequenza resta quella
    /// dell'hardware e AVAudioEngine ricampiona.
    func activate(preferredSampleRate: Double) throws {
        try? session.setPreferredSampleRate(preferredSampleRate)
        try session.setActive(true)
    }

    var outputSampleRate: Double {
        session.sampleRate
    }

    var outputName: String {
        session.currentRoute.outputs.first?.portName ?? String(localized: "Uscita audio")
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            onEvent?(.interruptionBegan)
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }

        // Cuffie scollegate: la musica non deve continuare dall'altoparlante.
        if reason == .oldDeviceUnavailable {
            onEvent?(.outputDeviceRemoved)
        }
    }
}
