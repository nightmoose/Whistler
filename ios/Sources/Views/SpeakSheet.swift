import SwiftUI

struct SpeakSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = SpeakModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Write the line the way it should be spoken. How is the delivery. Grok writes a 48 kHz WAV you can share into a session.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    keySection
                    field("Line", text: $model.text, limit: SpeechMarkup.textLimit, axis: .vertical)
                    field("How", text: $model.how, limit: SpeechMarkup.howLimit, axis: .vertical)
                    chips
                    controls
                    Button(model.busy ? "Generating…" : "Generate WAV") {
                        Task { await model.generate() }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.brass, in: Capsule())
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.plain)
                    .disabled(model.busy || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.hasKey)
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.paper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let fileURL = model.fileURL {
                        HStack(spacing: 8) {
                            Button("Play") { model.play() }
                                .buttonStyle(BrassChipStyle())
                            ShareLink(item: fileURL, preview: SharePreview(fileURL.lastPathComponent, image: Image(systemName: "waveform"))) {
                                Text("Share WAV")
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Theme.brass, in: Capsule())
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    if !model.spoken.isEmpty, model.spoken != model.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.spoken)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(Theme.brass)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Keep this reading") { model.keepReading() }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.brass)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 16))
                    }
                    DisclosureGroup("Tags you can type in the line") {
                        Text("Sounds: " + SpeechMarkup.inlineTags.map { "[\($0)]" }.joined(separator: " "))
                        Text("Wrap a phrase: " + SpeechMarkup.wrapTags.map { "<\($0)>…</\($0)>" }.joined(separator: " "))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.ink)
            .navigationTitle("Speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.prepare() }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasKey && !model.replacingKey {
                HStack {
                    Text("Key is on this phone.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Replace") { model.replacingKey = true }
                    Button("Remove") { model.forgetKey() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.brass)
            } else {
                SecureField("xAI API key", text: $model.keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.paper)
                Button("Save key on this phone") { model.saveKey() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.brass)
                    .disabled(model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpeechMarkup.directionPhrases, id: \.self) { phrase in
                    Button(phrase) { model.addDirection(phrase) }
                        .buttonStyle(BrassChipStyle())
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled("Voice") {
                Picker("Voice", selection: $model.voiceId) {
                    ForEach(model.voices) { voice in
                        Text(voice.name).tag(voice.voiceId)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.brass)
            }
            labeled("Custom voice id") {
                TextField("optional", text: $model.customVoice)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 12))
            }
            labeled("Language") {
                Picker("Language", selection: $model.language) {
                    ForEach(SpeechMarkup.languages, id: \.code) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.brass)
            }
            labeled("Speed \(String(format: "%.2f×", model.speed))") {
                Slider(value: $model.speed, in: SpeechMarkup.speedMin...SpeechMarkup.speedMax, step: 0.05)
                    .tint(Theme.brass)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, limit: Int, axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            TextField(title, text: text, axis: axis)
                .lineLimit(3...8)
                .onChange(of: text.wrappedValue) { _, value in
                    if value.count > limit { text.wrappedValue = String(value.prefix(limit)) }
                }
                .padding(12)
                .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Theme.paper)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            content()
        }
    }
}

private struct BrassChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.ink2, in: Capsule())
            .foregroundStyle(Theme.paper)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
