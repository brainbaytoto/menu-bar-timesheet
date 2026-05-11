import SwiftUI

/// Text field for HH:MM time entry that normalises on commit (focus loss or Return):
/// "0700" → "07:00", "730" → "07:30", "7:30" → "07:30", "1530" → "15:30".
/// Invalid input reverts to the previous valid value.
struct TimeField: View {
    @Binding var hhmm: String
    let width: CGFloat
    let isEnabled: Bool

    @State private var editing: String
    @FocusState private var isFocused: Bool

    init(hhmm: Binding<String>, width: CGFloat = 80, isEnabled: Bool = true) {
        self._hhmm = hhmm
        self.width = width
        self.isEnabled = isEnabled
        self._editing = State(initialValue: hhmm.wrappedValue)
    }

    var body: some View {
        TextField("", text: $editing)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .focused($isFocused)
            .disabled(!isEnabled)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
            .onChange(of: hhmm) { _, new in
                if !isFocused { editing = new }
            }
    }

    private func commit() {
        if let normalized = Self.normalize(editing) {
            hhmm = normalized
            editing = normalized
        } else {
            editing = hhmm
        }
    }

    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let h: Int
        let m: Int

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let hh = Int(parts[0]),
                  let mm = Int(parts[1].isEmpty ? "0" : String(parts[1]))
            else { return nil }
            h = hh
            m = mm
        } else {
            let digits = trimmed.filter(\.isNumber)
            guard digits.count == trimmed.count else { return nil }  // reject letters/symbols
            switch digits.count {
            case 1, 2:
                guard let hh = Int(digits) else { return nil }
                h = hh; m = 0
            case 3:
                guard let hh = Int(String(digits.prefix(1))),
                      let mm = Int(String(digits.suffix(2))) else { return nil }
                h = hh; m = mm
            case 4:
                guard let hh = Int(String(digits.prefix(2))),
                      let mm = Int(String(digits.suffix(2))) else { return nil }
                h = hh; m = mm
            default:
                return nil
            }
        }

        guard (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }
}
