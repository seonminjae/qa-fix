import Foundation

struct NotionQueryResponse: Decodable {
    let results: [NotionPage]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct NotionPage: Decodable {
    let id: String
    let createdTime: String?
    let lastEditedTime: String?
    let properties: [String: NotionProperty]

    enum CodingKeys: String, CodingKey {
        case id
        case createdTime = "created_time"
        case lastEditedTime = "last_edited_time"
        case properties
    }
}

enum NotionProperty: Decodable {
    case title([String])
    case select(String?)
    case multiSelect([String])
    case richText([String])
    case people([String])
    case uniqueID(prefix: String?, number: Int?)
    case files([NotionFile])
    case unknown

    struct NotionFile: Decodable {
        let name: String
        let url: String
    }

    enum CodingKeys: String, CodingKey {
        case type
        case title, richText = "rich_text"
        case select, multiSelect = "multi_select"
        case people
        case uniqueID = "unique_id"
        case files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "title":
            let items = try container.decode([RichTextItem].self, forKey: .title)
            self = .title(items.map { $0.plainText })
        case "rich_text":
            let items = try container.decode([RichTextItem].self, forKey: .richText)
            self = .richText(items.map { $0.plainText })
        case "select":
            let sel = try container.decodeIfPresent(NamedItem.self, forKey: .select)
            self = .select(sel?.name)
        case "multi_select":
            let items = try container.decode([NamedItem].self, forKey: .multiSelect)
            self = .multiSelect(items.map { $0.name })
        case "people":
            let items = try container.decode([PersonItem].self, forKey: .people)
            self = .people(items.compactMap { $0.name })
        case "unique_id":
            let item = try container.decode(UniqueIDItem.self, forKey: .uniqueID)
            self = .uniqueID(prefix: item.prefix, number: item.number)
        case "files":
            let items = try container.decode([FileItem].self, forKey: .files)
            self = .files(items.map { NotionFile(name: $0.name, url: $0.bestURL ?? "") })
        default:
            self = .unknown
        }
    }

    private struct RichTextItem: Decodable {
        let plainText: String
        enum CodingKeys: String, CodingKey { case plainText = "plain_text" }
    }

    private struct NamedItem: Decodable { let name: String }
    private struct PersonItem: Decodable { let name: String? }
    private struct UniqueIDItem: Decodable {
        let prefix: String?
        let number: Int?
    }
    private struct FileItem: Decodable {
        let name: String
        let external: URLHolder?
        let file: URLHolder?
        var bestURL: String? { external?.url ?? file?.url }
    }
    private struct URLHolder: Decodable { let url: String }
}

struct NotionCommentsResponse: Decodable {
    let results: [NotionComment]
}

struct NotionComment: Decodable {
    let createdTime: String
    let richText: [CommentText]
    let displayName: DisplayName?

    struct CommentText: Decodable {
        let plainText: String
        enum CodingKeys: String, CodingKey { case plainText = "plain_text" }
    }

    struct DisplayName: Decodable {
        let resolvedName: String?
        enum CodingKeys: String, CodingKey { case resolvedName = "resolved_name" }
    }

    enum CodingKeys: String, CodingKey {
        case createdTime = "created_time"
        case richText = "rich_text"
        case displayName = "display_name"
    }

    var text: String { richText.map { $0.plainText }.joined() }
    var author: String { displayName?.resolvedName ?? "unknown" }
}

struct NotionBlocksResponse: Decodable {
    let results: [NotionBlock]
}

struct NotionBlock: Decodable {
    let id: String
    let type: String
    let image: ImageBlock?

    struct ImageBlock: Decodable {
        let type: String
        let external: URLHolder?
        let file: URLHolder?
        var bestURL: String? { external?.url ?? file?.url }
    }

    struct URLHolder: Decodable { let url: String }
}
