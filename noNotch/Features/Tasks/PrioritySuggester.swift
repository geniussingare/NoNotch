import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On macOS 26 with Apple Intelligence, suggests a priority and project for new tasks
/// using the on-device model. Suggestions are offered, never applied silently.
@MainActor
@Observable
final class PrioritySuggester {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    var isEnabled: Bool {
        isAvailable && UserDefaults.standard.isEnabled(SettingsKey.featureSuggestions)
    }

    /// Asks the model about a task the user left without a priority or project.
    func suggest(for task: TaskItem, knownProjects: [String]) async -> TaskSuggestion? {
        guard isEnabled else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return await Self.ask(title: task.title, knownProjects: knownProjects)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct Guess {
        @Guide(description: "How urgent or important the task sounds", .anyOf(["none", "low", "medium", "high"]))
        var priority: String
        @Guide(description: "A short project name (one or two words), reusing an existing one when it fits, or empty if none fits")
        var project: String
    }

    @available(macOS 26, *)
    private static func ask(title: String, knownProjects: [String]) async -> TaskSuggestion? {
        let session = LanguageModelSession(instructions: """
            You triage personal to-do items. Pick a priority: high only for urgent or deadline-bound items, \
            low for nice-to-haves, none when it's unclear. Suggest a project only when the task clearly belongs to one.
            """)
        let projects = knownProjects.isEmpty ? "none yet" : knownProjects.prefix(20).joined(separator: ", ")
        do {
            let guess = try await session.respond(
                to: "Task: \(title)\nExisting projects: \(projects)",
                generating: Guess.self
            ).content
            let suggestion = TaskSuggestion(
                priority: TaskPriority(name: guess.priority),
                project: guess.project.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))).nilIfEmpty
            )
            return suggestion.isEmpty ? nil : suggestion
        } catch {
            return nil
        }
    }
    #endif
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
