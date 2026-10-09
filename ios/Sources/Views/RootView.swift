import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(WhistleSession.self) private var session
    @State private var midiURL: URL?
    @State private var copied = false
    @State private var importing = false
    @State private var showSpeak = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PitchMeter(live: session.live, recording: session.isRecording)
                    if !session.notes.isEmpty {
                        results
                    } else if !session.isRecording {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            transport
        }
        .clipped()
        .onChange(of: session.nameLine) { _, _ in
            midiURL = session.notes.isEmpty ? nil : try? session.midiURL()
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: midiTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    session.importMIDI(from: url)
                }
            case .failure(let error):
                session.errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            guard isMIDI(url) else { return }
            session.importMIDI(from: url)
        }
        .sheet(isPresented: $showSpeak) {
            SpeakSheet()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ON-DEVICE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.brass)
                Text("Whistler")
                    .font(.system(size: 40, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.paper)
                Text("Whistle a melody. Get the notes.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Speak") { showSpeak = true }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.brass, in: Capsule())
                .foregroundStyle(Theme.ink)
                .buttonStyle(.plain)
                .accessibilityLabel("Speak a line")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A quiet room helps.")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(Theme.paper)
            Text("Hold each pitch a beat, leave a little air between notes, and skip heavy vibrato if you want a cleaner score. Or open a MIDI file and we’ll play it.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Import MIDI") { importing = true }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.brass)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.muted.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        )
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.importedName == nil ? "The tune" : session.importedName!)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(session.autotuneEnabled ? "Pitch Fix on" : "As whistled") {
                    session.toggleAutotune()
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(session.autotuneEnabled ? Theme.brass : Theme.ink2, in: Capsule())
                .foregroundStyle(session.autotuneEnabled ? Theme.ink : Theme.muted)
                .buttonStyle(.plain)
            }
            if let key = session.keyLabel {
                Text("Heard as \(key). Play notes is the cleaned take; Original is you.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(session.nameLine)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.brass)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            NoteRollView(notes: session.notes, duration: max(session.transcription?.duration ?? 1, lastEnd), selectedID: session.selectedNoteID) { id in
                session.selectedNoteID = id
            }
            .frame(minWidth: 0, maxWidth: .infinity)

            if session.selectedNote != nil {
                HStack(spacing: 10) {
                    Text(Notes.midiToName(session.selectedNote!.midi, ascii: true))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(Theme.paper)
                    Spacer(minLength: 0)
                    Button("♯ up") { session.bumpSelected(by: 1) }
                    Button("♭ down") { session.bumpSelected(by: -1) }
                    Button("drop") { session.dropSelected() }
                        .foregroundStyle(Theme.blood)
                }
                .font(.system(size: 14, weight: .medium))
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 16))
            }

            Text("STAFF")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                StaffView(notes: session.notes)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))

            Text("GUITAR TAB")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 8) {
                if let shift = session.tab.shiftLabel {
                    Text(shift)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(session.tab.ascii)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.inkText)
                        .padding(14)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], alignment: .leading, spacing: 8) {
                chip("Play notes", action: session.playScore)
                chip("Stop", action: session.stopPlayback)
                if session.hasOriginal {
                    chip("Original", action: session.playOriginal)
                }
                chip("Copy notes") {
                    UIPasteboard.general.string = session.nameLine
                    copied = true
                }
                chip("Copy tab") {
                    UIPasteboard.general.string = session.tab.ascii
                    copied = true
                }
                if let midiURL {
                    ShareLink(item: midiURL, preview: SharePreview("whistler.mid", image: Image(systemName: "music.note"))) {
                        Text("Share MIDI")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Theme.ink2, in: Capsule())
                            .foregroundStyle(Theme.paper)
                    }
                }
                chip("Import MIDI") { importing = true }
                chip("Clear", action: session.clear)
            }
            if copied {
                Text("Copied")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.brass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        VStack(spacing: 14) {
            Button(action: session.toggle) {
                ZStack {
                    Circle()
                        .fill(session.isRecording ? Theme.blood : Theme.ink2)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle().stroke(session.isRecording ? Theme.blood : Theme.brass, lineWidth: 4)
                        )
                        .shadow(color: session.isRecording ? Theme.blood.opacity(0.45) : .clear, radius: 18)
                    RoundedRectangle(cornerRadius: session.isRecording ? 6 : 32)
                        .fill(Theme.paper)
                        .frame(
                            width: session.isRecording ? 28 : 54,
                            height: session.isRecording ? 28 : 54
                        )
                }
            }
            .accessibilityLabel(session.isRecording ? "Stop recording" : "Start recording")

            HStack(spacing: 8) {
                Text(timeString)
                    .font(.system(size: 13, design: .monospaced))
                Text("·")
                Text(status)
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.muted)

            if let error = session.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.blood)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 8) {
                ForEach(SourceMode.allCases) { mode in
                    Button {
                        session.mode = mode
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(session.mode == mode ? Theme.brass : Theme.ink2, in: Capsule())
                            .foregroundStyle(session.mode == mode ? Theme.ink : Theme.muted)
                    }
                    .disabled(session.isRecording)
                }
            }

            HStack(spacing: 16) {
                Button("Play a demo whistle") {
                    session.runDemo()
                }
                Button("Import MIDI") {
                    importing = true
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.brass)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.ink)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.ink2, in: Capsule())
                .foregroundStyle(Theme.paper)
        }
        .buttonStyle(.plain)
    }

    private var timeString: String {
        let s = max(0, session.elapsed)
        let m = Int(s) / 60
        let r = Int(s) % 60
        let t = Int((s * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", m, r, t)
    }

    private var status: String {
        if session.isRecording { return "whistling…" }
        if session.isBusy { return "transcribing…" }
        return "idle"
    }

    private var lastEnd: Double {
        session.notes.reduce(0.5) { max($0, $1.start + $1.duration) }
    }

    private var midiTypes: [UTType] {
        var types: [UTType] = [.midi]
        if let mid = UTType(filenameExtension: "mid") { types.append(mid) }
        if let midi = UTType(filenameExtension: "midi") { types.append(midi) }
        return types
    }

    private func isMIDI(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mid" || ext == "midi"
    }
}

struct PitchMeter: View {
    var live: LivePitch
    var recording: Bool

    var body: some View {
        let hasPitch = live.midi != nil
        let name = hasPitch ? Notes.midiToName(Int(round(live.midi!))) : "—"
        let cents = hasPitch ? Notes.centsOff(live.midi!) : 0
        let needle = max(-50, min(50, cents))
        VStack(spacing: 12) {
            Text(recording ? "LISTENING" : "READY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Theme.muted)
            Text(name)
                .font(.system(size: 72, weight: .medium, design: .serif))
                .foregroundStyle(Theme.paper)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(hasPitch ? String(format: "%.1f Hz", live.frequency ?? 0) : "silence")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink2)
                    Capsule()
                        .fill(Theme.brass)
                        .frame(width: 2)
                        .offset(x: geo.size.width / 2)
                    Circle()
                        .fill(Theme.brass)
                        .frame(width: 14, height: 14)
                        .offset(x: geo.size.width / 2 + CGFloat(needle) / 100 * geo.size.width - 7)
                }
            }
            .frame(height: 14)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.ink2)
                .overlay {
                    if recording {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Theme.blood.opacity(0.18))
                    }
                }
        )
    }
}

