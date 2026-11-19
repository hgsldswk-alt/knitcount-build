import Foundation
import CoreGraphics

typealias CounterID = UUID
enum CounterKind: String, Codable, CaseIterable { case row, stitch, custom; case repeatCount = "repeat" }
enum TrackerMode: String, Codable, CaseIterable { case bar, ring, grid, none }
enum PageKind: String, Codable { case image, pdfPage }
enum ProjectStatus: String, Codable, CaseIterable { case active, completed, planned }

struct Yarn: Codable, Equatable, Identifiable {
    var id: UUID
    var brand: String
    var color: String
    var batch: String
    var amount: String
    init(id: UUID = UUID(), brand: String = "", color: String = "", batch: String = "", amount: String = "") {
        self.id = id
        self.brand = brand
        self.color = color
        self.batch = batch
        self.amount = amount
    }
    enum CodingKeys: String, CodingKey { case id, brand, color, batch, amount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        batch = try c.decodeIfPresent(String.self, forKey: .batch) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? ""
    }
}

struct Counter: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var kind: CounterKind
    var value: Int
    var min: Int
    var resetAt: Int?
    var linkTo: UUID?
    init(id: UUID = UUID(), name: String = L.t("行"), kind: CounterKind = .row, value: Int = 1, min: Int = 1, resetAt: Int? = nil, linkTo: UUID? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.value = value
        self.min = min
        self.resetAt = resetAt
        self.linkTo = linkTo
    }
    enum CodingKeys: String, CodingKey { case id, name, kind, value, min, resetAt, linkTo }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L.t("行")
        kind = try c.decodeIfPresent(CounterKind.self, forKey: .kind) ?? .row
        value = try c.decodeIfPresent(Int.self, forKey: .value) ?? 1
        min = try c.decodeIfPresent(Int.self, forKey: .min) ?? 1
        resetAt = try c.decodeIfPresent(Int.self, forKey: .resetAt)
        linkTo = try c.decodeIfPresent(UUID.self, forKey: .linkTo)
    }
}

struct RowReminder: Codable, Equatable, Identifiable {
    var id: UUID
    var atRow: Int
    var text: String
    var colorTag: Int?
    init(id: UUID = UUID(), atRow: Int = 1, text: String = "", colorTag: Int? = nil) {
        self.id = id
        self.atRow = atRow
        self.text = text
        self.colorTag = colorTag
    }
    enum CodingKeys: String, CodingKey { case id, atRow, text, colorTag }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        atRow = try c.decodeIfPresent(Int.self, forKey: .atRow) ?? 1
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        colorTag = try c.decodeIfPresent(Int.self, forKey: .colorTag)
    }
}

