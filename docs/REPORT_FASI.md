# Report di sviluppo

Stato al 30 ottobre 2026.

## Riepilogo

| Parte | Stato |
|---|---|
| Decoder FLAC (C) | **Collaudato** su Windows contro il decoder di riferimento |
| Compilazione del C per arm64 | **Verificata** con Zig/clang, target macOS arm64 |
| Sintassi Swift | **Verificata** con un parser (tree-sitter): 46 file, 0 errori |
| Compilazione Swift | **Non eseguita**: richiede Xcode, quindi avverrà su Codemagic |
| Test XCTest | **Scritti, mai eseguiti**: partiranno su Codemagic |
| `codemagic.yaml` | YAML valido, **mai eseguito** |
| IPA e Sideloadly | **Non provati** |
| Riproduzione su iPhone | **Non provata** |

Un parser controlla la forma del codice, non i tipi. La prima compilazione può quindi segnalare errori da correggere.

## Fase 1: analisi tecnica

**Decisioni**

| Tema | Scelta | Motivo |
|---|---|---|
| Decoder | libFLAC 1.5.0, sorgente incluso | Implementazione di riferimento, BSD a 3 clausole, nessuna dipendenza esterna da scaricare in compilazione |
| Alternativa scartata | dr_flac | Ben mantenuto, ma senza release con tag e con molte correzioni recenti proprio sul seek (crash e deadlock, le ultime del 28 ottobre 2026) |
| Progetto Xcode | XcodeGen 2.46 su Codemagic | Da Windows non si può generare né mantenere un `.pbxproj` in modo affidabile |
| Persistenza | SQLite con WAL | Scritture atomiche, nessun vincolo a iOS 17 |
| Compatibilità | iOS 16, modalità Swift 5 | Più iPhone supportati, nessun errore di concorrenza stretta |
| IPA | `xcodebuild archive` senza firma, poi zip di `Payload/` | Sideloadly firma sul PC |

**Verifiche sulla dipendenza libFLAC**

| Requisito | Esito |
|---|---|
| Mantenuta | Release 1.5.0 di febbraio 2025 del progetto Xiph |
| Supporta iOS | Codice C portabile. Compila per arm64 con le intestazioni Apple |
| Licenza | BSD a 3 clausole |
| ARM64 | Compilata con target `aarch64-macos`. Nessun assembly richiesto |
| Integrazione | Pacchetto Swift locale con sorgente incluso |
| Serve un Mac locale | No |

SHA‑256 del sorgente scaricato: `F2C1C76592A82FFFF8413BA3C4A1299B6C7AB06C734DEE03FD88630485C2B920`.

**File:** nessuno. Fase di sola analisi.

## Fase 2: creazione del progetto

Struttura del progetto, configurazione XcodeGen, `Info.plist`, modelli dati e percorsi.

**File:** `project.yml`, `.gitignore`, `.gitattributes`, `FLACPlayer/Config/Info.plist`, `FLACPlayer/Models/*`, `FLACPlayer/Services/AppPaths.swift`.

**Scostamenti dalla struttura suggerita**

- `Playlists/` e `Covers/` non stanno in Documents. Il database e le copertine sono in Application Support, così non si possono cancellare da Windows.
- I test sono in `FLACPlayerTests/`, fuori dal target dell'app.

## Fase 3: decoder FLAC

Incluso il sottoinsieme di libFLAC necessario alla decodifica (11 file `.c`, senza encoder) e scritto un bridge C che trasforma il modello a callback in letture a richiesta.

**File:** `Packages/CFLAC/**`, `FLACPlayer/Audio/FLACDecoder.swift`.

**Collaudo eseguito su Windows.** File creati con `flac.exe` 1.5.0 a compressione massima.

