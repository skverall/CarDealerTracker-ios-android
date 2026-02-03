import Foundation

enum InteractionType: String, CaseIterable {
    case call = "call"
    case meeting = "meeting"
    case message = "message"
    case email = "email"
    case testDrive = "test_drive"
    case offer = "offer"
    case followUp = "follow_up"

    var displayName: String {
        switch self {
        case .call:
            return "Call"
        case .meeting:
            return "Meeting"
        case .message:
            return "Message"
        case .email:
            return "Email"
        case .testDrive:
            return "Test Drive"
        case .offer:
            return "Offer"
        case .followUp:
            return "Follow Up"
        }
    }

    var iconName: String {
        switch self {
        case .call:
            return "phone.fill"
        case .meeting:
            return "person.2.fill"
        case .message:
            return "message.fill"
        case .email:
            return "envelope.fill"
        case .testDrive:
            return "car.fill"
        case .offer:
            return "doc.text.fill"
        case .followUp:
            return "arrow.clockwise"
        }
    }
}