struct Tracker: Codable, Equatable {
    var mode: TrackerMode
    var page: Int
    var pageY: [Int: Double]
    var y: Double
    var height: Double
    var step: Double
    var centerX: Double
    var centerY: Double
    var firstRadius: Double
    var ringSpacing: Double
    var radius: Double
    var originX: Double
    var originY: Double
    var cellWidth: Double
    var cellHeight: Double
    var alternating: Bool
    var gridColumn: Int
    var zoomScale: Double
    var offsetX: Double
    var offsetY: Double
    var dim: Bool
    init(mode: TrackerMode = .bar, page: Int = 0, pageY: [Int: Double] = [:], y: Double = 0.15, height: Double = 0.065, step: Double = 0.065, centerX: Double = 0.5, centerY: Double = 0.5, firstRadius: Double = 0.08, ringSpacing: Double = 0.025, radius: Double = 0.08, originX: Double = 0.1, originY: Double = 0.1, cellWidth: Double = 0.05, cellHeight: Double = 0.05, alternating: Bool = true, gridColumn: Int = 0, zoomScale: Double = 1, offsetX: Double = 0, offsetY: Double = 0, dim: Bool = false) {
        self.mode = mode
        self.page = page
        self.pageY = pageY
        self.y = y
        self.height = height
        self.step = step
        self.centerX = centerX
        self.centerY = centerY
        self.firstRadius = firstRadius
        self.ringSpacing = ringSpacing
        self.radius = radius
        self.originX = originX
        self.originY = originY
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.alternating = alternating
        self.gridColumn = gridColumn
        self.zoomScale = zoomScale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.dim = dim
    }
    enum CodingKeys: String, CodingKey { case mode, page, pageY, y, height, step, centerX, centerY, firstRadius, ringSpacing, radius, originX, originY, cellWidth, cellHeight, alternating, gridColumn, zoomScale, offsetX, offsetY, dim }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(TrackerMode.self, forKey: .mode) ?? .bar
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 0
        pageY = try c.decodeIfPresent([Int: Double].self, forKey: .pageY) ?? [:]
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.15
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0.065
        step = try c.decodeIfPresent(Double.self, forKey: .step) ?? 0.065
        centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5
        centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5
        firstRadius = try c.decodeIfPresent(Double.self, forKey: .firstRadius) ?? 0.08
        ringSpacing = try c.decodeIfPresent(Double.self, forKey: .ringSpacing) ?? 0.025
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.08
        originX = try c.decodeIfPresent(Double.self, forKey: .originX) ?? 0.1
        originY = try c.decodeIfPresent(Double.self, forKey: .originY) ?? 0.1
        cellWidth = try c.decodeIfPresent(Double.self, forKey: .cellWidth) ?? 0.05
        cellHeight = try c.decodeIfPresent(Double.self, forKey: .cellHeight) ?? 0.05
        alternating = try c.decodeIfPresent(Bool.self, forKey: .alternating) ?? true
        gridColumn = try c.decodeIfPresent(Int.self, forKey: .gridColumn) ?? 0
        zoomScale = try c.decodeIfPresent(Double.self, forKey: .zoomScale) ?? 1
        offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        dim = try c.decodeIfPresent(Bool.self, forKey: .dim) ?? false
    }
}

struct PatternPage: Codable, Equatable, Identifiable {
    var id: UUID
    var filename: String
    var kind: PageKind
    var pdfFilename: String?
    var pdfPage: Int?
    var aspectRatio: Double
    var ocrLines: [CGRect]?
    var rowMap: [Int: Int]
    init(id: UUID = UUID(), filename: String = "", kind: PageKind = .image, pdfFilename: String? = nil, pdfPage: Int? = nil, aspectRatio: Double = 0.75, ocrLines: [CGRect]? = nil, rowMap: [Int: Int] = [:]) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.pdfFilename = pdfFilename
        self.pdfPage = pdfPage
        self.aspectRatio = aspectRatio
        self.ocrLines = ocrLines
        self.rowMap = rowMap
    }
    enum CodingKeys: String, CodingKey { case id, filename, kind, pdfFilename, pdfPage, aspectRatio, ocrLines, rowMap }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        kind = try c.decodeIfPresent(PageKind.self, forKey: .kind) ?? .image
        pdfFilename = try c.decodeIfPresent(String.self, forKey: .pdfFilename)
        pdfPage = try c.decodeIfPresent(Int.self, forKey: .pdfPage)
        aspectRatio = try c.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 0.75
        ocrLines = try c.decodeIfPresent([CGRect].self, forKey: .ocrLines)
        rowMap = try c.decodeIfPresent([Int: Int].self, forKey: .rowMap) ?? [:]
    }
}

struct PatternLine: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var row: Int?
    var target: Int?
    init(id: UUID = UUID(), text: String = "", row: Int? = nil, target: Int? = nil) {
        self.id = id
        self.text = text
        self.row = row
        self.target = target
    }
    enum CodingKeys: String, CodingKey { case id, text, row, target }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        row = try c.decodeIfPresent(Int.self, forKey: .row)
        target = try c.decodeIfPresent(Int.self, forKey: .target)
    }
}

