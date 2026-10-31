import AVFoundation
import Observation
import Speech
import SwiftUI

/// Speech-to-text recognised on the Mac (on-device when the language supports it).
/// One field listens at a time; each identifies itself with an `owner` string.
@MainActor
@Observable
final class Dictation {
    static let shared = Dictation()

    private(set) var owner: String?
    private(set) var level: Float = 0
    private(set) var error: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var onText: (String) -> Void = { _ in }
    @ObservationIgnored private var silence: Task<Void, Never>?

    func isListening(_ owner: String) -> Bool { self.owner == owner }

    /// Starts listening for `owner`, or stops if it already is. `onText` receives the live transcript.
    func toggle(_ owner: String, onText: @escaping (String) -> Void) {
        if self.owner == owner {
            stop()
            return
        }
        stop()
        Task { await start(owner, onText: onText) }
    }

    func stop() {
        silence?.cancel()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.finish()
        engine = nil
        request = nil
        recognition = nil
        owner = nil
        level = 0
    }

    private func start(_ owner: String, onText: @escaping (String) -> Void) async {
        error = nil
        guard await Self.authorize() else {
            error = "Allow Microphone and Speech Recognition in System Settings."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition isn't available for this language."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            error = "No microphone found."
            return
        }
        Self.installTap(on: input, format: format, request: request) { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = error.localizedDescription
            return
        }

        self.engine = engine
        self.request = request
        self.onText = onText
        self.owner = owner
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.received(text, final: isFinal || failed, owner: owner) }
        }
    }

    private func received(_ text: String?, final: Bool, owner: String) {
        guard self.owner == owner else { return }
        if let text, !text.isEmpty { onText(text) }
        if final {
            stop()
            return
        }
        // Stop after two quiet seconds.
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.owner == owner else { return }
            self?.stop()
        }
    }

    /// Runs on the audio thread: feeds the recogniser and reports a rough input level.
    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Float) -> Void
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in stride(from: 0, to: count, by: 8) { sum += samples[index] * samples[index] }
            level(min(sqrt(sum / Float(max(count / 8, 1))) * 8, 1))
        }
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func authorize() async -> Bool {
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Mic toggle that pulses with the input level while listening.
struct DictationButton: View {
    let dictation: Dictation
    let owner: String
    let onText: (String) -> Void

    var body: some View {
        let listening = dictation.isListening(owner)
        Button {
            dictation.toggle(owner, onText: onText)
        } label: {
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(listening ? .red : Design.tertiaryText)
                .symbolEffect(.variableColor.iterative, isActive: listening)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.red.opacity(listening ? 0.15 + Double(dictation.level) * 0.4 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(dictation.error ?? (listening ? "Stop dictation" : "Dictate"))
        .accessibilityLabel(Text(listening ? "Stop dictation" : "Dictate"))
        .animation(NotchViewModel.snappy, value: listening)
    }
}
