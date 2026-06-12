import SwiftUI
import CoreData

struct ClientListView: View {
    @StateObject private var viewModel: ClientViewModel
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @ObservedObject private var permissionService = PermissionService.shared

    @State private var activeSheet: SheetType?
    @State private var showFilters = false
    @State private var dateFilter: DashboardTimeRange = .all

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }
    
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

    var showNavigation: Bool = true

    init(showNavigation: Bool = true) {
        self.showNavigation = showNavigation
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: ClientViewModel(context: context))
    }

    var body: some View {
        Group {
            if showNavigation {
                NavigationView {
                    contentView
                }
            } else {
                contentView
            }
        }
    }

    private var contentView: some View {
        ZStack(alignment: .top) {
            ColorTheme.background.ignoresSafeArea()
            
            listContent
        }
        .navigationTitle("clients".localizedString)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
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
        .padding(10)
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var listContent: some View {
        let clients = visibleClients(applyDateFilter: showFilters)
        
        return ScrollView {
            VStack(spacing: 12) {
                // Search & Filters inside the ScrollView so they pull down nicely
                VStack(spacing: 0) {
                    searchBar
                    
                    if showFilters {
                        filtersBar
                            .padding(.bottom, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                
                if clients.isEmpty {
                    emptyStateContent
                } else {
                    LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
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
                }
            }
            .padding(.bottom, 90) // Clear custom floating tab bar
        }
        .refreshable {
            await performSync()
        }
    }
    
    private var emptyStateContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 60)
            
            ZStack {
                Circle()
                    .fill(ColorTheme.cardBackground)
                    .frame(width: 90, height: 90)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 6)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundColor(ColorTheme.tertiaryText)
            }
            
            VStack(spacing: 8) {
                Text("no_clients_found".localizedString)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText)
                Text("tap_plus_to_add_client".localizedString)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func statusHeader(for status: ClientStatus, count: Int) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                
                Text(status.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText.opacity(0.8))
                    .tracking(0.8)
            }
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(status.color.opacity(0.12))
                .foregroundColor(status.color)
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(ColorTheme.background.opacity(0.95))
    }

    private func dateHeader(for bucket: String, count: Int) -> some View {
        HStack {
            Text(bucket.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(0.8)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorTheme.primary.opacity(0.12))
                .foregroundColor(ColorTheme.primary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(ColorTheme.background.opacity(0.95))
    }

    private func clientRow(for client: Client) -> some View {
        ClientRowView(
            client: client,
            onCall: { phone in call(phone) },
            onWhatsApp: { phone in whatsapp(phone) },
            onSMS: { phone in sms(phone) }
        )
        .onTapGesture {
            activeSheet = .edit(client)
        }
        .contextMenu {
            if let phone = client.phone, !phone.isEmpty {
                Button { call(phone) } label: { Label("call".localizedString, systemImage: "phone") }
                Button { whatsapp(phone) } label: { Label("whatsapp".localizedString, systemImage: "message") }
                Button { sms(phone) } label: { Label("sms".localizedString, systemImage: "message.fill") }
            }
            if canDeleteRecords {
                Button(role: .destructive) { delete(client) } label: { Label("delete".localizedString, systemImage: "trash") }
            }
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
    
    private func sms(_ phone: String) {
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "sms:\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func delete(_ client: Client) {
        guard canDeleteRecords else { return }
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
        guard let date else { return "no_date".localizedString }
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
    var onSMS: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 1. Avatar (Left)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [ColorTheme.primary, ColorTheme.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: ColorTheme.primary.opacity(0.15), radius: 4, x: 0, y: 2)
                
                Text(initials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // 2. Main Info (Middle)
            VStack(alignment: .leading, spacing: 6) {
                // Name & Date Row
                HStack(alignment: .firstTextBaseline) {
                    Text(client.name ?? "unknown_client".localizedString)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(activityText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ColorTheme.primaryText.opacity(0.6))
                }
                
                // Vehicle / Interest
                if !primaryInterestText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "car.fill")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.primary)
                        Text(primaryInterestText)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText.opacity(0.85))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
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
                            // Call Button - Solid Primary Gradient
                            Button {
                                if let phone = client.phone { onCall?(phone) }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [ColorTheme.primary, ColorTheme.primary.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 32, height: 32)
                                        .shadow(color: ColorTheme.primary.opacity(0.25), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.hapticScale)
                            
                            // WhatsApp - Green Gradient
                            Button {
                                if let phone = client.phone { onWhatsApp?(phone) }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.04, green: 0.58, blue: 0.23)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 32, height: 32)
                                        .shadow(color: Color(red: 0.04, green: 0.58, blue: 0.23).opacity(0.25), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "message.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.hapticScale)
                            
                            // SMS - Secondary Blue Gradient
                            Button {
                                if let phone = client.phone { onSMS?(phone) }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [ColorTheme.secondary, ColorTheme.secondary.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 32, height: 32)
                                        .shadow(color: ColorTheme.secondary.opacity(0.25), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.hapticScale)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .cardStyle()
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
            return "today".localizedStringFallback + " " + formatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "yesterday".localizedStringFallback
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
        return "vehicle".localizedStringFallback
    }
}