struct Part: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var copies: Int
    var currentCopy: Int
    var counters: [Counter]
    var mainCounterID: UUID?
    var patternPages: [PatternPage]
    var textPattern: [PatternLine]?
    var tracker: Tracker
    var reminders: [RowReminder]
    var roundTargets: [Int: Int]
    var sizeIndex: Int?
    var videoMarks: [Int: Int]
    var rowNotes: [Int: String]
    var rowsWorked: Int
    init(id: UUID = UUID(), name: String = L.t("主体"), copies: Int = 1, currentCopy: Int = 1, counters: [Counter] = [Counter()], mainCounterID: UUID? = nil, patternPages: [PatternPage] = [], textPattern: [PatternLine]? = nil, tracker: Tracker = Tracker(), reminders: [RowReminder] = [], roundTargets: [Int: Int] = [:], sizeIndex: Int? = nil, videoMarks: [Int: Int] = [:], rowNotes: [Int: String] = [:], rowsWorked: Int = 0) {
        self.id = id
        self.name = name
        self.copies = copies
        self.currentCopy = currentCopy
        self.counters = counters
        self.mainCounterID = mainCounterID
        self.patternPages = patternPages
        self.textPattern = textPattern
        self.tracker = tracker
        self.reminders = reminders
        self.roundTargets = roundTargets
        self.sizeIndex = sizeIndex
        self.videoMarks = videoMarks
        self.rowNotes = rowNotes
        self.rowsWorked = rowsWorked
    }
    enum CodingKeys: String, CodingKey { case id, name, copies, currentCopy, counters, mainCounterID, patternPages, textPattern, tracker, reminders, roundTargets, sizeIndex, videoMarks, rowNotes, rowsWorked }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L.t("主体")
        copies = try c.decodeIfPresent(Int.self, forKey: .copies) ?? 1
        currentCopy = try c.decodeIfPresent(Int.self, forKey: .currentCopy) ?? 1
        counters = try c.decodeIfPresent([Counter].self, forKey: .counters) ?? [Counter()]
        mainCounterID = try c.decodeIfPresent(UUID.self, forKey: .mainCounterID)
        patternPages = try c.decodeIfPresent([PatternPage].self, forKey: .patternPages) ?? []
        textPattern = try c.decodeIfPresent([PatternLine].self, forKey: .textPattern)
        tracker = try c.decodeIfPresent(Tracker.self, forKey: .tracker) ?? Tracker()
        reminders = try c.decodeIfPresent([RowReminder].self, forKey: .reminders) ?? []
        roundTargets = try c.decodeIfPresent([Int: Int].self, forKey: .roundTargets) ?? [:]
        sizeIndex = try c.decodeIfPresent(Int.self, forKey: .sizeIndex)
        videoMarks = try c.decodeIfPresent([Int: Int].self, forKey: .videoMarks) ?? [:]
        rowNotes = try c.decodeIfPresent([Int: String].self, forKey: .rowNotes) ?? [:]
        rowsWorked = try c.decodeIfPresent(Int.self, forKey: .rowsWorked) ?? 0
    }
}

struct Project: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var status: ProjectStatus
    var createdAt: Date
    var completedAt: Date?
    var coverFilename: String?
    var parts: [Part]
    var yarns: [Yarn]
    var hookSize: String
    var size: String
    var notes: String
    var photos: [String]
    var videoLink: String?
    var totalSeconds: Int
    var lastOpened: Date
    var selectedPartID: UUID?
    var weeklySeconds: [String: Int]
    init(id: UUID = UUID(), name: String = L.t("我的作品"), status: ProjectStatus = .active, createdAt: Date = Date(), completedAt: Date? = nil, coverFilename: String? = nil, parts: [Part] = [Part()], yarns: [Yarn] = [], hookSize: String = "", size: String = "", notes: String = "", photos: [String] = [], videoLink: String? = nil, totalSeconds: Int = 0, lastOpened: Date = Date(), selectedPartID: UUID? = nil, weeklySeconds: [String: Int] = [:]) {
        self.id = id
        self.name = name
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.coverFilename = coverFilename
        self.parts = parts
        self.yarns = yarns
        self.hookSize = hookSize
        self.size = size
        self.notes = notes
        self.photos = photos
        self.videoLink = videoLink
        self.totalSeconds = totalSeconds
        self.lastOpened = lastOpened
        self.selectedPartID = selectedPartID
        self.weeklySeconds = weeklySeconds
    }
    enum CodingKeys: String, CodingKey { case id, name, status, createdAt, completedAt, coverFilename, parts, yarns, hookSize, size, notes, photos, videoLink, totalSeconds, lastOpened, selectedPartID, weeklySeconds }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L.t("我的作品")
        status = try c.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .active
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        coverFilename = try c.decodeIfPresent(String.self, forKey: .coverFilename)
        parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? [Part()]
        yarns = try c.decodeIfPresent([Yarn].self, forKey: .yarns) ?? []
        hookSize = try c.decodeIfPresent(String.self, forKey: .hookSize) ?? ""
        size = try c.decodeIfPresent(String.self, forKey: .size) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        videoLink = try c.decodeIfPresent(String.self, forKey: .videoLink)
        totalSeconds = try c.decodeIfPresent(Int.self, forKey: .totalSeconds) ?? 0
        lastOpened = try c.decodeIfPresent(Date.self, forKey: .lastOpened) ?? Date()
        selectedPartID = try c.decodeIfPresent(UUID.self, forKey: .selectedPartID)
        weeklySeconds = try c.decodeIfPresent([String: Int].self, forKey: .weeklySeconds) ?? [:]
    }
}

