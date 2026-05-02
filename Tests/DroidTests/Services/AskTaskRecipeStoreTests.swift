import Foundation
import Testing

@testable import Droid

@MainActor
struct AskTaskRecipeStoreTests {
    @Test
    func recipesIncludeGlobalAndCurrentProjectOnly() throws {
        let fileStore = try recipeStore()
        let store = AskTaskRecipeStore(fileStore: fileStore)
        let projectID = UUID()
        let otherID = UUID()

        store.save(name: "Global", prompt: "global", projectID: nil)
        store.save(name: "Project", prompt: "project", projectID: projectID)
        store.save(name: "Other", prompt: "other", projectID: otherID)

        let names = store.recipes(for: projectID).map(\.name)

        #expect(names.contains("Global"))
        #expect(names.contains("Project"))
        #expect(!names.contains("Other"))
    }

    @Test
    func updatePreservesRecipeIdentityAndChangesScope() throws {
        let fileStore = try recipeStore()
        let store = AskTaskRecipeStore(fileStore: fileStore)
        let projectID = UUID()
        store.save(name: "Smoke", prompt: "old", projectID: nil)
        let recipe = try #require(store.userRecipes.first)

        store.update(id: recipe.id, name: "Smoke 2", prompt: "new", projectID: projectID)

        let updated = try #require(store.userRecipes.first)
        #expect(updated.id == recipe.id)
        #expect(updated.name == "Smoke 2")
        #expect(updated.prompt == "new")
        #expect(updated.projectID == projectID)
    }

    private func recipeStore() throws -> CodableFileStore<[AskTaskRecipe]> {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return CodableFileStore<[AskTaskRecipe]>(fileURL: directory.appendingPathComponent("ask-recipes.json"))
    }
}