struct NoteRollView: View {
    var notes: [NoteEvent]
    var duration: Double
    var selectedID: String?
    var onSelect: (String) -> Void

    var body: some View {
        let minMidi = (notes.map(\.midi).min() ?? 72) - 2
        let maxMidi = (notes.map(\.midi).max() ?? 76) + 2
        let span = max(1, maxMidi - minMidi)
        let width = max(340, duration * 140)
        ScrollView(.horizontal, showsIndicators: false) {
            Canvas { context, size in
                for midi in minMidi...maxMidi {
                    let y = CGFloat(maxMidi - midi) / CGFloat(span) * (size.height - 16) + 8
                    var path = Path()
                    path.move(to: CGPoint(x: 40, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(midi % 12 == 0 ? Theme.rule : Theme.rule.opacity(0.45)), lineWidth: midi % 12 == 0 ? 1.2 : 0.6)
                    if midi % 12 == 0 {
                        context.draw(
                            Text(Notes.midiToName(midi, ascii: true)).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted),
                            at: CGPoint(x: 4, y: y),
                            anchor: .leading
                        )
                    }
                }
                for note in notes {
                    let x = 48 + (note.start / duration) * (size.width - 64)
                    let w = max(12, (note.duration / duration) * (size.width - 64))
                    let y = CGFloat(maxMidi - note.midi) / CGFloat(span) * (size.height - 16) + 2
                    let rect = CGRect(x: x, y: y, width: w, height: 12)
                    context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(note.id == selectedID ? Theme.blood : Theme.brass))
                }
            }
            .frame(width: width, height: 160)
            .contentShape(Rectangle())
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                for note in notes {
                    let x = 48 + (note.start / duration) * (width - 64)
                    let w = max(12, (note.duration / duration) * (width - 64))
                    if location.x >= x - 6 && location.x <= x + w + 6 {
                        onSelect(note.id)
                        return
                    }
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StaffView: View {
    var notes: [NoteEvent]

    var body: some View {
        let width = max(320, 80 + CGFloat(notes.count) * 36)
        Canvas { context, size in
            let lineGap: CGFloat = 12
            let top: CGFloat = 28
            let origin = diatonic(64)
            for i in 0..<5 {
                var line = Path()
                let y = top + CGFloat(i) * lineGap
                line.move(to: CGPoint(x: 48, y: y))
                line.addLine(to: CGPoint(x: size.width - 12, y: y))
                context.stroke(line, with: .color(Theme.inkText), lineWidth: 1.1)
            }
            context.draw(Text("𝄞").font(.system(size: 42, design: .serif)).foregroundColor(Theme.inkText), at: CGPoint(x: 28, y: top + 2.2 * lineGap))
            for (i, note) in notes.enumerated() {
                let x = 72 + CGFloat(i) * 36
                let steps = CGFloat(diatonic(note.midi) - origin)
                let y = top + 4 * lineGap - steps * (lineGap / 2)
                let pc = ((note.midi % 12) + 12) % 12
                if [1, 3, 6, 8, 10].contains(pc) {
                    context.draw(Text("♯").font(.system(size: 14, design: .serif)).foregroundColor(Theme.inkText), at: CGPoint(x: x - 10, y: y))
                }
                context.fill(Path(ellipseIn: CGRect(x: x, y: y - 5, width: 14, height: 10)), with: .color(Theme.inkText))
                if note.duration < 1.6 {
                    var stem = Path()
                    stem.move(to: CGPoint(x: x + 13, y: y))
                    stem.addLine(to: CGPoint(x: x + 13, y: y - 28))
                    context.stroke(stem, with: .color(Theme.inkText), lineWidth: 1.3)
                }
            }
        }
        .frame(width: width, height: 140)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func diatonic(_ midi: Int) -> Int {
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        let steps = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][pc]
        return (octave - 4) * 7 + steps
    }
}
