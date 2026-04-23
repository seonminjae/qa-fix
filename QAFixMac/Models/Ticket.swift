import Foundation

enum Severity: String, CaseIterable, Comparable {
    case critical = "Critical"
    case major = "Major"
    case minor = "Minor"
    case trivial = "Trivial"
    case unknown = "-"

    static let rank: [Severity: Int] = [
        .critical: 0, .major: 1, .minor: 2, .trivial: 3, .unknown: 4
    ]

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        (rank[lhs] ?? 99) < (rank[rhs] ?? 99)
    }

    static func from(_ raw: String?) -> Severity {
        guard let raw else { return .unknown }
        return Severity(rawValue: raw) ?? .unknown
    }
}

struct TicketAttachment: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
}

struct TicketComment: Identifiable, Hashable {
    let id = UUID()
    let author: String
    let createdTime: String
    let text: String
}

struct Ticket: Identifiable, Hashable {
    let pageID: String
    let displayID: String
    let title: String
    let severity: Severity
    let status: String
    let type: String
    let reporter: [String]
    let references: [String]
    let assignees: [String]
    let environment: [String]
    let device: String
    let appVerified: String
    let issueCount: String
    let notes: String
    let reproduceSteps: String
    let reproduceResult: String
    let affectedVersion: String
    let attachments: [TicketAttachment]
    let versionTags: [String]
    let createdTime: String?
    let lastEditedTime: String?
    var comments: [TicketComment] = []

    var id: String { pageID }

    static func build(from page: NotionPage) -> Ticket {
        let title = (extract(page, "Projects").titleValues ?? []).joined()
        let sev = Severity.from(extract(page, "위험도").selectValue)
        let status = extract(page, "상태").selectValue ?? "-"
        let type = extract(page, "유형").selectValue ?? "-"
        let reporter = extract(page, "보고자").peopleValues ?? []
        let references = extract(page, "참조").peopleValues ?? []
        let assignees = extract(page, "담당자").peopleValues ?? []
        let environment = extract(page, "환경").multiSelectValues
            ?? extract(page, "환경").selectValue.map { [$0] }
            ?? []
        let device = (extract(page, "확인 Device").richTextValues ?? []).joined()
        let appVerified = (extract(page, "확인 버전 (App)").richTextValues ?? []).joined()
        let issueCount = extract(page, "이슈 등록 차수").selectValue
            ?? (extract(page, "이슈 등록 차수").richTextValues ?? []).joined()
        let notes = (extract(page, "참고").richTextValues ?? []).joined()
        let steps = (extract(page, "재현 절차").richTextValues ?? []).joined()
        let result = (extract(page, "재현 결과").richTextValues ?? []).joined()
        let version = (extract(page, "발생 버전 (App)").richTextValues ?? []).joined()
        let versionTags = extract(page, "검증 프로젝트 태그").multiSelectValues ?? []
        let attachmentsRaw = extract(page, "첨부").filesValues ?? []
        let attachments = attachmentsRaw.map { TicketAttachment(name: $0.name, url: $0.url) }
        let unique = extract(page, "ID").uniqueIDValue
        let displayID: String
        if let (prefix, number) = unique {
            let pfx = prefix.map { "\($0)-" } ?? ""
            let num = number.map(String.init) ?? "?"
            displayID = "\(pfx)\(num)"
        } else {
            displayID = String(page.id.prefix(8))
        }
        return Ticket(
            pageID: page.id,
            displayID: displayID,
            title: title.isEmpty ? "(no title)" : title,
            severity: sev,
            status: status,
            type: type,
            reporter: reporter,
            references: references,
            assignees: assignees,
            environment: environment,
            device: device,
            appVerified: appVerified,
            issueCount: issueCount,
            notes: notes,
            reproduceSteps: steps,
            reproduceResult: result,
            affectedVersion: version,
            attachments: attachments,
            versionTags: versionTags,
            createdTime: page.createdTime,
            lastEditedTime: page.lastEditedTime
        )
    }

    private static func extract(_ page: NotionPage, _ key: String) -> NotionPropertyHelper {
        NotionPropertyHelper(value: page.properties[key])
    }
}

struct NotionPropertyHelper {
    let value: NotionProperty?

    var titleValues: [String]? {
        if case let .title(values) = value { return values }
        return nil
    }
    var richTextValues: [String]? {
        if case let .richText(values) = value { return values }
        return nil
    }
    var selectValue: String? {
        if case let .select(value) = value { return value }
        return nil
    }
    var multiSelectValues: [String]? {
        if case let .multiSelect(values) = value { return values }
        return nil
    }
    var peopleValues: [String]? {
        if case let .people(values) = value { return values }
        return nil
    }
    var uniqueIDValue: (String?, Int?)? {
        if case let .uniqueID(prefix, number) = value { return (prefix, number) }
        return nil
    }
    var filesValues: [(name: String, url: String)]? {
        if case let .files(files) = value {
            return files.map { (name: $0.name, url: $0.url) }
        }
        return nil
    }
}
