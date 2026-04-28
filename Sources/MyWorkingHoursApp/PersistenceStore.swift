import Foundation
import SwiftData

@MainActor
final class PersistenceStore {
    let modelContainer: ModelContainer

    static let storeURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MyWorkingHours", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.sqlite")
    }()

    init(inMemory: Bool = false) {
        let schema = Schema([
            Project.self,
            Tag.self,
            WorkTask.self,
            TimeEntry.self,
        ])

        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(url: PersistenceStore.storeURL)
        }

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create ModelContainer at \(PersistenceStore.storeURL.path): \(error)")
        }
    }

    func save(_ context: ModelContext) {
        guard context.hasChanges else {
            return
        }

        do {
            try context.save()
        } catch {
            NSLog("[MyWorkingHours] Failed to save context: %@", String(describing: error))
            assertionFailure("Failed to save context: \(error)")
        }
    }
}
