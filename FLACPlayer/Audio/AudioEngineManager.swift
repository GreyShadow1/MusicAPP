import AVFoundation

/// Eventi del motore audio, consegnati sul main thread. `token` identifica il
/// caricamento che li ha generati: l'app scarta quelli di un brano già superato.
enum PlaybackEngineEvent {
    case loaded(AudioFormatInfo, token: UInt64)
    case position(TimeInterval, token: UInt64)
    case finished(token: UInt64)
    case failed(Error, token: UInt64)
    case damaged(token: UInt64)
}

/// Contratto del motore audio. `AudioPlayer` dipende solo da questo, così la sua
/// logica è collaudabile senza hardware audio.
protocol PlaybackEngine: AnyObject {
    var onEvent: ((PlaybackEngineEvent) -> Void)? { get set }
    func load(url: URL, startingAt position: TimeInterval, token: UInt64)
    func pause()
    func resume()
    func seek(to position: TimeInterval)
    func stop()
    /// Da chiamare dopo un'interruzione: il grafo audio non è più affidabile.
    func invalidate()
    func setEqualizer(_ settings: EqualizerSettings)
}

/// Percorso audio: FLACDecoder → AVAudioPCMBuffer (float32) → AVAudioPlayerNode →
/// equalizzatore → mixer → uscita.
///
/// Tutto lo stato è confinato in una coda seriale. La decodifica è guidata dai
/// buffer completati: al massimo `maxBuffersInFlight` restano in memoria, quindi
/// il consumo non dipende dalla lunghezza del brano. L'equalizzatore è facoltativo:
/// da spento è in bypass. Non ci sono normalizzazione o guadagno: il mixer lavora a volume 1.
final class AudioEngineManager: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?

    private static let bufferSeconds = 0.5
    private static let maxBuffersInFlight = 6

    private let queue = DispatchQueue(label: "flacplayer.audio-engine", qos: .userInitiated)
    private let session: AudioSessionManager

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var equalizerNode: AVAudioUnitEQ?
    private var equalizerSettings = EqualizerSettings()
    private var format: AVAudioFormat?
    private var configurationObserver: NSObjectProtocol?

    private var decoder: FLACDecoder?
    private var currentURL: URL?
    private var token: UInt64 = 0

    /// Cresce a ogni caricamento o seek: invalida i buffer già programmati.
    private var generation: UInt64 = 0
    private var buffersInFlight = 0
    private var reachedEnd = false
    private var pendingError: Error?

    /// Posizione del primo campione programmato dopo l'ultimo `play()`.
    private var basePosition: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var isPaused = false
    private var needsRestart = false

    private var positionTimer: DispatchSourceTimer?

    init(session: AudioSessionManager) {
        self.session = session
    }

    // MARK: - Comandi

    func load(url: URL, startingAt position: TimeInterval, token: UInt64) {
        queue.async { self.performLoad(url: url, position: position, token: token) }
    }

    func pause() {
        queue.async {
            guard self.decoder != nil, !self.isPaused else { return }
            self.lastPosition = self.currentPosition()
            self.isPaused = true
            self.stopPositionTimer()
            self.playerNode?.pause()
            self.engine?.pause()
            self.post(.position(self.lastPosition, token: self.token))
        }
    }

    func resume() {
        queue.async {
            guard let url = self.currentURL, self.decoder != nil else { return }
            if self.needsRestart {
                self.performLoad(url: url, position: self.lastPosition, token: self.token)
                return
            }
            guard let engine = self.engine, let node = self.playerNode else { return }
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                node.play()
                self.isPaused = false
                self.startPositionTimer()
            } catch {
                self.post(.failed(error, token: self.token))
            }
        }
    }

    func seek(to position: TimeInterval) {
        queue.async { self.performSeek(to: position) }
    }

    func stop() {
        queue.async {
            self.resetTrackState()
            self.currentURL = nil
            self.engine?.stop()
        }
    }

    func invalidate() {
        queue.async {
            guard self.decoder != nil else { return }
            if !self.isPaused {
                self.lastPosition = self.currentPosition()
            }
            self.isPaused = true
            self.needsRestart = true
            self.stopPositionTimer()
        }
    }

    func setEqualizer(_ settings: EqualizerSettings) {
        queue.async {
            self.equalizerSettings = settings
            if let node = self.equalizerNode {
                self.apply(settings, to: node)
            }
        }
    }

    private func apply(_ settings: EqualizerSettings, to node: AVAudioUnitEQ) {
        for (band, gain) in zip(node.bands, settings.gains) {
            band.gain = gain
        }
        node.globalGain = settings.headroom
        node.bypass = !settings.isEnabled
    }

    private func makeEqualizer() -> AVAudioUnitEQ {
        let node = AVAudioUnitEQ(numberOfBands: EqualizerSettings.frequencies.count)
        for (band, frequency) in zip(node.bands, EqualizerSettings.frequencies) {
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.bypass = false
        }
        apply(equalizerSettings, to: node)
        return node
    }

    // MARK: - Caricamento

    private func performLoad(url: URL, position: TimeInterval, token: UInt64) {
        resetTrackState()
        self.token = token
        currentURL = url

        do {
            let decoder = try FLACDecoder(url: url)
            let info = decoder.info
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(info.sampleRate),
                channels: AVAudioChannelCount(info.channels)
            ) else {
                throw FLACError.decodingFailed
            }

            if position > 0 {
                try decoder.seek(toFrame: Self.frame(for: position, info: info))
            }
            self.decoder = decoder
            try prepareGraph(for: format)

            basePosition = position
            lastPosition = position
            generation &+= 1
            scheduleBuffers(generation: generation)
            playerNode?.play()
            startPositionTimer()

            post(.loaded(
                AudioFormatInfo(
                    sourceSampleRate: info.sampleRate,
                    sourceBitDepth: info.bitDepth,
                    outputSampleRate: session.outputSampleRate,
                    outputName: session.outputName
                ),
                token: token
            ))
        } catch {
            resetTrackState()
            post(.failed(error, token: token))
        }
    }

    /// Il grafo si ricrea solo quando cambia il formato o il motore è fermo. Un
    /// motore nuovo eredita la frequenza attuale dell'hardware senza stati residui.
    private func prepareGraph(for format: AVAudioFormat) throws {
        if engine?.isRunning == true, self.format == format {
            return
        }
        tearDownGraph()
        try session.activate(preferredSampleRate: format.sampleRate)

        let newEngine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let equalizer = makeEqualizer()
        newEngine.attach(node)
        newEngine.attach(equalizer)
        newEngine.connect(node, to: equalizer, format: format)
        newEngine.connect(equalizer, to: newEngine.mainMixerNode, format: format)
        newEngine.prepare()
        try newEngine.start()

        engine = newEngine
        playerNode = node
        equalizerNode = equalizer
        self.format = format
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.handleConfigurationChange() }
        }
    }

    private func tearDownGraph() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        equalizerNode = nil
        engine = nil
        format = nil
    }

    /// Cambio di uscita (cuffie, AirPlay, Bluetooth): iOS ferma il motore e
    /// scarta i buffer, quindi si riparte dal punto in cui si era.
    private func handleConfigurationChange() {
        guard let engine, !engine.isRunning, let url = currentURL, decoder != nil else { return }
        if isPaused {
            needsRestart = true
            return
        }
        performLoad(url: url, position: currentPosition(), token: token)
    }

    private func resetTrackState() {
        generation &+= 1
        stopPositionTimer()
        playerNode?.stop()
        decoder = nil
        buffersInFlight = 0
        reachedEnd = false
        pendingError = nil
        isPaused = false
        needsRestart = false
    }

    // MARK: - Seek

    private func performSeek(to position: TimeInterval) {
        guard let decoder, let node = playerNode, let url = currentURL else { return }
        // play() su un motore fermo solleva un'eccezione: iOS può averlo appena
        // fermato per un cambio di uscita, prima che arrivi la notifica.
        guard engine?.isRunning == true else {
            performLoad(url: url, position: position, token: token)
            return
        }
        let target = Self.frame(for: position, info: decoder.info)
        generation &+= 1
        node.stop()
        buffersInFlight = 0
        reachedEnd = false
        pendingError = nil
        do {
            try decoder.seek(toFrame: target)
            basePosition = Double(target) / Double(decoder.info.sampleRate)
            lastPosition = basePosition
            scheduleBuffers(generation: generation)
            node.play()
            isPaused = false
            startPositionTimer()
            post(.position(basePosition, token: token))
        } catch {
            post(.failed(error, token: token))
        }
    }

    private static func frame(for position: TimeInterval, info: FLACStreamInfo) -> Int64 {
        let frame = Int64(position * Double(info.sampleRate))
        guard info.totalFrames > 0 else { return max(0, frame) }
        return min(max(0, frame), info.totalFrames - 1)
    }

    // MARK: - Decodifica

    private func scheduleBuffers(generation: UInt64) {
        guard generation == self.generation, let decoder, let format, let node = playerNode else { return }
        let capacity = AVAudioFrameCount(Double(decoder.info.sampleRate) * Self.bufferSeconds)

        while buffersInFlight < Self.maxBuffersInFlight, !reachedEnd {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                pendingError = FLACError.outOfMemory
                reachedEnd = true
                break
            }
            do {
                guard try decoder.read(into: buffer) > 0 else {
                    reachedEnd = true
                    break
                }
                buffersInFlight += 1
                // Il completamento non deve mai richiamare il nodo direttamente:
                // fermarlo da questa callback provocherebbe un deadlock.
                node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    self?.queue.async { self?.bufferDidFinish(generation: generation) }
                }
            } catch {
                pendingError = error
                reachedEnd = true
            }
        }

        if reachedEnd, buffersInFlight == 0 {
            trackDidEnd()
        }
    }

    private func bufferDidFinish(generation: UInt64) {
        guard generation == self.generation else { return }
        buffersInFlight -= 1
        scheduleBuffers(generation: generation)
    }

    private func trackDidEnd() {
        guard let decoder else { return }
        let token = self.token
        let wasDamaged = decoder.errorCount > 0
        let error = pendingError
        stopPositionTimer()
        // Evita un secondo evento di fine se arrivano altri completamenti.
        generation &+= 1

        if let error {
            post(.failed(error, token: token))
        } else {
            if wasDamaged {
                post(.damaged(token: token))
            }
            post(.finished(token: token))
        }
    }

    // MARK: - Posizione

    private func currentPosition() -> TimeInterval {
        guard
            let node = playerNode,
            let renderTime = node.lastRenderTime,
            let playerTime = node.playerTime(forNodeTime: renderTime),
            playerTime.sampleRate > 0
        else {
            return lastPosition
        }
        let position = basePosition + Double(playerTime.sampleTime) / playerTime.sampleRate
        return max(position, basePosition)
    }

    private func startPositionTimer() {
        stopPositionTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lastPosition = self.currentPosition()
            self.post(.position(self.lastPosition, token: self.token))
        }
        positionTimer = timer
        timer.resume()
    }

    private func stopPositionTimer() {
        positionTimer?.cancel()
        positionTimer = nil
    }

    private func post(_ event: PlaybackEngineEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
