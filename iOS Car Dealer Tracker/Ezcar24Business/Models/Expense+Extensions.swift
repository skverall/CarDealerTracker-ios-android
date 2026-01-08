
import Foundation

// MARK: - Expense Extensions

extension Expense {
    var amountDecimal: Decimal {
        amount?.decimalValue ?? 0
    }

    var categoryTitle: String {
        switch category ?? "" {
        case "vehicle": return "Vehicle"
        case "personal": return "Personal"
        case "employee": return "Employee"
        default: return "Other"
        }
    }

    var categoryIcon: String {
        switch category ?? "" {
        case "vehicle": return "fuelpump"
        case "personal": return "person"
        case "employee": return "briefcase"
        default: return "tag"
        }
    }

    var vehicleTitle: String {
        let make = vehicle?.make ?? ""
        let model = vehicle?.model ?? ""
        let title = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        return title.isEmpty ? "Any Vehicle" : title
    }

    var vehicleSubtitle: String {
        if let vehicle {
            var components: [String] = []
            let name = [vehicle.make, vehicle.model]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty {
                components.append(name)
            }
            if let vin = vehicle.vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty {
                components.append(vin)
            }
            if !components.isEmpty {
                return components.joined(separator: " • ")
            }
        }
        return "No vehicle linked"
    }

    var timeString: String {
        guard let timestamp = createdAt ?? updatedAt else { return "--" }
        return DashboardFormatter.time.string(from: timestamp)
    }

    var dateString: String {
        guard let date else { return "--" }
        return DashboardFormatter.date.string(from: date)
    }
}

// Ensure DashboardFormatter is available or move it here too.
// Since DashboardFormatter was private in DashboardView, let's make a public shared one or put it here.

struct DashboardFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
