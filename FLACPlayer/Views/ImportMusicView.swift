import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Selettore nativo dei documenti: file FLAC o cartelle, anche più di uno.
    @MainActor
    func musicImporter(isPresented: Binding<Bool>, library: MusicLibraryManager) -> some View {
        let flac = UTType(filenameExtension: "flac", conformingTo: .audio) ?? .audio
        return fileImporter(
            isPresented: isPresented,
            allowedContentTypes: [flac, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                library.importItems(urls)
            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Pannello di importazione in testa alla libreria: pulsante, avanzamento ed esito.
struct ImportMusicView: View {
    let onImport: () -> Void

    @EnvironmentObject var library: MusicLibraryManager
    @State private var isShowingUSBHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onImport) {
                Text("IMPORTA MUSICA")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundColor(.black)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.borderless)
            .disabled(library.progress != nil)

            if let progress = library.progress {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.title)
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                    if progress.total > 0 {
                        ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if let result = library.lastResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
            }

            Button {
                isShowingUSBHelp = true
            } label: {
                Label("Trasferire musica via USB da Windows", systemImage: "cable.connector")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .sheet(isPresented: $isShowingUSBHelp) {
            USBTransferHelpView()
        }
    }
}

struct USBTransferHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Da Windows") {
                    Label("Collega l'iPhone al PC con il cavo USB.", systemImage: "1.circle")
                    Label("Apri Dispositivi Apple o iTunes e seleziona l'iPhone.", systemImage: "2.circle")
                    Label("Apri la sezione File e scegli FLAC Player.", systemImage: "3.circle")
                    Label("Trascina i file FLAC o intere cartelle nella finestra.", systemImage: "4.circle")
                    Label("Riapri FLAC Player: i nuovi brani vengono rilevati da soli.", systemImage: "5.circle")
                }
                Section {
                    Text("I file non vengono convertiti. I duplicati vengono riconosciuti dal contenuto e ignorati. La musica è esclusa dai backup di iCloud: conserva gli originali sul PC.")
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .navigationTitle("Trasferimento USB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}
