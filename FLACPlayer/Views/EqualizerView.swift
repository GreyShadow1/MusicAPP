import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { player.equalizer.isEnabled },
            set: { newValue in player.updateEqualizer { $0.isEnabled = newValue } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Attivo", isOn: isEnabled)
                } footer: {
                    Text("Quando è spento, l'audio non viene modificato.")
                }

                Section("Preset") {
                    ForEach(EqualizerSettings.presets) { preset in
                        Button {
                            player.updateEqualizer { $0.apply(preset) }
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if player.equalizer.presetName == preset.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section("Bande") {
                    ForEach(EqualizerSettings.frequencies.indices, id: \.self) { band in
                        bandRow(band)
                    }
                }
                .disabled(!player.equalizer.isEnabled)
            }
            .navigationTitle("Equalizzatore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private func bandRow(_ band: Int) -> some View {
        let frequency = EqualizerSettings.frequencies[band]
        let gain = player.equalizer.gains[band]
        return HStack(spacing: 8) {
            Text(frequency >= 1000 ? "\(Int(frequency / 1000)) kHz" : "\(Int(frequency)) Hz")
                .font(.caption)
                .foregroundColor(Theme.secondaryText)
                .frame(width: 52, alignment: .leading)
            Slider(
                value: Binding(
                    get: { gain },
                    set: { newValue in player.updateEqualizer { $0.setGain(newValue, band: band) } }
                ),
                in: -EqualizerSettings.maxGain...EqualizerSettings.maxGain
            )
            .accessibilityLabel(Text("Banda \(Int(frequency)) hertz"))
            Text(String(format: "%+.1f", gain))
                .font(.caption.monospacedDigit())
                .foregroundColor(Theme.secondaryText)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
