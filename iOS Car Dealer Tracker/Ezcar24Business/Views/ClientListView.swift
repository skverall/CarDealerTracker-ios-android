import SwiftUI
import CoreData

struct ClientListView: View {
    @StateObject private var viewModel = ClientViewModel()
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager

    @State private var activeSheet: SheetType?
    @State private var showFilters = false
    @State private var dateFilter: DashboardTimeRange = .all
    
    enum SheetType: Identifiable {
        case new
        case edit(Client)
        
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let client): return client.objectID.uriRepresentation().absoluteString
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                ColorTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search & Filters Area
                    VStack(spacing: 0) {
                        searchBar
                        
                        if showFilters {
                            filtersBar
                                .padding(.bottom, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .background(ColorTheme.background)
                    .zIndex(1)
                    
                    // List Content
                    listContent
                }
            }
            .navigationTitle("clients".localizedString)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showFilters.toggle()
                        }
                        if !showFilters {
                            dateFilter = .all
                        }
                    } label: {
                        Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(ColorTheme.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .new
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(ColorTheme.success)
                            .shadow(color: ColorTheme.success.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .sheet(item: $activeSheet) { item in
                switch item {
                case .new:
                    ClientDetailView(client: nil, context: context) { _ in
                        viewModel.fetchClients()
                    }
                case .edit(let client):
                    ClientDetailView(client: client, context: context) { _ in
                        viewModel.fetchClients()
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ColorTheme.secondaryText)
            
            TextField("search_clients_placeholder".localizedString, text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.subheadline)
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(8)
        .background(ColorTheme.cardBackground)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var listContent: some View {
        let clients = visibleClients(applyDateFilter: showFilters)
        
        return Group {
            if clients.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                        if showFilters {
                            ForEach(groupedClientsByDate(clients), id: \.key) { bucket, bucketClients in
                                Section(header: dateHeader(for: bucket, count: bucketClients.count)) {
                                    ForEach(bucketClients, id: \.self) { client in
                                        clientRow(for: client)
                                    }
                                }
                            }
                        } else {
                            ForEach(ClientStatus.allCases) { status in
                                let sectionClients = clients.filter { $0.clientStatus == status }
                                if !sectionClients.isEmpty {
                                    Section(header: statusHeader(for: status, count: sectionClients.count)) {
                                        ForEach(sectionClients, id: \.self) { client in
                                            clientRow(for: client)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                    .padding(.top, 8)
                }
                .refreshable {
                    await performSync()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 100)
                
                ZStack {
                    Circle()
                        .fill(ColorTheme.background)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 40))
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                
                
                VStack(spacing: 8) {
                    Text("no_clients_found".localizedString)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text("tap_plus_to_add_client".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                
                Spacer(minLength: 100)
            }
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.6)
        }
        .refreshable {
            await performSync()
        }
    }

    private func statusHeader(for status: ClientStatus, count: Int) -> some View {
        HStack {
            Text(status.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ColorTheme.cardBackground)
                .foregroundColor(ColorTheme.secondaryText)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        }
        .padding(.vertical, 4)
        .background(ColorTheme.background.opacity(0.95))
    }

    private func dateHeader(for bucket: String, count: Int) -> some View {
        HStack {
            Text(bucket)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ColorTheme.secondaryText)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .foregroundColor(ColorTheme.secondaryText)
                .clipShape(Circle())
        }
        .padding(.vertical, 4)
        .background(ColorTheme.background.opacity(0.95))
    }

    private func clientRow(for client: Client) -> some View {
        ClientRowView(
            client: client,
            onCall: { phone in call(phone) },
            onWhatsApp: { phone in whatsapp(phone) }
        )
        .onTapGesture {
            activeSheet = .edit(client)
        }
        .contextMenu {
            if let phone = client.phone, !phone.isEmpty {
                Button { call(phone) } label: { Label("call".localizedString, systemImage: "phone") }
                Button { whatsapp(phone) } label: { Label("whatsapp".localizedString, systemImage: "message") }
            }
            Button(role: .destructive) { delete(client) } label: { Label("delete".localizedString, systemImage: "trash") }
        }
    }
    
    // MARK: - Actions
    
    private func call(_ phone: String) {
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func whatsapp(_ phone: String) {
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "https://wa.me/\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func delete(_ client: Client) {
        guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
        let deletedId = viewModel.deleteClient(client)
        if let id = deletedId {
            Task {
                await CloudSyncManager.shared?.deleteClient(id: id, dealerId: dealerId)
            }
        }
        viewModel.fetchClients()
    }

    // MARK: - Filters
    
    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Main Date Filter Menu
                Menu {
                    Button("all_time".localizedString) { dateFilter = .all }
                    Button("today".localizedString) { dateFilter = .today }
                    Button("last_7_days".localizedString) { dateFilter = .week }
                    Button("last_30_days".localizedString) { dateFilter = .month }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(dateFilterTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .opacity(0.5)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ColorTheme.cardBackground)
                    .foregroundColor(ColorTheme.primaryText)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                }

                // Clear Filter Button
                if dateFilter != .all {
                    Button {
                        withAnimation {
                            dateFilter = .all
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                            Text("clear".localizedString)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(ColorTheme.secondaryText)
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var dateFilterTitle: String {
        switch dateFilter {
        case .all: return "all_time".localizedString
        case .today: return "today".localizedString
        case .week: return "this_week".localizedString
        case .month: return "this_month".localizedString
        case .threeMonths: return "last_3_months".localizedString
        case .sixMonths: return "last_6_months".localizedString
        }
    }

    // MARK: - Data Helpers
    
    private func visibleClients(applyDateFilter: Bool) -> [Client] {
        let searchFiltered = viewModel.filteredClients()
        let filtered = applyDateFilter ? searchFiltered.filter(matchesDateFilter) : searchFiltered
        
        // Sort: Newest first
        return filtered.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private func groupedClientsByDate(_ clients: [Client]) -> [(key: String, items: [Client])] {
        let groups = Dictionary(grouping: clients) { client in
            dateBucket(for: client.createdAt)
        }

        func order(_ key: String) -> Int {
            switch key {
            case "today".localizedString: return 0
            case "yesterday".localizedString: return 1
            case "last_7_days".localizedString: return 2
            case "last_30_days".localizedString: return 3
            case "no_date".localizedString: return 5
            default: return 4
            }
        }

        return groups
            .map { ($0.key, $0.value.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }) }
            .sorted { a, b in
                let oa = order(a.0)
                let ob = order(b.0)
                if oa != ob { return oa < ob }
                return a.0 < b.0
            }
    }

    private func matchesDateFilter(_ client: Client) -> Bool {
        guard showFilters else { return true }
        guard dateFilter != .all else { return true }
        guard let createdAt = client.createdAt else { return false }
        if let start = dateFilter.startDate, createdAt < start { return false }
        if let end = dateFilter.endDate, createdAt >= end { return false }
        return true
    }

    private func dateBucket(for date: Date?) -> String {
        guard let date else { return "No Date" }
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) { return "today".localizedString }
        if cal.isDateInYesterday(date) { return "yesterday".localizedString }
        if let seven = cal.date(byAdding: .day, value: -7, to: now), date >= seven { return "last_7_days".localizedString }
        if let thirty = cal.date(byAdding: .day, value: -30, to: now), date >= thirty { return "last_30_days".localizedString }
        return "older".localizedString
    }

    private func performSync() async {
        guard case .signedIn(let user) = sessionStore.status else { return }
        await withCheckedContinuation { continuation in
            Task.detached {
                await cloudSyncManager.manualSync(user: user)
                continuation.resume()
            }
        }
        viewModel.fetchClients()
    }
}

// MARK: - Client Row View

struct ClientRowView: View {
    let client: Client
    var onCall: ((String) -> Void)?
    var onWhatsApp: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 1. Avatar (Left)
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Text(initials)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primary)
            }
            
            // 2. Main Info (Middle)
            VStack(alignment: .leading, spacing: 6) {
                // Name & Date Row
                HStack(alignment: .firstTextBaseline) {
                    Text(client.name ?? "unknown_client".localizedString)
                        .font(.system(size: 16, weight: .bold)) // Bolder name
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(activityText)
                        .font(.system(size: 11, weight: .medium)) // Slightly bolder
                        .foregroundColor(ColorTheme.primaryText.opacity(0.6)) // Darker than tertiary
                }
                
                // Vehicle / Interest (The "Content" of the card)
                // User wants this to be informative but clean.
                if !primaryInterestText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft") // Generic content icon, or car if vehicle
                            .font(.caption2)
                            .foregroundColor(ColorTheme.primary) // Highlighted icon
                        Text(primaryInterestText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(ColorTheme.primaryText.opacity(0.9)) // Darker text
                            .lineLimit(2) // Allow 2 lines for better context if needed
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Footer: Status + Actions
                HStack(spacing: 0) {
                    // Status Badge
                    Text(client.clientStatus.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(client.clientStatus.color.opacity(0.12))
                        .foregroundColor(client.clientStatus.color)
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Actions
                    if hasPhone {
                        HStack(spacing: 12) {
                            // Call Button - Made "Highlighted" as requested
                            Button {
                                if let phone = client.phone { onCall?(phone) }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(ColorTheme.primary) // Solid primary color
                                        .frame(width: 32, height: 32)
                                        .shadow(color: ColorTheme.primary.opacity(0.3), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // WhatsApp - Explicit Green Icon
                            Button {
                                if let phone = client.phone { onWhatsApp?(phone) }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.green) // Explicit WhatsApp Green
                                        .frame(width: 32, height: 32)
                                        .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "message.circle.fill") // WhatsApp-style icon
                                        .symbolVariant(.fill) // Ensure fill
                                        .font(.system(size: 18)) // Slightly larger icon inside
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
    
    private var hasPhone: Bool {
        return client.phone != nil && !(client.phone?.isEmpty ?? true)
    }
    
    private var isNew: Bool {
        guard let date = client.createdAt else { return false }
        return Date().timeIntervalSince(date) < 24 * 3600
    }
    
    private var initials: String {
        let name = client.name ?? ""
        let components = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if let first = components.first?.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    private var primaryInterestText: String {
        if let vehicle = client.vehicle {
            return vehicle.displayName
        }
        if let request = client.requestDetails, !request.isEmpty {
            return request
        }
        // If nothing is selected, we can return empty to hide the row, or a default text.
        // For compact design, hiding empty info might be better.
        return "" 
    }
    
    private var activityText: String {
        guard let date = client.createdAt else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today " + formatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
    }
}

extension Vehicle {
    var displayName: String {
        let make = make?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        if let vin = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty {
            return vin
        }
        return "Vehicle"
    }
}

