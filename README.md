# FLAC Player

Lettore musicale nativo per iPhone: riproduce file FLAC locali fino a 24 bit / 192 kHz, senza account, senza pubblicità e senza Internet. Si sviluppa da Windows, si compila su Codemagic e si installa con Sideloadly.

> **Stato del progetto.** Il decoder è stato collaudato su Windows (vedi [docs/REPORT_FASI.md](docs/REPORT_FASI.md)). Il codice Swift non è ancora stato compilato: su Windows non esiste un compilatore per iOS. La prima compilazione avverrà su Codemagic e il collaudo finale sul tuo iPhone.

## Indice

- [Come funziona il percorso](#come-funziona-il-percorso)
- [Guida passo passo da Windows](#guida-passo-passo-da-windows) (sezioni A–O)
- [Trasferire la musica](#trasferire-la-musica)
- [Collaudo sull'iPhone](#collaudo-delliphone)
- [Qualità audio: cosa fa davvero l'app](#qualità-audio-cosa-fa-davvero-lapp)
- [Limiti noti](#limiti-noti)
- [Se qualcosa non funziona](#se-qualcosa-non-funziona)
- [Struttura del progetto](#struttura-del-progetto)

## Come funziona il percorso

Sono quattro passaggi distinti, svolti in posti diversi:

| Passaggio | Dove | Risultato |
|---|---|---|
| 1. Compilazione | Mac cloud di Codemagic | L'app compilata per iPhone |
| 2. Creazione dell'IPA | Mac cloud di Codemagic | `FLACPlayer.ipa`, **non firmato** |
| 3. Firma | Sideloadly sul tuo PC | L'app firmata con il tuo Apple ID |
| 4. Installazione | Sideloadly, via USB | L'app sul tuo iPhone |

La firma avviene solo sul tuo PC: su GitHub e su Codemagic non finiscono mai password, certificati o profili.

### Account Apple gratuito o a pagamento

| | Gratuito | Developer a pagamento (99 $/anno) |
|---|---|---|
| Durata della firma | 7 giorni | Fino a 1 anno |
| App installabili con Sideloadly | 3 | Nessun limite indicato |
| Nuovi App ID | 10 ogni 7 giorni | Nessun limite indicato |
| Audio in background e condivisione file | Funzionano | Funzionano |

Con **entrambi** gli account l'IPA si firma con Sideloadly. Codemagic non può firmare con un account gratuito: la sua firma automatica richiede una chiave API di App Store Connect, che esiste solo per gli account a pagamento. Anche con l'account a pagamento non serve configurare nulla su Codemagic.

---

## Guida passo passo da Windows

### A. Installa Visual Studio Code

1. Scarica l'installer da <https://code.visualstudio.com>.
2. Eseguilo e lascia le opzioni predefinite.
3. Facoltativo: dal pannello Estensioni installa **Swift** per avere i colori nella sintassi. Non permette di compilare per iOS.

### B. Installa Git per Windows

1. Scarica Git da <https://git-scm.com/download/win> e installalo con le opzioni predefinite.
2. Apri **Git Bash** e indica il tuo nome e la tua email:

   ```bash
   git config --global user.name "Il tuo nome"
   git config --global user.email "la-tua-email@esempio.it"
   ```

### C. Crea il repository privato su GitHub

1. Accedi a <https://github.com> e crea un account, se non ce l'hai.
2. Clicca **New repository**.
3. Chiamalo `flac-player` e seleziona **Private**.
4. **Non** aggiungere README, `.gitignore` o licenza: esistono già nel progetto.
5. Clicca **Create repository** e copia l'indirizzo, del tipo `https://github.com/TUO-NOME/flac-player.git`.

### D. Apri il progetto in Visual Studio Code

1. Apri VS Code.
2. **File → Apri cartella** e scegli la cartella del progetto.
3. Apri il terminale integrato con **Terminale → Nuovo terminale**.

La prima volta collega la cartella a GitHub (sostituisci l'indirizzo):

```bash
git init
git add .
git commit -m "Prima versione di FLAC Player"
git branch -M main
git remote add origin https://github.com/TUO-NOME/flac-player.git
git push -u origin main
```

Al primo `push` si apre il browser per accedere a GitHub.

### E. Modifica il codice

I file si trovano in `FLACPlayer/`. Salva con `Ctrl+S`. Su Windows non puoi eseguire l'app: ogni prova passa da Codemagic e Sideloadly.

### F. Invia gli aggiornamenti a GitHub

```bash
git add .
git commit -m "Descrizione della modifica"
git push
```

### G. Collega GitHub a Codemagic

1. Vai su <https://codemagic.io/start> e accedi con GitHub.
2. Autorizza Codemagic ad accedere al repository `flac-player`.
3. Clicca **Add application**, scegli GitHub e poi il repository.
4. Quando chiede il tipo di progetto, scegli la configurazione tramite `codemagic.yaml`.

Il piano gratuito include 500 minuti al mese su Mac mini M2. Lo storico delle compilazioni e gli artifact restano disponibili per 30 giorni.

### H. Avvia la compilazione

1. Apri l'applicazione su Codemagic e clicca **Start new build**.
2. Scegli il ramo `main`.
3. Scegli il workflow **IPA per Sideloadly (con test)**.
4. Clicca **Start new build**.

Il workflow genera il progetto Xcode con XcodeGen, esegue i test, compila, crea l'IPA e ne controlla il contenuto. Se un passaggio fallisce, la compilazione si ferma e non produce un IPA.

Per piccole modifiche puoi usare **IPA per Sideloadly (senza test)**, che consuma meno minuti.

### I. Scarica l'IPA

A compilazione terminata, nella sezione **Artifacts** scarica `FLACPlayer.ipa`. I file `.log` nello stesso elenco servono se qualcosa va storto.

### J. Installa Sideloadly

1. Scarica Sideloadly da <https://sideloadly.io>.
2. Installalo con le opzioni predefinite.

### K. Installa i componenti Apple

Sideloadly richiede le versioni di **iTunes e iCloud scaricate dal web**, non quelle del Microsoft Store.

1. Se hai iTunes o iCloud dal Microsoft Store, disinstallali.
2. Scarica iTunes e iCloud dai collegamenti presenti sulla pagina di Sideloadly.
3. Installali e riavvia il PC.

### L. Collega l'iPhone

1. Collega l'iPhone al PC con un cavo USB e sbloccalo.
2. Tocca **Autorizza** sull'iPhone e inserisci il codice.
3. Apri Sideloadly: l'iPhone deve comparire nel campo del dispositivo.
4. Su iOS 16 o successivo, attiva **Impostazioni → Privacy e sicurezza → Modalità sviluppatore**. L'iPhone si riavvia.

### M. Firma e installa l'IPA

1. Trascina `FLACPlayer.ipa` nella finestra di Sideloadly.
2. Inserisci il tuo Apple ID e clicca **Start**.
3. Inserisci la password e il codice di verifica a due fattori quando richiesti. Sideloadly li invia solo ai server Apple.
4. Attendi il messaggio **Done**.
5. Sull'iPhone apri **Impostazioni → Generali → VPN e gestione dispositivo**, tocca la tua email e scegli **Autorizza**.
6. Apri FLAC Player.

### N. Gestisci la validità della firma

**Account gratuito:** dopo 7 giorni l'app non si apre più. La musica e i dati **restano sul telefono**.

- **Rinnovo manuale:** ripeti la sezione M con lo stesso IPA e lo stesso Apple ID.
- **Rinnovo automatico:** in Sideloadly attiva l'opzione di aggiornamento automatico durante l'installazione. Il servizio di Sideloadly rinnova l'app quando l'iPhone è collegato via USB o raggiungibile via Wi‑Fi, con il PC acceso.

**Account a pagamento:** ripeti la procedura una volta l'anno.

### O. Aggiorna l'app senza perdere la musica

> **Non eliminare mai l'app dall'iPhone per aggiornarla.** Eliminandola cancelli anche tutta la musica copiata al suo interno, le playlist e i preferiti.

iOS sostituisce l'app e conserva i dati solo se la nuova installazione ha **lo stesso Bundle Identifier** ed è firmata con **lo stesso Apple ID**.

1. Modifica il codice e invialo a GitHub (sezione F).
2. Compila su Codemagic (sezione H) e scarica il nuovo IPA.
3. Installalo con Sideloadly **sopra** l'app esistente, con lo stesso Apple ID.

Il Bundle Identifier è in `project.yml`, alla voce `PRODUCT_BUNDLE_IDENTIFIER`:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.dario.flacplayer.personal
```

Non cambiarlo dopo la prima installazione: per iOS sarebbe un'altra app, con una libreria vuota. Se Sideloadly segnala che il Bundle Identifier è già in uso da un altro sviluppatore, cambialo **prima** della prima installazione.

Se nelle opzioni avanzate di Sideloadly imposti un Bundle ID personalizzato, usa sempre lo stesso a ogni installazione.

---

## Trasferire la musica

I file vengono copiati senza conversioni. L'app riconosce i duplicati dal contenuto (SHA‑256), anche se hanno un altro nome.

### Con il pulsante IMPORTA MUSICA

Nella Libreria tocca **IMPORTA MUSICA** e scegli file o cartelle da File, iCloud Drive o una chiavetta. I file vengono copiati nell'app e organizzati in `Music/Artista/Album/`. Gli originali non vengono toccati.

### Via USB da Windows

**Con Dispositivi Apple**

1. Collega l'iPhone e apri l'app **Dispositivi Apple**.
2. Seleziona l'iPhone nella barra laterale e apri **File**.
3. Trascina file `.flac` o intere cartelle su **FLAC Player**.

**Con iTunes**, installato per Sideloadly:

1. Collega l'iPhone e clicca sull'icona del dispositivo.
2. Apri **Condivisione file** e seleziona **FLAC Player**.
3. Trascina file o cartelle nell'elenco dei documenti.

Riapri FLAC Player: la scansione parte da sola e trova i nuovi brani. Puoi avviarla anche con il pulsante di aggiornamento in alto nella Libreria.

Sideloadly richiede iTunes. La sua documentazione non parla di Dispositivi Apple, quindi la convivenza dei due non è verificata. Se dopo aver installato Dispositivi Apple Sideloadly non vede più l'iPhone, usa iTunes anche per la musica.

La cartella dell'app compare anche nell'app **File** dell'iPhone, in **Sul mio iPhone → FLAC Player**.

### Backup

La musica è esclusa dai backup di iCloud, per non riempire lo spazio con decine di GB. **Conserva gli originali sul PC**: se elimini l'app o ripristini l'iPhone, dovrai ricopiarli.

---

## Collaudo sull'iPhone

I test automatici non provano che il suono esca davvero. Dopo la prima installazione controlla questi punti:

**Importazione e libreria**

- [ ] Importa un FLAC con IMPORTA MUSICA.
- [ ] Importa più file insieme e poi una cartella.
- [ ] Copia file via USB e controlla che compaiano riaprendo l'app.
- [ ] Importa di nuovo lo stesso file: deve risultare duplicato.
- [ ] Controlla titoli, artisti, album e copertine.

**Riproduzione** (idealmente con file 16/44,1, 24/96 e 24/192)

- [ ] Riproduci, metti in pausa e riprendi.
- [ ] Passa al brano successivo e al precedente.
- [ ] Sposta la barra di avanzamento avanti e indietro.
- [ ] Controlla la riga del formato sotto l'album.

**Modalità**

- [ ] Ripeti brano: il brano ricomincia quando finisce.
- [ ] Ripeti coda: dopo l'ultimo brano riparte il primo.
- [ ] Ripetizione disattivata: alla fine della coda l'audio si ferma.
- [ ] Shuffle: il brano corrente continua. Spegnendolo torna l'ordine originale.

**Coda, playlist e preferiti**

- [ ] Riordina e rimuovi brani dalla coda, poi svuotala.
- [ ] Crea, modifica ed elimina una playlist.
- [ ] Aggiungi e rimuovi un preferito.
- [ ] Chiudi forzatamente l'app e riaprila: dati e coda devono essere ancora lì.

**Background e interruzioni**

- [ ] Blocca lo schermo: la musica continua.
- [ ] Vai alla schermata Home e apri un'altra app: la musica continua.
- [ ] Usa i controlli dalla schermata di blocco e dal Centro di Controllo.
- [ ] Ricevi una telefonata: la musica si ferma e, se iOS lo consente, riprende dopo.
- [ ] Attiva Siri.
- [ ] Scollega le cuffie: la musica va in pausa.
- [ ] Passa a un'uscita diversa (Bluetooth o AirPlay) durante la riproduzione.

---

## Qualità audio: cosa fa davvero l'app

**Decoder.** libFLAC 1.5.0, il decoder di riferimento. L'audio decodificato è stato confrontato bit per bit con `flac.exe` ufficiale su file a 16 e 24 bit, da 44,1 a 192 kHz: identico in tutti i casi.

**Percorso audio.** `libFLAC → PCM float 32 bit → AVAudioPlayerNode → mixer → uscita`.

- Nessun equalizzatore, normalizzazione o compressione.
- I campioni fino a 24 bit restano esatti: il formato float a 32 bit li rappresenta senza arrotondamenti.
- I file sono letti a blocchi di mezzo secondo. In memoria ci sono al massimo 3 secondi di audio.
- I file originali non vengono mai modificati.

**Frequenza di uscita.** A ogni brano l'app chiede a iOS di usare la frequenza del file. È una richiesta, non una garanzia: se l'uscita non la supporta, iOS mantiene la propria e `AVAudioEngine` ricampiona. L'altoparlante interno di solito lavora a una frequenza fissa, mentre i DAC USB esterni possono arrivare più in alto: la riga del formato mostra il valore reale. Il Bluetooth ricomprime sempre l'audio.

La schermata In riproduzione mostra sia il formato del file sia la frequenza di uscita, con la scritta **ricampionata** quando le due differiscono.

**Non è una riproduzione bit-perfect dichiarata.** Il mixer di iOS resta nel percorso e non esiste un modo per verificare dall'app ciò che arriva al DAC. L'app non fa questa affermazione.

## Limiti noti

- **Tra un brano e il successivo c'è una breve pausa.** La riproduzione gapless non è implementata: si sente negli album con brani collegati, come i live.
- **Solo mono e stereo.** I FLAC multicanale vengono rifiutati con un messaggio chiaro, senza riduzione a stereo.
- **FLAC a 32 bit.** Vengono riprodotti con la precisione del float a 32 bit, cioè 24 bit effettivi.
- **Shuffle e riordino.** Lo spostamento di brani nella coda durante lo shuffle vale solo per l'ordine casuale. Spegnendo lo shuffle torna l'ordine originale.
- **Duplicati.** Riconosce i file identici byte per byte. Lo stesso brano con tag diversi conta come due brani.
- **Durata sconosciuta.** I rari FLAC che non dichiarano la durata mostrano `0:00` e la barra di avanzamento resta disattivata.
- **Firma gratuita.** Va rinnovata ogni 7 giorni.

## Se qualcosa non funziona

| Problema | Soluzione |
|---|---|
| La compilazione su Codemagic fallisce | Apri il passaggio in rosso e scarica `build/logs/archive.log` o `test.log` dagli artifact. L'errore è nelle righe che contengono `error:` |
| Codemagic non trova la versione di Xcode | Aggiorna `xcode:` in `codemagic.yaml` con una versione presente nella [documentazione di Codemagic](https://docs.codemagic.io/specs/versions-macos/) |
| Sideloadly non vede l'iPhone | Reinstalla iTunes e iCloud dal web, riavvia, tocca **Autorizza** sull'iPhone, prova un altro cavo o un'altra porta |
| `NP_E_CONN_FAILED` o `AFC_E_MUX_ERROR` | Disinstalla iTunes del Microsoft Store e installa la versione web |
| Sideloadly segnala il limite di App ID («You may create up to 10 App IDs») | L'account gratuito consente 10 App ID ogni 7 giorni: attendi o usa un altro Apple ID |
| L'app non si apre dopo qualche giorno | La firma è scaduta: ripeti la sezione M, **senza eliminare l'app** |
| «Sviluppatore non autorizzato» | Autorizzalo in **Impostazioni → Generali → VPN e gestione dispositivo** |
| FLAC Player non compare tra le app con condivisione file | Avvia l'app almeno una volta e ricollega l'iPhone |
| Un brano appare grigio con «File mancante» | Il file non c'è più. Ricopialo: il brano torna con playlist e preferiti, anche se ha un altro nome |

## Struttura del progetto

```text
project.yml              Definizione del progetto per XcodeGen
codemagic.yaml           Compilazione cloud e creazione dell'IPA
Packages/CFLAC/          libFLAC 1.5.0 (solo decoder) e bridge C
FLACPlayer/
  App/                   Avvio e collegamento dei servizi
  Models/                Brani, album, playlist, coda
  Audio/                 Decoder, motore audio, coda, Now Playing
  Services/              Database, importazione, scansione, metadati, copertine
  Views/                 Interfaccia SwiftUI
  Resources/             Icona e colori
  Config/Info.plist      Audio in background e condivisione file
FLACPlayerTests/         Test automatici e file FLAC di prova
docs/REPORT_FASI.md      Report di sviluppo, fase per fase
```

**Dove stanno i dati sull'iPhone**

```text
Documents/               Visibile da Windows: contiene solo musica
  Music/Artista/Album/   Brani importati dall'app
  (altre cartelle)       Brani copiati via USB: restano dove li metti
Library/Application Support/FLACPlayer/
  library.sqlite         Libreria, playlist, preferiti, coda
  Covers/                Copertine estratte dai file
```

Il database non è accessibile da Windows, quindi non si può cancellare per errore.

**Traduzioni.** I testi dell'interfaccia sono chiavi localizzabili con l'italiano come lingua di partenza. Per aggiungere una lingua basta un file `en.lproj/Localizable.strings` nelle risorse.

## Licenze

- libFLAC: licenza BSD a 3 clausole, testo in [Packages/CFLAC/COPYING.Xiph](Packages/CFLAC/COPYING.Xiph).
- Codice dell'app: uso personale.
