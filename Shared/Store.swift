import Foundation

enum StoreError: Error { case unavailable, invalidFilename, invalidArchive }

final class Store {
    private static let lock = NSRecursiveLock()
    let root: URL
    var files: URL { root.appendingPathComponent("Files", isDirectory: true) }
    var json: URL { root.appendingPathComponent("projects.json") }
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "GouZhiAppGroup") as? String ?? "group.com.hgsldswk.knitcount"
    }
    convenience init() throws {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) else { throw StoreError.unavailable }
        try self.init(root: root)
    }
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    }
    func file(_ name: String) throws -> URL {
        guard !name.isEmpty, name == (name as NSString).lastPathComponent,
              !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { throw StoreError.invalidFilename }
        return files.appendingPathComponent(name)
    }
    @discardableResult func writeFile(_ data: Data, extension ext: String) throws -> String {
        let name = UUID().uuidString + "." + ext.filter { $0.isLetter || $0.isNumber }
        try data.write(to: file(name), options: .atomic); return name
    }
    func load() throws -> AppData {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var result: AppData?
        var failure: Error?
        var coordination: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: root, options: [], error: &coordination) { _ in
            do { result = try self.readUnlocked() } catch { failure = error }
        }
        if let error = coordination ?? (failure as NSError?) { throw error }
        return result ?? AppData()
    }
    private func readUnlocked() throws -> AppData {
        guard FileManager.default.fileExists(atPath: json.path) else { return AppData() }
        return try JSONDecoder().decode(AppData.self, from: Data(contentsOf: json))
    }
    @discardableResult func update(_ change: (inout AppData) throws -> Void) throws -> AppData {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var result: AppData?
        var failure: Error?
        var coordination: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: root, options: .forMerging, error: &coordination) { _ in
            do {
                var state = try self.readUnlocked()
                try change(&state)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(state).write(to: self.json, options: .atomic)
                result = state
            } catch { failure = error }
        }
        if let error = coordination ?? (failure as NSError?) { throw error }
        guard let result else { throw StoreError.unavailable }; return result
    }
    func exportAll() throws -> URL {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("GouZhi-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var snapshotError: Error?; var coordinateError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: root, options: [], error: &coordinateError) { _ in
            do {
                let state = try self.readUnlocked()
                try JSONEncoder().encode(state).write(to: staging.appendingPathComponent("projects.json"), options: .atomic)
                let destination = staging.appendingPathComponent("Files", isDirectory: true)
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                var names = Set<String>()
                var parts = [state.quick]
                for project in state.projects {
                    if let cover = project.coverFilename { names.insert(cover) }
                    names.formUnion(project.photos); parts += project.parts
                }
                for part in parts { for page in part.patternPages {
                    names.insert(page.filename); if let pdf = page.pdfFilename { names.insert(pdf) }
                    names.insert(page.id.uuidString + ".drawing")
                } }
                for name in names {
                    let source = try self.file(name)
                    if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: destination.appendingPathComponent(name)) }
                }
            } catch { snapshotError = error }
        }
        if let error = coordinateError ?? (snapshotError as NSError?) { throw error }
        let result = fm.temporaryDirectory.appendingPathComponent("GouZhi-" + UUID().uuidString + ".zip")
        var uploadError: Error?; var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: staging, options: .forUploading, error: &error) { archive in
            do { try fm.copyItem(at: archive, to: result) } catch { uploadError = error }
        }
        if let failure = error ?? (uploadError as NSError?) { throw failure }
        guard fm.fileExists(atPath: result.path) else { throw StoreError.invalidArchive }
        return result
    }
}

extension AppData {
    var currentProject: Project? { projects.first(where: { $0.id == recentID }) }
    var currentPart: Part { currentProject?.part ?? quick }
    mutating func editPart(projectID: UUID?, partID: UUID, _ change: (inout Part) -> Void) {
        if let projectID, let p = projects.firstIndex(where: { $0.id == projectID }),
           let i = projects[p].parts.firstIndex(where: { $0.id == partID }) { change(&projects[p].parts[i]) }
        else if projectID == nil, quick.id == partID { change(&quick) }
    }
    @discardableResult mutating func count(projectID: UUID?, partID: UUID, counterID: UUID, delta: Int) -> [CountEvent] {
        let linked = entitlement.hasPro(at: Date())
        var events: [CountEvent] = []
        var stack = undo[partID.uuidString] ?? []
        editPart(projectID: projectID, partID: partID) { part in
            Counting.remember(part, in: &stack)
            let result = delta > 0 ? Counting.increment(part, counterID: counterID, linked: linked) : Counting.decrement(part, counterID: counterID, linked: linked)
            part = result.part; events = result.events
        }
        undo[partID.uuidString] = stack
        return events
    }
}