| Prova | Risultato |
|---|---|
| Output confrontato bit per bit con `flac -d`: 16 e 24 bit a 44,1 / 48 / 88,2 / 96 / 176,4 / 192 kHz, più mono | **13 su 13 identici** |
| Letture a blocchi di dimensioni diverse (4096 e 1777 frame) | Identiche |
| Seek in 11 posizioni per file, inclusi primo e ultimo frame | **0 differenze** |
| Seek oltre la fine | Errore gestito, il decoder resta utilizzabile |
| Firma MD5 di tutti i file | Corrisponde |
| Tag UTF‑8 e copertina frontale preferita alla posteriore | Corretti |
| File vuoto, testo con estensione `.flac`, file assente | Errori distinti, nessun crash |
| File troncato | Riprodotto fino al punto valido, segnalato |
| File con byte alterati | Nessun crash, errori contati, MD5 rifiutato |
| File con tag ID3 in testa | Letto correttamente |
| FLAC a 6 canali | Rifiutato con un errore dedicato |

**Problemi:** il compilatore Zig ha rilevato un frammento mancante in `lpc.c`, poi aggiunto. Il collaudo è avvenuto su x86‑64: su arm64 il codice è stato solo compilato.

## Fase 4: motore audio

Percorso `FLACDecoder → AVAudioPCMBuffer → AVAudioPlayerNode → mixer → uscita`. Tutto lo stato vive in una coda seriale. La decodifica è guidata dai buffer completati e tiene in memoria al massimo 3 secondi. Una generazione numerica scarta i buffer di un brano già superato.

**File:** `FLACPlayer/Audio/AudioEngineManager.swift`, `AudioSessionManager.swift`.

**Problemi:** in revisione è emerso che `play()` su un motore appena fermato da iOS solleverebbe un'eccezione durante il seek. Il caso ora ricarica il brano dal punto richiesto.

## Fase 5: libreria

Database SQLite con migrazioni, identificativi stabili, lettura dei tag, copertine deduplicate e caricate ridimensionate. Un database illeggibile viene messo da parte e ricreato, invece di bloccare l'app.

**File:** `FLACPlayer/Services/SQLiteDatabase.swift`, `PersistenceManager.swift`, `MetadataReader.swift`, `CoverStore.swift`, `FileHasher.swift`, `MusicLibraryManager.swift`.

## Fase 6: importazione e USB

Selettore di File con selezione multipla e cartelle, copia atomica, controllo dello spazio, duplicati per SHA‑256. La scansione copre tutto Documents, perché da Windows i file finiscono nella radice della cartella dell'app, non in `Music/`.

**File:** `FLACPlayer/Services/FileImportManager.swift`, `FileScanner.swift`, `FLACPlayer/Views/ImportMusicView.swift`.

**Comportamenti da conoscere**

- Un file spostato o rinominato mantiene identità, playlist e preferiti.
- Un file sparito resta come «File mancante» e torna quando ricompare.
- Un duplicato non viene cancellato, solo ignorato. Se l'originale sparisce, ne prende il posto.
- La musica è esclusa dal backup di iCloud.

## Fase 7: playlist

Creazione, rinomina, aggiunta, rimozione, riordino ed eliminazione. Le playlist contengono solo identificativi. Eliminando un brano, una chiave esterna lo toglie anche da playlist e preferiti.

**File:** `FLACPlayer/Views/PlaylistsView.swift`, `PersistenceManager.swift`, `MusicLibraryManager.swift`.

## Fase 8: preferiti

Il cuore salva subito. «PREFERITI» è una vista dell'elenco, non una playlist, quindi è sempre aggiornata e non è modificabile a mano.

**File:** `FLACPlayer/Services/FavoritesManager.swift`, `FLACPlayer/Views/FavoritesView.swift`, `Components/FavoriteButton.swift`.

## Fase 9: coda, Shuffle e Repeat

Struttura a valore senza dipendenze audio. Separa brano corrente, coda corrente, ordine originale e sorgente. Repeat One ripete solo alla fine naturale; Avanti cambia comunque brano.

