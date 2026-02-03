import Foundation

struct NotionDatabase: Codable, Identifiable {
    let id: String
    let title: [NotionTitle]
    let properties: [String: NotionProperty]
    let url: String?
    
    var displayTitle: String {
        title.first?.plainText ?? "Untitled Database"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case properties
        case url
    }
}

struct NotionTitle: Codable {
    let plainText: String?
    let text: NotionTextContent?
    
    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
        case text
    }
}

struct NotionTextContent: Codable {
    let content: String?
}

struct NotionProperty: Codable {
    let type: String
    let id: String?
    let name: String?
    let number: NotionNumberConfig?
    let select: NotionSelectConfig?
    let formula: NotionFormulaConfig?
    let richText: NotionRichTextConfig?
    let title: NotionTitleConfig?
    let date: NotionDateConfig?
    
    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case number
        case select
        case formula
        case richText = "rich_text"
        case title
        case date
    }
}

struct NotionNumberConfig: Codable {
    let format: String?
}

struct NotionSelectConfig: Codable {
    let options: [NotionSelectOption]?
}

struct NotionSelectOption: Codable {
    let name: String
    let color: String?
}

struct NotionFormulaConfig: Codable {
    let expression: String
}

struct NotionRichTextConfig: Codable {}
struct NotionTitleConfig: Codable {}
struct NotionDateConfig: Codable {}

struct NotionPage: Codable, Identifiable {
    let id: String
    let url: String
    let properties: [String: NotionPageProperty]?
}

struct NotionPageProperty: Codable {
    let id: String?
    let type: String?
}

struct NotionSearchResponse: Codable {
    let results: [NotionDatabase]
    let hasMore: Bool
    let nextCursor: String?
    
    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

enum NotionValue {
    case title(String)
    case number(Decimal)
    case select(String)
    case date(Date)
    case formula(String)
    case richText(String)
    case url(String)
    case checkbox(Bool)
    case email(String)
    case phoneNumber(String)
    
    var notionProperty: [String: Any] {
        switch self {
        case .title(let value):
            return ["title": [["text": ["content": value]]]]
        case .number(let value):
            return ["number": NSDecimalNumber(decimal: value).doubleValue]
        case .select(let value):
            return ["select": ["name": value]]
        case .date(let value):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return ["date": ["start": formatter.string(from: value)]]
        case .formula(let value):
            return ["formula": ["expression": value]]
        case .richText(let value):
            return ["rich_text": [["text": ["content": value]]]]
        case .url(let value):
            return ["url": value]
        case .checkbox(let value):
            return ["checkbox": value]
        case .email(let value):
            return ["email": value]
        case .phoneNumber(let value):
            return ["phone_number": value]
        }
    }
}

struct NotionCreateDatabaseRequest: Codable {
    let parent: NotionParent
    let title: [NotionTitleContent]
    let properties: [String: NotionPropertyDefinition]
}

struct NotionParent: Codable {
    let pageId: String
    
    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
    }
}

struct NotionTitleContent: Codable {
    let text: NotionTextContent
}

struct NotionPropertyDefinition: Codable {
    let type: String
    let number: NotionNumberConfig?
    let select: NotionSelectConfig?
    let formula: NotionFormulaConfig?
    let richText: NotionRichTextConfig?
    let title: NotionTitleConfig?
    let date: NotionDateConfig?
    let checkbox: NotionCheckboxConfig?
    let email: NotionEmailConfig?
    let phoneNumber: NotionPhoneConfig?
    let url: NotionUrlConfig?
    
    enum CodingKeys: String, CodingKey {
        case type
        case number
        case select
        case formula
        case richText = "rich_text"
        case title
        case date
        case checkbox
        case email
        case phoneNumber = "phone_number"
        case url
    }
    
    static func title() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "title",
            number: nil,
            select: nil,
            formula: nil,
            richText: nil,
            title: NotionTitleConfig(),
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func richText() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "rich_text",
            number: nil,
            select: nil,
            formula: nil,
            richText: NotionRichTextConfig(),
            title: nil,
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func number(format: String = "dollar") -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "number",
            number: NotionNumberConfig(format: format),
            select: nil,
            formula: nil,
            richText: nil,
            title: nil,
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func select(options: [NotionSelectOption]) -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "select",
            number: nil,
            select: NotionSelectConfig(options: options),
            formula: nil,
            richText: nil,
            title: nil,
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func date() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "date",
            number: nil,
            select: nil,
            formula: nil,
            richText: nil,
            title: nil,
            date: NotionDateConfig(),
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func formula(expression: String) -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "formula",
            number: nil,
            select: nil,
            formula: NotionFormulaConfig(expression: expression),
            richText: nil,
            title: nil,
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func checkbox() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "checkbox",
            number: nil,
            select: nil,
            formula: nil,
            richText: nil,
            title: nil,
            date: nil,
            checkbox: NotionCheckboxConfig(),
            email: nil,
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func email() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "email",
            number: nil,
            select: nil,
            formula: nil,
            richText: nil,
            title: nil,
            date: nil,
            checkbox: nil,
            email: NotionEmailConfig(),
            phoneNumber: nil,
            url: nil
        )
    }
    
    static func phoneNumber() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "phone_number",
            number: nil,
            select: nil,
            formula: nil,
            richText: nil,
            title: nil,
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: NotionPhoneConfig(),
            url: nil
        )
    }
    
    static func url() -> NotionPropertyDefinition {
        NotionPropertyDefinition(
            type: "url",
            number: nil,
            select: nil,
            formula: nil,
            richText: nil,
            title: nil,
            date: nil,
            checkbox: nil,
            email: nil,
            phoneNumber: nil,
            url: NotionUrlConfig()
        )
    }
}

struct NotionCheckboxConfig: Codable {}
struct NotionEmailConfig: Codable {}
struct NotionPhoneConfig: Codable {}
struct NotionUrlConfig: Codable {}