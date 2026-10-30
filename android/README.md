# FLAC Player per Android

Versione Android di FLAC Player: stesse funzioni dell'app iOS, riscritta in Kotlin con Jetpack Compose e Media3/ExoPlayer. Richiede Android 8.0 o successivo.

## Installare l'APK

1. Copia `FLACPlayer-1.1.0.apk` sul telefono, via USB o in qualsiasi altro modo.
2. Aprilo dall'app File del telefono.
3. Se Android lo chiede, consenti l'installazione da quella app.
4. Apri FLAC Player e concedi l'accesso alla musica e alle notifiche.

## Trasferire la musica

**Via USB:** collega il telefono al PC, scegli **Trasferimento file** sul telefono, poi in Esplora file copia file FLAC o cartelle in `Music`. Riapri l'app: i brani vengono trovati da soli. I file restano dove li hai messi.

**Con IMPORTA MUSICA:** scegli file o una cartella. I brani vengono copiati nella cartella privata dell'app.

## Aggiornare l'app

Installa il nuovo APK **sopra** quello esistente: libreria, playlist e preferiti restano. Funziona solo con un APK firmato dalla stessa chiave.

**Conserva la chiave.** La chiave è in `C:\Users\Dario\.flacplayer\`: `release.jks` e `keystore.properties`, che contiene la password. Se la perdi, il telefono rifiuterà gli aggiornamenti e dovrai disinstallare l'app, perdendo playlist e preferiti. Fanne una copia di sicurezza e non metterla su GitHub.

## Ricompilare

Installa [Android Studio](https://developer.android.com/studio), copia `keystore.properties` in questa cartella e lancia:

```bash
gradlew.bat :app:testDebugUnitTest :app:assembleRelease
```

L'APK viene creato in `app/build/outputs/apk/release/`.

## Differenze rispetto a iOS

| | iOS | Android |
|---|---|---|
| Decoder | libFLAC incluso nell'app | Decoder FLAC di Android, tramite ExoPlayer |
| Passaggio tra brani | Breve pausa | Senza pausa tra i brani, quando il formato lo consente |
| Musica via USB | Nella cartella dell'app | In qualsiasi cartella del telefono, per esempio `Music` |
| Elimina brano | Cancella sempre il file | Cancella i file importati. Quelli copiati via USB escono solo dalla libreria |
| FLAC multicanale | Rifiutati | Non bloccati dall'app, non provati |
| Testi | Pronti per la traduzione | Solo italiano, scritti nel codice |

## Qualità audio

L'audio viene decodificato in float a 32 bit, senza normalizzazione. L'equalizzatore è facoltativo e spento di default: si apre dal lettore e lavora con le bande del telefono, a cui i preset vengono adattati. Quando è attivo, il volume si abbassa quanto basta a compensare l'aumento maggiore, per evitare distorsioni. Android di norma mescola e ricampiona tutto alla frequenza del dispositivo, spesso 48 kHz. La schermata In riproduzione mostra la frequenza del file e quella di uscita del sistema. L'app non dichiara una riproduzione bit-perfect.
