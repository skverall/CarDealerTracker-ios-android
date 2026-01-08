import Foundation
import SwiftUI

enum InteractionStage: String, CaseIterable, Identifiable {
    case outreach
    case qualification
    case negotiation
    case offer
    case testDrive = "test_drive"
    case closedWon = "closed_won"
    case closedLost = "closed_lost"
    case followUp = "follow_up"
    case update

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .outreach: return "interaction_outreach".localizedString
        case .qualification: return "interaction_qualification".localizedString
        case .negotiation: return "interaction_negotiation".localizedString
        case .offer: return "interaction_offer".localizedString
        case .testDrive: return "interaction_test_drive".localizedString
        case .closedWon: return "interaction_closed_won".localizedString
        case .closedLost: return "interaction_closed_lost".localizedString
        case .followUp: return "interaction_follow_up".localizedString
        case .update: return "interaction_update".localizedString
        }
    }

    var icon: String {
        switch self {
        case .outreach: return "phone.fill"
        case .qualification: return "checkmark.seal.fill"
        case .negotiation: return "arrow.triangle.branch"
        case .offer: return "doc.text.fill"
        case .testDrive: return "steeringwheel"
        case .closedWon: return "handshake.fill"
        case .closedLost: return "xmark.octagon.fill"
        case .followUp: return "clock.arrow.circlepath"
        case .update: return "note.text"
        }
    }

    var color: Color {
        switch self {
        case .outreach: return ColorTheme.primary
        case .qualification: return ColorTheme.success
        case .negotiation: return ColorTheme.warning
        case .offer: return ColorTheme.secondary
        case .testDrive: return ColorTheme.accent
        case .closedWon: return ColorTheme.success
        case .closedLost: return ColorTheme.danger
        case .followUp: return ColorTheme.purple
        case .update: return ColorTheme.secondaryText
        }
    }
}

struct InteractionDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var notes: String
    var occurredAt: Date
    var stage: InteractionStage
    var value: Decimal?
}

struct ReminderDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var notes: String
    var dueDate: Date
    var isCompleted: Bool
}

extension ClientInteraction {
    var interactionStage: InteractionStage {
        get { InteractionStage(rawValue: stage ?? "update") ?? .update }
        set { stage = newValue.rawValue }
    }

    var formattedValue: String? {
        guard let value else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "AED"
        return formatter.string(from: value)
    }

    func asDraft() -> InteractionDraft {
        InteractionDraft(
            id: id ?? UUID(),
            title: title ?? "",
            notes: detail ?? "",
            occurredAt: occurredAt ?? Date(),
            stage: interactionStage,
            value: value?.decimalValue
        )
    }
}

extension ClientReminder {
    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var statusColor: Color {
        if isCompleted { return ColorTheme.success }
        if isOverdue { return ColorTheme.danger }
        return ColorTheme.accent
    }

    var statusLabel: String {
        if isCompleted { return "Completed" }
        return isOverdue ? "Overdue" : "Scheduled"
    }

    func asDraft() -> ReminderDraft {
        ReminderDraft(
            id: id ?? UUID(),
            title: title ?? "",
            notes: notes ?? "",
            dueDate: dueDate ?? Date(),
            isCompleted: isCompleted
        )
    }
}

enum ClientStatus: String, CaseIterable, Identifiable {
    case new
    case inProgress = "in_progress"
    case completed
    case purchased

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .new: return "client_status_new".localizedString
        case .inProgress: return "client_status_in_progress".localizedString
        case .completed: return "client_status_completed".localizedString
        case .purchased: return "client_status_purchased".localizedString
        }
    }

    var sortOrder: Int {
        switch self {
        case .new: return 0
        case .inProgress: return 1
        case .completed: return 2
        case .purchased: return 3
        }
    }

    var color: Color {
        switch self {
        case .new: return ColorTheme.primary
        case .inProgress: return ColorTheme.warning
        case .completed: return ColorTheme.success
        case .purchased: return ColorTheme.success
        }
    }
}

extension Client {
    var clientStatus: ClientStatus {
        get { ClientStatus(rawValue: status ?? "new") ?? .new }
        set { status = newValue.rawValue }
    }
}
