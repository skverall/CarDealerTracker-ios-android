import Foundation

enum InteractionOutcome: String, CaseIterable {
    case positive = "positive"
    case negative = "negative"
    case neutral = "neutral"

    var displayName: String {
        switch self {
        case .positive:
            return "Positive"
        case .negative:
            return "Negative"
        case .neutral:
            return "Neutral"
        }
    }

    var iconName: String {
        switch self {
        case .positive:
            return "hand.thumbsup.fill"
        case .negative:
            return "hand.thumbsdown.fill"
        case .neutral:
            return "minus.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .positive:
            return "green"
        case .negative:
            return "red"
        case .neutral:
            return "gray"
        }
    }
}
