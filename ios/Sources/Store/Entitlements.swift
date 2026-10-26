import Foundation

/// Product identifiers sold in the app. The price lives in App Store Connect;
/// the app only ever shows `Product.displayPrice`.
enum ProProduct {
    static let id = "com.nightmoose.whistler.pro"
    static let all: Set<String> = [id]
}

/// Everything the one-time Pro unlock opens up.
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case midiExport
    case staffNotation
    case guitarTab
    case unlimitedRecording
    case humMode
    case anyMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midiExport: return "MIDI export & share"
        case .staffNotation: return "Staff notation"
        case .guitarTab: return "Guitar tab"
        case .unlimitedRecording: return "Unlimited recording length"
        case .humMode: return "Hum mode"
        case .anyMode: return "Any-source mode"
        }
    }

    var detail: String {
        switch self {
        case .midiExport: return "Send your tune to a DAW or another app as a .mid file."
        case .staffNotation: return "See the melody on a treble staff."
        case .guitarTab: return "Get a playable six-string tab and copy it."
        case .unlimitedRecording: return "Free takes stop at \(Int(RecordingCap.freeLimit)) seconds. Pro has no cap."
        case .humMode: return "Tuned for a low singing or humming voice."
        case .anyMode: return "A wider net for instruments and other sources."
        }
    }

    var symbol: String {
        switch self {
        case .midiExport: return "square.and.arrow.up"
        case .staffNotation: return "music.note.list"
        case .guitarTab: return "guitars"
        case .unlimitedRecording: return "infinity"
        case .humMode: return "mouth"
        case .anyMode: return "waveform"
        }
    }
}

/// Pure gating rules. One check per gated feature; free features never ask.
struct Gate: Equatable, Sendable {
    var isPro: Bool

    func allows(_ feature: ProFeature) -> Bool {
        isPro
    }

    func allows(mode: SourceMode) -> Bool {
        guard let feature = mode.proFeature else { return true }
        return allows(feature)
    }
}

extension SourceMode {
    /// The Pro feature a source mode needs, or nil if it is free.
    var proFeature: ProFeature? {
        switch self {
        case .whistle: return nil
        case .hum: return .humMode
        case .any: return .anyMode
        }
    }
}

/// The free-tier recording cap.
enum RecordingCap {
    static let freeLimit: TimeInterval = 15

    /// Returns true when a take that has run for `elapsed` seconds must stop now.
    static func shouldStop(elapsed: TimeInterval, isPro: Bool) -> Bool {
        guard !isPro else { return false }
        return elapsed >= freeLimit
    }

    /// Seconds left before the cap, or nil when there is no cap.
    static func remaining(elapsed: TimeInterval, isPro: Bool) -> TimeInterval? {
        guard !isPro else { return nil }
        return max(0, freeLimit - elapsed)
    }
}

/// Why the paywall opened. Drives the headline on the sheet.
struct PaywallTrigger: Identifiable, Equatable {
    enum Reason: Equatable {
        case feature(ProFeature)
        case recordingCap
        case browse
    }

    let id = UUID()
    let reason: Reason

    static func == (lhs: PaywallTrigger, rhs: PaywallTrigger) -> Bool {
        lhs.reason == rhs.reason
    }
}
