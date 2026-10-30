import Combine
import Foundation

/// Tempo trascorso, separato da `AudioPlayer`: cambia quattro volte al secondo e
/// così aggiorna solo le viste che lo mostrano, non le liste della libreria.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published fileprivate(set) var position: TimeInterval = 0
    @Published fileprivate(set) var duration: TimeInterval = 0
}

/// Stato della riproduzione visibile all'interfaccia: coordina coda e motore audio.
@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var queue = PlaybackQueueManager()
    @Published private(set) var formatInfo: AudioFormatInfo?
    @Published private(set) var equalizer = EqualizerSettings()
    @Published var errorMessage: String?

    let progress = PlaybackProgress()

    /// Sotto questa soglia il tasto Indietro cambia brano invece di riavvolgere.
    static let restartThreshold: TimeInterval = 3
    private static let maxConsecutiveFailures = 3
    private static let sessionKey = "playback.session"
    private static let equalizerKey = "equalizer"

    private let engine: PlaybackEngine
    private let session: AudioSessionManager
    private let nowPlaying: NowPlayingManager
    private let persistence: PersistenceManager
    private let paths: AppPaths
    private let trackLookup: (UUID) -> Track?

    private var token: UInt64 = 0
    /// Vero se il motore non ha caricato il brano corrente (avvio, fine coda, seek in pausa).
    private var needsLoad = true
    private var consecutiveFailures = 0
    private var resumeAfterInterruption = false
    private var saveTask: Task<Void, Never>?

    init(
        engine: PlaybackEngine,
        session: AudioSessionManager,
        nowPlaying: NowPlayingManager,
        persistence: PersistenceManager,
        paths: AppPaths,
        trackLookup: @escaping (UUID) -> Track?
    ) {
        self.engine = engine
        self.session = session
        self.nowPlaying = nowPlaying
        self.persistence = persistence
        self.paths = paths
        self.trackLookup = trackLookup

        // Motore, sessione e comandi di sistema consegnano tutto sul main thread.
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        session.onEvent = { [weak self] event in
            self?.handle(event)
        }
        nowPlaying.install(NowPlayingManager.Commands(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] position in self?.seek(to: position) }
        ))
        restoreEqualizer()
    }

    // MARK: - Equalizzatore

    func updateEqualizer(_ change: (inout EqualizerSettings) -> Void) {
        change(&equalizer)
        engine.setEqualizer(equalizer)
        if let data = try? JSONEncoder().encode(equalizer), let json = String(data: data, encoding: .utf8) {
            try? persistence.setSetting(Self.equalizerKey, value: json)
        }
    }

    private func restoreEqualizer() {
        guard
            let json = try? persistence.setting(Self.equalizerKey),
            let data = json.data(using: .utf8),
            let saved = try? JSONDecoder().decode(EqualizerSettings.self, from: data),
            saved.gains.count == EqualizerSettings.frequencies.count
        else { return }
        equalizer = saved
        engine.setEqualizer(saved)
    }

    // MARK: - Avvio di una coda

    /// Riproduce `tracks` partendo da `index`. I brani con file mancante vengono esclusi.
    func play(tracks: [Track], startAt index: Int, source: QueueSource) {
        guard tracks.indices.contains(index) else { return }
        let selected = tracks[index]
        guard !selected.isMissing else {
            errorMessage = String(localized: "Il file di «\(selected.title)» non è più presente sul dispositivo.")
            return
        }
        let playable = tracks.filter { !$0.isMissing }
        let start = playable.firstIndex(of: selected) ?? 0
        queue.load(trackIDs: playable.map(\.id), startAt: start, source: source)
        startCurrentItem()
    }

    /// Riproduce `tracks` in ordine casuale partendo da un brano qualsiasi.
    func shufflePlay(tracks: [Track], source: QueueSource) {
        let playable = tracks.filter { !$0.isMissing }
        guard let first = playable.indices.randomElement() else { return }
        queue.setShuffle(true)
        queue.load(trackIDs: playable.map(\.id), startAt: first, source: source)
        startCurrentItem()
    }

    // MARK: - Controlli

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let track = currentTrack else { return }
        if needsLoad {
            load(track, at: progress.position)
        } else {
            engine.resume()
        }
        setPlaying(true)
    }

    func pause() {
        guard isPlaying else { return }
        engine.pause()
        setPlaying(false)
        saveSession()
    }

    func next() {
        guard queue.advance(userInitiated: true) != nil else {
            finishQueue()
            return
        }
        startCurrentItem()
    }

    /// Primo tocco a brano avanzato: torna all'inizio. Altrimenti: brano precedente.
    func previous() {
        guard currentTrack != nil else { return }
        if progress.position > Self.restartThreshold {
            seek(to: 0)
            return
        }
        _ = queue.retreat()
        startCurrentItem()
    }

    func seek(to position: TimeInterval) {
        guard currentTrack != nil else { return }
        let target = min(max(0, position), max(progress.duration, 0))
        progress.position = target
        if isPlaying {
            engine.seek(to: target)
        } else {
            // In pausa il motore riparte da qui alla prossima pressione di Play.
            engine.stop()
            needsLoad = true
        }
        updateNowPlaying()
        saveSession()
    }

    func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        scheduleSave()
    }

    func cycleRepeatMode() {
        queue.repeatMode = queue.repeatMode.next
        scheduleSave()
    }

    // MARK: - Coda

    func addToQueue(_ tracks: [Track]) {
        let wasEmpty = queue.isEmpty
        queue.append(trackIDs: playableIDs(tracks))
        if wasEmpty {
            prepareCurrentWithoutPlaying()
        }
        scheduleSave()
    }

    func playNext(_ tracks: [Track]) {
        let wasEmpty = queue.isEmpty
        queue.insertNext(trackIDs: playableIDs(tracks))
        if wasEmpty {
            prepareCurrentWithoutPlaying()
        }
        scheduleSave()
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpcoming(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func removeFromQueue(itemID: UUID) {
        if queue.remove(itemID: itemID) {
            handleCurrentItemRemoved()
        }
        scheduleSave()
    }

    func clearQueue() {
        queue.clearExceptCurrent()
        scheduleSave()
    }

    func jump(to itemID: UUID) {
        guard queue.jump(to: itemID) != nil else { return }
        startCurrentItem()
    }

    private func playableIDs(_ tracks: [Track]) -> [UUID] {
        tracks.filter { !$0.isMissing }.map(\.id)
    }

    // MARK: - Allineamento con la libreria

    /// Da chiamare quando la libreria cambia: aggiorna i metadati del brano
    /// corrente e toglie dalla coda i brani eliminati.
    func libraryDidChange() {
        let unknown = Set(queue.playOrder.map(\.trackID)).filter { trackLookup($0) == nil }
        if !unknown.isEmpty, queue.remove(trackIDs: unknown) {
            handleCurrentItemRemoved()
        }
        if let current = currentTrack, let updated = trackLookup(current.id), updated != current {
            currentTrack = updated
            updateNowPlaying()
        }
    }

    /// Riprende la sessione precedente senza far partire l'audio.
    func restoreSession() {
        guard
            let json = try? persistence.setting(Self.sessionKey),
            let data = json.data(using: .utf8),
            let saved = try? JSONDecoder().decode(PlaybackSession.self, from: data)
        else { return }

        queue = saved.queue
        let unknown = Set(queue.playOrder.map(\.trackID)).filter { trackLookup($0) == nil }
        if !unknown.isEmpty {
            queue.remove(trackIDs: unknown)
        }
        guard let item = queue.currentItem, let track = trackLookup(item.trackID) else { return }
        currentTrack = track
        progress.duration = track.duration
        progress.position = min(saved.position, track.duration)
        needsLoad = true
        updateNowPlaying()
    }

    /// Salva coda e posizione. Da chiamare anche quando l'app va in background.
    func saveSession() {
        saveTask?.cancel()
        saveTask = nil
        let snapshot = PlaybackSession(queue: queue, position: progress.position)
        guard
            let data = try? JSONEncoder().encode(snapshot),
            let json = String(data: data, encoding: .utf8)
        else { return }
        try? persistence.setSetting(Self.sessionKey, value: json)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveSession()
        }
    }

    // MARK: - Transizioni

    private func startCurrentItem() {
        guard let item = queue.currentItem, let track = trackLookup(item.trackID) else {
            finishQueue()
            return
        }
        load(track, at: 0)
        setPlaying(true)
        scheduleSave()
    }

    private func load(_ track: Track, at position: TimeInterval) {
        token &+= 1
        currentTrack = track
        formatInfo = nil
        progress.duration = track.duration
        progress.position = position
        needsLoad = false
        engine.load(url: paths.fileURL(for: track), startingAt: position, token: token)
    }

    private func prepareCurrentWithoutPlaying() {
        guard let item = queue.currentItem, let track = trackLookup(item.trackID) else { return }
        currentTrack = track
        progress.duration = track.duration
        progress.position = 0
        needsLoad = true
        updateNowPlaying()
    }

    /// La coda è finita: resta sull'ultimo brano, fermo all'inizio.
    private func finishQueue() {
        engine.stop()
        needsLoad = true
        progress.position = 0
        formatInfo = nil
        setPlaying(false)
        saveSession()
    }

    private func handleCurrentItemRemoved() {
        guard queue.currentItem != nil else {
            engine.stop()
            needsLoad = true
            currentTrack = nil
            formatInfo = nil
            progress.position = 0
            progress.duration = 0
            setPlaying(false)
            nowPlaying.clear()
            return
        }
        if isPlaying {
            startCurrentItem()
        } else {
            engine.stop()
            prepareCurrentWithoutPlaying()
        }
    }

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        nowPlaying.update(
            track: track,
            coverURL: track.coverID.map { CoverStore.url(for: $0, in: paths) },
            position: progress.position,
            duration: progress.duration,
            isPlaying: isPlaying
        )
    }

    // MARK: - Eventi del motore

    private func handle(_ event: PlaybackEngineEvent) {
        switch event {
        case .loaded(let info, let eventToken):
            guard eventToken == token else { return }
            consecutiveFailures = 0
            formatInfo = info
            updateNowPlaying()

        case .position(let position, let eventToken):
            guard eventToken == token, !needsLoad else { return }
            let duration = progress.duration
            progress.position = duration > 0 ? min(position, duration) : position

        case .finished(let eventToken):
            guard eventToken == token else { return }
            trackDidFinish()

        case .damaged(let eventToken):
            guard eventToken == token, let track = currentTrack else { return }
            errorMessage = String(localized: "«\(track.title)» contiene parti danneggiate: alcuni passaggi potrebbero essere saltati o silenziosi.")

        case .failed(let error, let eventToken):
            guard eventToken == token else { return }
            trackDidFail(error)
        }
    }

    private func trackDidFinish() {
        guard queue.advance(userInitiated: false) != nil else {
            finishQueue()
            return
        }
        startCurrentItem()
    }

    /// Un brano illeggibile non deve fermare la coda, ma nemmeno creare un ciclo
    /// infinito se sono illeggibili tutti.
    private func trackDidFail(_ error: Error) {
        let title = currentTrack?.title ?? ""
        errorMessage = String(localized: "Impossibile riprodurre «\(title)». \(error.localizedDescription)")
        consecutiveFailures += 1

        let limit = min(queue.playOrder.count, Self.maxConsecutiveFailures)
        guard consecutiveFailures < limit, queue.advance(userInitiated: true) != nil else {
            consecutiveFailures = 0
            finishQueue()
            return
        }
        startCurrentItem()
    }

    // MARK: - Eventi della sessione audio

    private func handle(_ event: AudioSessionManager.Event) {
        switch event {
        case .interruptionBegan:
            resumeAfterInterruption = isPlaying
            engine.invalidate()
            setPlaying(false)
            saveSession()

        case .interruptionEnded(let shouldResume):
            if shouldResume, resumeAfterInterruption {
                play()
            }
            resumeAfterInterruption = false

        case .outputDeviceRemoved:
            pause()

        case .mediaServicesReset:
            let wasPlaying = isPlaying
            engine.invalidate()
            setPlaying(false)
            if wasPlaying {
                play()
            }
        }
    }
}
