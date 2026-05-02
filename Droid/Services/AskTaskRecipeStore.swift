import Foundation
import os

private let askTaskRecipeLogger = Logger(subsystem: "app.droid", category: "AskTaskRecipeStore")

@MainActor
@Observable
final class AskTaskRecipeStore {
    static let shared = AskTaskRecipeStore()

    private(set) var userRecipes: [AskTaskRecipe] = []
    private let fileStore: CodableFileStore<[AskTaskRecipe]>

    var recipes: [AskTaskRecipe] {
        AskTaskRecipe.builtIns + userRecipes.sorted { $0.updatedAt > $1.updatedAt }
    }

    init(fileStore: CodableFileStore<[AskTaskRecipe]> = CodableFileStore(fileURL: DroidFileStorage.fileURL(filename: "ask-recipes.json"))) {
        self.fileStore = fileStore
        load()
    }

    func recipes(for projectID: UUID?) -> [AskTaskRecipe] {
        recipes.filter { $0.isGlobal || $0.projectID == projectID }
    }

    func save(name: String, prompt: String, projectID: UUID?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPrompt.isEmpty else { return }
        if let index = userRecipes.firstIndex(where: { sameRecipe($0, name: cleanName, projectID: projectID) }) {
            userRecipes[index].prompt = cleanPrompt
            userRecipes[index].projectID = projectID
            userRecipes[index].updatedAt = Date()
        } else {
            userRecipes.append(.user(name: cleanName, prompt: cleanPrompt, projectID: projectID))
        }
        persist()
    }

    func update(id: String, name: String, prompt: String, projectID: UUID?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPrompt.isEmpty else { return }
        guard let index = userRecipes.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else {
            save(name: cleanName, prompt: cleanPrompt, projectID: projectID)
            return
        }
        userRecipes[index].name = cleanName
        userRecipes[index].prompt = cleanPrompt
        userRecipes[index].projectID = projectID
        userRecipes[index].updatedAt = Date()
        persist()
    }

    func delete(id: String) {
        userRecipes.removeAll { $0.id == id && !$0.isBuiltIn }
        persist()
    }

    private func load() {
        do {
            userRecipes = try fileStore.load() ?? []
        } catch {
            askTaskRecipeLogger.error("Failed to load ask recipes: \(error.localizedDescription)")
        }
    }

    private func sameRecipe(_ recipe: AskTaskRecipe, name: String, projectID: UUID?) -> Bool {
        !recipe.isBuiltIn && recipe.projectID == projectID && recipe.name.compare(name, options: [.caseInsensitive]) == .orderedSame
    }

    private func persist() {
        do {
            try fileStore.save(userRecipes)
        } catch {
            askTaskRecipeLogger.error("Failed to save ask recipes: \(error.localizedDescription)")
        }
    }
}
