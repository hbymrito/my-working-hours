import SwiftData

@MainActor
final class PersistenceStore {
    let modelContainer: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([
            Project.self,
            Tag.self,
            WorkTask.self,
            TimeEntry.self,
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }

    func save(_ context: ModelContext) {
        guard context.hasChanges else {
            return
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save context: \(error)")
        }
    }
}
