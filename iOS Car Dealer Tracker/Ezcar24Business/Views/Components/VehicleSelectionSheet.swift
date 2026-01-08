import SwiftUI

struct VehicleSelectionSheet: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    @Binding var selectedVehicle: Vehicle?
    let vehicles: [Vehicle]

    private var filteredVehicles: [Vehicle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return vehicles
        }
        return vehicles.filter { vehicle in
            let make = vehicle.make ?? ""
            let model = vehicle.model ?? ""
            let vin = vehicle.vin ?? ""
            return make.lowercased().contains(query) ||
                model.lowercased().contains(query) ||
                vin.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredVehicles.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredVehicles, id: \.self) { vehicle in
                                Button {
                                    selectedVehicle = vehicle
                                    isPresented = false
                                } label: {
                                    VehicleSelectionRow(
                                        vehicle: vehicle,
                                        isSelected: selectedVehicle == vehicle
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("select_vehicle".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .background(ColorTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(ColorTheme.secondaryText)
            TextField("Search Make, Model, VIN...", text: $searchText)
                .foregroundColor(ColorTheme.primaryText)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.circle")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.tertiaryText)
            Text("No vehicles found")
                .font(.headline)
                .foregroundColor(ColorTheme.secondaryText)
        }
        .padding(.top, 60)
    }
}

struct VehicleSelectionRow: View {
    let vehicle: Vehicle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ColorTheme.background)
                    .frame(width: 48, height: 48)
                Image(systemName: "car.fill")
                    .foregroundColor(ColorTheme.primary)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                HStack(spacing: 8) {
                    if let vin = vehicle.vin, !vin.isEmpty {
                        Text(vin)
                            .font(.caption)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ColorTheme.background)
                            .cornerRadius(4)
                    }

                    let yearText = vehicle.year > 0 ? String(vehicle.year) : ""
                    if !yearText.isEmpty {
                        Text(yearText)
                            .font(.caption)
                    }
                }
                .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ColorTheme.success)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? ColorTheme.primary : Color.clear, lineWidth: 2)
        )
    }
}
