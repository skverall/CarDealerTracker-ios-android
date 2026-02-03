import Foundation

enum LeadSource: String, CaseIterable {
    case facebook = "facebook"
    case dubizzle = "dubizzle"
    case instagram = "instagram"
    case referral = "referral"
    case walkIn = "walk_in"
    case phone = "phone"
    case website = "website"
    case other = "other"

    var displayName: String {
        switch self {
        case .facebook:
            return "Facebook"
        case .dubizzle:
            return "Dubizzle"
        case .instagram:
            return "Instagram"
        case .referral:
            return "Referral"
        case .walkIn:
            return "Walk In"
        case .phone:
            return "Phone"
        case .website:
            return "Website"
        case .other:
            return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .facebook:
            return "f.square.fill"
        case .dubizzle:
            return "d.square.fill"
        case .instagram:
            return "camera.fill"
        case .referral:
            return "person.2.fill"
        case .walkIn:
            return "door.left.hand.open"
        case .phone:
            return "phone.fill"
        case .website:
            return "globe"
        case .other:
            return "questionmark.circle.fill"
        }
    }
}