struct UndoStep: Codable, Equatable {
    var counters: [Counter]
    var tracker: Tracker
    var at: Date
    var rowsWorked: Int
    init(counters: [Counter] = [], tracker: Tracker = Tracker(), at: Date = Date(), rowsWorked: Int = 0) {
        self.counters = counters
        self.tracker = tracker
        self.at = at
        self.rowsWorked = rowsWorked
    }
    enum CodingKeys: String, CodingKey { case counters, tracker, at, rowsWorked }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counters = try c.decodeIfPresent([Counter].self, forKey: .counters) ?? []
        tracker = try c.decodeIfPresent(Tracker.self, forKey: .tracker) ?? Tracker()
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        rowsWorked = try c.decodeIfPresent(Int.self, forKey: .rowsWorked) ?? 0
    }
}

struct Preferences: Codable, Equatable {
    var haptics: Bool
    var volumeKeys: Bool
    var keepAwake: Bool
    var dimDefault: Bool
    init(haptics: Bool = true, volumeKeys: Bool = false, keepAwake: Bool = true, dimDefault: Bool = false) {
        self.haptics = haptics
        self.volumeKeys = volumeKeys
        self.keepAwake = keepAwake
        self.dimDefault = dimDefault
    }
    enum CodingKeys: String, CodingKey { case haptics, volumeKeys, keepAwake, dimDefault }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        volumeKeys = try c.decodeIfPresent(Bool.self, forKey: .volumeKeys) ?? false
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        dimDefault = try c.decodeIfPresent(Bool.self, forKey: .dimDefault) ?? false
    }
}

struct AppData: Codable, Equatable {
    var projects: [Project]
    var recentID: UUID?
    var quick: Part
    var undo: [String: [UndoStep]]
    var entitlement: Entitlement
    var preferences: Preferences
    var milestones: Set<String>
    var launchCount: Int
    var reviewedVersion: String?
    var expiryShown: Bool
    init(projects: [Project] = [], recentID: UUID? = nil, quick: Part = Part(counters: [Counter(name: L.t("快速计数"), kind: .custom, value: 0, min: 0)]), undo: [String: [UndoStep]] = [:], entitlement: Entitlement = Entitlement(), preferences: Preferences = Preferences(), milestones: Set<String> = [], launchCount: Int = 0, reviewedVersion: String? = nil, expiryShown: Bool = false) {
        self.projects = projects
        self.recentID = recentID
        self.quick = quick
        self.undo = undo
        self.entitlement = entitlement
        self.preferences = preferences
        self.milestones = milestones
        self.launchCount = launchCount
        self.reviewedVersion = reviewedVersion
        self.expiryShown = expiryShown
    }
    enum CodingKeys: String, CodingKey { case projects, recentID, quick, undo, entitlement, preferences, milestones, launchCount, reviewedVersion, expiryShown }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        recentID = try c.decodeIfPresent(UUID.self, forKey: .recentID)
        quick = try c.decodeIfPresent(Part.self, forKey: .quick) ?? Part(counters: [Counter(name: L.t("快速计数"), kind: .custom, value: 0, min: 0)])
        undo = try c.decodeIfPresent([String: [UndoStep]].self, forKey: .undo) ?? [:]
        entitlement = try c.decodeIfPresent(Entitlement.self, forKey: .entitlement) ?? Entitlement()
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        milestones = try c.decodeIfPresent(Set<String>.self, forKey: .milestones) ?? []
        launchCount = try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        reviewedVersion = try c.decodeIfPresent(String.self, forKey: .reviewedVersion)
        expiryShown = try c.decodeIfPresent(Bool.self, forKey: .expiryShown) ?? false
    }
}