**File:** `FLACPlayer/Audio/PlaybackQueueManager.swift`, `AudioPlayer.swift`, `FLACPlayer/Models/QueueItem.swift`.

## Fase 10: interfaccia

Quattro schede, mini-player persistente, libreria con ricerca e ordinamento, album, artisti, lettore completo, coda. Tema scuro. L'icona dell'app è generata via codice.

**File:** `FLACPlayer/App/*`, `FLACPlayer/Views/**`, `FLACPlayer/Resources/**`.

## Fase 11: background e controlli di sistema

Background Audio, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`. Interruzioni: pausa e ripresa se iOS lo consente. Cuffie scollegate: pausa. Cambio di uscita: ripartenza dallo stesso punto.

**File:** `FLACPlayer/Audio/NowPlayingManager.swift`, `AudioSessionManager.swift`, `AudioEngineManager.swift`, `AudioPlayer.swift`.

**Problemi:** il comportamento reale dipende da iOS e va provato sull'iPhone.

## Fase 12: test

Scritti 5 file di test. I controlli eseguibili su Windows sono passati; gli XCTest no, perché richiedono Xcode.

| Test richiesto | Dove |
|---|---|
| 1–2. Importazione singola e multipla | `LibraryTests` |
| 3–4. Metadati e copertine | `LibraryTests` |
| 5. Duplicati | `LibraryTests` |
| 6–9. Riproduzione, pausa, cambio traccia, seek | `AudioPlayerTests` con motore simulato, `FLACDecoderTests`; audio reale con la checklist del README |
| 10–12. Repeat One, Repeat All, Shuffle | `QueueManagerTests`, `AudioPlayerTests` |
| 13–15. Playlist | `PlaylistTests` |
| 16. Preferiti | `PlaylistTests` |
| 17. Persistenza | `PlaylistTests`, `AudioPlayerTests` |
| 18. Scansione USB | `LibraryTests` |

**Revisione manuale.** Non potendo compilare, il codice è stato riletto cercando errori che il parser non vede. Corretti tra gli altri: `import Combine` mancante, autoreferenze come `let tracks = tracks`, `Self` usato prima della fine di `init`, `try` a destra di `?:`, alert multipli che si annullavano, caricamento iniziale non garantito al primo avvio, un test dipendente dall'ordine dei file.

**File:** `FLACPlayerTests/**`.

## Fase 13: Codemagic

Due workflow avviati a mano, per non consumare minuti a ogni push: con test e senza test. Xcode 26.6 su Mac mini M2, entrambi disponibili secondo la documentazione di Codemagic consultata oggi.

**File:** `codemagic.yaml`.

## Fase 14: generazione dell'IPA

Il workflow archivia senza firma, crea `Payload/FLACPlayer.app` e lo comprime in `FLACPlayer.ipa`. Poi controlla architettura arm64, Background Audio e condivisione file, e fallisce se manca qualcosa.

**Da verificare:** l'IPA non è ancora stato generato.

## Fase 15: installazione con Sideloadly

Guida completa nel README, sezioni J–O, basata sulla documentazione e sulla FAQ di Sideloadly.

**Da verificare:** installazione reale. La FAQ non parla di Dispositivi Apple, quindi la convivenza con iTunes non è confermata: la guida prevede anche il trasferimento USB tramite iTunes.

## Fonti consultate

- [Release di libFLAC](https://github.com/xiph/flac/releases)
- [Cronologia di dr_flac](https://github.com/mackron/dr_libs/commits/master/dr_flac.h)
- [FAQ di Sideloadly](https://sideloadly.io/faq.html)
- [Configurazione YAML di Codemagic](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/)
- [Specifiche delle macchine macOS di Codemagic](https://docs.codemagic.io/specs/versions-macos/)
- [Prezzi di Codemagic](https://codemagic.io/pricing/)
- [Dispositivi Apple: condivisione file](https://support.apple.com/en-us/120402)
- [iTunes: condivisione file](https://support.apple.com/en-us/120403)
