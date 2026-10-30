import SwiftUI

enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.11)
    static let separator = Color(white: 0.2)
    static let secondaryText = Color(white: 0.6)
}

extension View {
    /// Aspetto comune delle liste: sfondo nero e nessuno sfondo di sistema.
    func flacListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Attenzione",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message.wrappedValue ?? "") }
        )
    }
}

enum TimeFormatting {
    /// 75 → "1:15"; 3700 → "1:01:40".
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
