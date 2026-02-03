//
//  InventoryAlertCard.swift
//  Ezcar24Business
//
//  Card showing alert details with severity indicator
//

import SwiftUI

struct InventoryAlertCard: View {
    let alert: InventoryAlert
    let vehicle: Vehicle?
    var onDismiss: (() -> Void)? = nil
    
    private var severityColor: Color {
        switch alert.severity {
        case "high":
            return ColorTheme.danger
        case "medium":
            return Color.orange
        case "low":
            return ColorTheme.warning
        default:
            return ColorTheme.secondaryText
        }
    }
    
    private var severityIcon: String {
        switch alert.severity {
        case "high":
            return "exclamationmark.triangle.fill"
        case "medium":
            return "exclamationmark.circle.fill"
        case "low":
            return "info.circle.fill"
        default:
            return "bell.fill"
        }
    }
    
    private var alertType: InventoryAlertType? {
        guard let typeString = alert.alertType else { return nil }
        return InventoryAlertType(rawValue: typeString)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: alertType?.iconName ?? severityIcon)
                    .font(.title3)
                    .foregroundColor(severityColor)
                    .frame(width: 40, height: 40)
                    .background(severityColor.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(alertType?.displayName ?? "Alert")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    if let vehicle = vehicle {
                        Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                
                Spacer()
                
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
                    }
                }
            }
            
            if let message = alert.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(severityColor)
                        .frame(width: 6, height: 6)
                    
                    Text((alert.severity ?? "low").capitalized)
                        .font(.caption)
                        .foregroundColor(severityColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.1))
                .cornerRadius(4)
                
                Spacer()
                
                if let date = alert.createdAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
            }
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

struct InventoryAlertListItem: View {
    let alert: InventoryAlert
    let vehicle: Vehicle?
    var onDismiss: (() -> Void)? = nil
    
    private var severityColor: Color {
        switch alert.severity {
        case "high":
            return ColorTheme.danger
        case "medium":
            return Color.orange
        case "low":
            return ColorTheme.warning
        default:
            return ColorTheme.secondaryText
        }
    }
    
    private var alertType: InventoryAlertType? {
        guard let typeString = alert.alertType else { return nil }
        return InventoryAlertType(rawValue: typeString)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alertType?.iconName ?? "bell.fill")
                .font(.subheadline)
                .foregroundColor(severityColor)
                .frame(width: 32, height: 32)
                .background(severityColor.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alertType?.displayName ?? "Alert")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primaryText)
                
                if let vehicle = vehicle {
                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                if let message = alert.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct InventoryAlertBanner: View {
    let count: Int
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) Active Alert\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Tap to review inventory alerts")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [ColorTheme.danger, Color.orange]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    
    let alert1 = InventoryAlert(context: context)
    alert1.id = UUID()
    alert1.alertType = InventoryAlertType.longDaysInInventory.rawValue
    alert1.severity = "high"
    alert1.message = "Vehicle has been in inventory for 120 days. Consider aggressive pricing."
    alert1.createdAt = Date()
    
    let alert2 = InventoryAlert(context: context)
    alert2.id = UUID()
    alert2.alertType = InventoryAlertType.lowROI.rawValue
    alert2.severity = "medium"
    alert2.message = "Projected ROI is 5.0%. Consider cost reduction or price increase."
    alert2.createdAt = Date().addingTimeInterval(-3600)
    
    let vehicle = Vehicle(context: context)
    vehicle.id = UUID()
    vehicle.make = "Toyota"
    vehicle.model = "Camry"
    vehicle.year = 2022
    
    return ScrollView {
        VStack(spacing: 16) {
            InventoryAlertBanner(count: 3) {}
            
            InventoryAlertCard(
                alert: alert1,
                vehicle: vehicle,
                onDismiss: {}
            )
            
            InventoryAlertCard(
                alert: alert2,
                vehicle: vehicle,
                onDismiss: {}
            )
            
            InventoryAlertListItem(
                alert: alert1,
                vehicle: vehicle,
                onDismiss: {}
            )
            
            InventoryAlertListItem(
                alert: alert2,
                vehicle: vehicle,
                onDismiss: {}
            )
        }
        .padding()
    }
    .background(ColorTheme.secondaryBackground)
}