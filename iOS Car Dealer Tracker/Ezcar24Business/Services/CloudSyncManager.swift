import Foundation
import CoreData
import Supabase

enum SyncHUDState: Equatable {
    case syncing
    case success
    case failure
}

private struct ApplicationLogInsert: Encodable {
    let level: String
    let message: String
    let context: [String: String]?
    let userId: UUID?

    enum CodingKeys: String, CodingKey {
        case level
        case message
        case context
        case userId = "user_id"
    }
}


@MainActor
final class CloudSyncManager: ObservableObject {
    static var shared: CloudSyncManager?

    private let client: SupabaseClient
    private var writeClient: SupabaseClient { client }
    private let context: NSManagedObjectContext

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published var syncHUDState: SyncHUDState?
    @Published var errorMessage: String?

    private var lastSyncTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: "lastSyncTimestamp") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastSyncTimestamp") }
    }

    init(client: SupabaseClient, context: NSManagedObjectContext) {
        self.client = client
        self.context = context
    }

    // MARK: - Public API

    func syncAfterLogin(user: Auth.User) async {
        guard !isSyncing else { return }
        isSyncing = true
        
        // Only show blocking HUD if this is the first sync ever
        let isFirstSync = lastSyncTimestamp == nil
        if isFirstSync {
            syncHUDState = .syncing
        }
        
        defer { isSyncing = false }

        let dealerId = user.id
        var effectiveSince = lastSyncTimestamp
        
        // Create a background context for heavy lifting
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        let writeClient = self.writeClient
        
        do {
            // 1. Flush any queued offline operations first (Main Actor is fine for this as it's usually small)
            await processOfflineQueue(dealerId: dealerId)

            // Pending deletes should block resurrection during this sync
            let pendingDeletes = await pendingDeleteIds()

            // Perform heavy sync logic on background context
            let localClientCount = try await bgContext.perform {
                let request: NSFetchRequest<Client> = Client.fetchRequest()
                request.includesPendingChanges = false
                return try bgContext.count(for: request)
            }
            if localClientCount == 0 {
                effectiveSince = nil
            }

            // 2. Fetch remote changes (Network is async, doesn't block context)
            let snapshot = try await fetchRemoteChanges(dealerId: dealerId, since: effectiveSince)
            let filteredSnapshot = filterSnapshot(snapshot, skippingIds: pendingDeletes)

            // 3. Ensure default accounts exist remotely if none locally
            let localAccountCount = try await bgContext.perform {
                try bgContext.count(for: FinancialAccount.fetchRequest())
            }
            let accountsForMerge: [RemoteFinancialAccount]
            if localAccountCount == 0 {
                accountsForMerge = await self.ensureDefaultAccounts(context: bgContext, for: dealerId, existingAccounts: filteredSnapshot.accounts, writeClient: writeClient)
            } else {
                accountsForMerge = filteredSnapshot.accounts
            }
            let snapshotForMerge = RemoteSnapshot(
                users: filteredSnapshot.users,
                accounts: accountsForMerge,
                accountTransactions: filteredSnapshot.accountTransactions,
                vehicles: filteredSnapshot.vehicles,
                templates: filteredSnapshot.templates,
                expenses: filteredSnapshot.expenses,
                sales: filteredSnapshot.sales,
                debts: filteredSnapshot.debts,
                debtPayments: filteredSnapshot.debtPayments,
                clients: filteredSnapshot.clients
            )
            
            try await bgContext.perform {
                // 4. Smart Merge
                try self.mergeRemoteChanges(snapshotForMerge, context: bgContext, dealerId: dealerId)

                // 4.5. CRITICAL: Save the merged changes to Core Data
                if bgContext.hasChanges {
                    try bgContext.save()
                    print("CloudSyncManager: Saved \(snapshotForMerge.vehicles.count) vehicles, \(snapshotForMerge.expenses.count) expenses to Core Data")
                }
            }

            // 5. Push local changes - Now done AFTER merge to ensure IDs are resolved
            try await self.pushLocalChanges(context: bgContext, dealerId: dealerId, writeClient: writeClient, skippingVehicleIds: pendingDeletes[.vehicle] ?? [])
            
            // 6. Update timestamp (Main Actor)
            lastSyncTimestamp = Date()
            lastSyncAt = lastSyncTimestamp
            
            // 7. Background tasks
            Task { [weak self] in
                await self?.downloadVehicleImages(dealerId: dealerId, vehicles: filteredSnapshot.vehicles)
            }
            
            if isFirstSync {
                syncHUDState = .success
                scheduleHideHUD(for: .success)
            }
            
            // 8. Process offline queue again
            await processOfflineQueue(dealerId: dealerId)
            
        } catch {

            // Ignore cancellation errors
            if error is CancellationError {
                return
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
            if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                return
            }
            
            print("CloudSyncManager sync error: \(error)")
            await logSyncError(
                rpc: "syncAfterLogin",
                dealerId: user.id,
                error: error
            )
            if isFirstSync {
                syncHUDState = .failure
                scheduleHideHUD(for: .failure)
            }
            showError("Sync failed: \(error.localizedDescription)")
        }
    }

    func manualSync(user: Auth.User, force: Bool = false) async {
        // Fast pull-to-refresh: only fetch and merge remote changes
        // Skip push and offline queue for speed
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let dealerId = user.id
        let syncStartedAt = Date()
        let since = force ? nil : lastSyncTimestamp
        
        // Collect pending IDs in the offline queue to avoid deleting unsynced local items during a full refresh
        let queueItems = await SyncQueueManager.shared.getAllItems()
        let decoder = JSONDecoder()
        var protectedIds: [SyncEntityType: Set<UUID>] = [:]
        func protect(_ type: SyncEntityType, id: UUID) {
            var set = protectedIds[type] ?? []
            set.insert(id)
            protectedIds[type] = set
        }
        
        for item in queueItems {
            switch item.entityType {
            case .vehicle:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.vehicle, id: id) }
                } else if let remote = try? decoder.decode(RemoteVehicle.self, from: item.payload) {
                    protect(.vehicle, id: remote.id)
                }
            case .expense:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.expense, id: id) }
                } else if let remote = try? decoder.decode(RemoteExpense.self, from: item.payload) {
                    protect(.expense, id: remote.id)
                }
            case .sale:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.sale, id: id) }
                } else if let remote = try? decoder.decode(RemoteSale.self, from: item.payload) {
                    protect(.sale, id: remote.id)
                }
            case .client:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.client, id: id) }
                } else if let remote = try? decoder.decode(RemoteClient.self, from: item.payload) {
                    protect(.client, id: remote.id)
                }
            case .user:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.user, id: id) }
                } else if let remote = try? decoder.decode(RemoteDealerUser.self, from: item.payload) {
                    protect(.user, id: remote.id)
                }
            case .account:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.account, id: id) }
                } else if let remote = try? decoder.decode(RemoteFinancialAccount.self, from: item.payload) {
                    protect(.account, id: remote.id)
                }
            case .accountTransaction:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.accountTransaction, id: id) }
                } else if let remote = try? decoder.decode(RemoteAccountTransaction.self, from: item.payload) {
                    protect(.accountTransaction, id: remote.id)
                }
            case .template:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.template, id: id) }
                } else if let remote = try? decoder.decode(RemoteExpenseTemplate.self, from: item.payload) {
                    protect(.template, id: remote.id)
                }
            case .debt:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.debt, id: id) }
                } else if let remote = try? decoder.decode(RemoteDebt.self, from: item.payload) {
                    protect(.debt, id: remote.id)
                }
            case .debtPayment:
                if item.operation == .delete {
                    if let id = try? decoder.decode(UUID.self, from: item.payload) { protect(.debtPayment, id: id) }
                } else if let remote = try? decoder.decode(RemoteDebtPayment.self, from: item.payload) {
                    protect(.debtPayment, id: remote.id)
                }
            }
        }

        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        do {
            // 0. Push local changes first to avoid overwrites during merge
            await processOfflineQueue(dealerId: dealerId)
            
            // 1. Fetch remote changes only (fastest path)
            let snapshot = try await fetchRemoteChanges(dealerId: dealerId, since: since)

            // Skip if no changes
            let hasChanges = !snapshot.vehicles.isEmpty || !snapshot.expenses.isEmpty ||
                            !snapshot.sales.isEmpty || !snapshot.debts.isEmpty ||
                            !snapshot.debtPayments.isEmpty || !snapshot.clients.isEmpty ||
                            !snapshot.users.isEmpty || !snapshot.accounts.isEmpty ||
                            !snapshot.accountTransactions.isEmpty || !snapshot.templates.isEmpty

            guard hasChanges else {
                lastSyncTimestamp = Date()
                lastSyncAt = lastSyncTimestamp
                return
            }

            // 2. Merge changes (with missing cleanup on full refresh)
            let cleanupContext: MissingCleanupContext? = force ? MissingCleanupContext(
                syncStartedAt: syncStartedAt,
                remoteIds: [
                    .vehicle: Set(snapshot.vehicles.map { $0.id }),
                    .expense: Set(snapshot.expenses.map { $0.id }),
                    .sale: Set(snapshot.sales.map { $0.id }),
                    .debt: Set(snapshot.debts.map { $0.id }),
                    .debtPayment: Set(snapshot.debtPayments.map { $0.id }),
                    .client: Set(snapshot.clients.map { $0.id }),
                    .user: Set(snapshot.users.map { $0.id }),
                    .account: Set(snapshot.accounts.map { $0.id }),
                    .accountTransaction: Set(snapshot.accountTransactions.map { $0.id }),
                    .template: Set(snapshot.templates.map { $0.id })
                ],
                protectedIds: protectedIds
            ) : nil
            try await bgContext.perform {
                try self.mergeRemoteChanges(
                    snapshot,
                    context: bgContext,
                    dealerId: dealerId,
                    missingCleanup: cleanupContext
                )
                if bgContext.hasChanges {
                    try bgContext.save()
                }
            }

            // 3. Update timestamp
            lastSyncTimestamp = Date()
            lastSyncAt = lastSyncTimestamp

            // 4. Download images in background (non-blocking)
            Task.detached { [weak self] in
                await self?.downloadVehicleImages(dealerId: dealerId, vehicles: snapshot.vehicles)
            }

        } catch {
            if !(error is CancellationError) {
                print("CloudSyncManager manualSync error: \(error)")
                await logSyncError(
                    rpc: "manualSync",
                    dealerId: dealerId,
                    error: error
                )
            }
        }
    }

    /// Full sync with push - use for initial sync or "Sync Now" button
    func fullSync(user: Auth.User) async {
        await syncAfterLogin(user: user)
    }

    func showError(_ message: String) {
        Task { @MainActor in
            self.errorMessage = message
            // Auto-dismiss after 5 seconds
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            if self.errorMessage == message {
                self.errorMessage = nil
            }
        }
    }

    func resetSyncState() {
        lastSyncTimestamp = nil
        lastSyncAt = nil
        syncHUDState = nil
        errorMessage = nil
    }

    // MARK: - Diagnostics

    func runDiagnostics(dealerId: UUID) async -> SyncDiagnosticsReport {
        let queueItems = await SyncQueueManager.shared.getAllItems().filter { $0.dealerId == dealerId }
        let queueSummary = summarizeQueue(items: queueItems)

        let localCounts: [SyncEntityType: Int] = await context.perform { [context] in
            func count(_ entityName: String) -> Int {
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                request.predicate = NSPredicate(format: "deletedAt == nil")
                request.includesSubentities = false
                return (try? context.count(for: request)) ?? 0
            }

            return [
                .vehicle: count("Vehicle"),
                .expense: count("Expense"),
                .sale: count("Sale"),
                .debt: count("Debt"),
                .debtPayment: count("DebtPayment"),
                .client: count("Client"),
                .user: count("User"),
                .account: count("FinancialAccount"),
                .accountTransaction: count("AccountTransaction"),
                .template: count("ExpenseTemplate")
            ]
        }

        var remoteCounts: [SyncEntityType: Int] = [:]
        var remoteFetchError: String?
        do {
            let snapshot = try await fetchRemoteChanges(dealerId: dealerId, since: nil)

            func countActive<T>(_ values: [T], deletedAt: (T) -> Date?) -> Int {
                values.filter { deletedAt($0) == nil }.count
            }

            remoteCounts = [
                .vehicle: countActive(snapshot.vehicles) { $0.deletedAt },
                .expense: countActive(snapshot.expenses) { $0.deletedAt },
                .sale: countActive(snapshot.sales) { $0.deletedAt },
                .debt: countActive(snapshot.debts) { $0.deletedAt },
                .debtPayment: countActive(snapshot.debtPayments) { $0.deletedAt },
                .client: countActive(snapshot.clients) { $0.deletedAt },
                .user: countActive(snapshot.users) { user in
                    guard let deletedAt = user.deletedAt else { return nil }
                    return CloudSyncManager.parseDateAndTime(deletedAt)
                },
                .account: countActive(snapshot.accounts) { $0.deletedAt },
                .accountTransaction: countActive(snapshot.accountTransactions) { $0.deletedAt },
                .template: countActive(snapshot.templates) { $0.deletedAt }
            ]
        } catch {
            remoteFetchError = error.localizedDescription
        }

        let entityCounts = SyncEntityType.allCases.map { entity in
            SyncEntityCount(
                entity: entity,
                localCount: localCounts[entity] ?? 0,
                remoteCount: remoteCounts[entity]
            )
        }

        return SyncDiagnosticsReport(
            generatedAt: Date(),
            lastSyncAt: lastSyncAt,
            isSyncing: isSyncing,
            offlineQueueCount: queueItems.count,
            offlineQueueSummary: queueSummary,
            entityCounts: entityCounts,
            remoteFetchError: remoteFetchError
        )
    }

    private func isNetworkConnectivityError(_ error: Error) -> Bool {
        func unwrapURLError(_ error: Error) -> URLError? {
            if let urlError = error as? URLError { return urlError }
            let nsError = error as NSError
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                return unwrapURLError(underlying)
            }
            return nil
        }

        guard let urlError = unwrapURLError(error) else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private func summarizeQueue(items: [SyncQueueItem]) -> [SyncQueueSummaryItem] {
        let grouped = Dictionary(grouping: items) { item in
            SyncQueueGroupKey(entity: item.entityType, operation: item.operation)
        }
        let summaries = grouped.map { key, value in
            SyncQueueSummaryItem(entity: key.entity, operation: key.operation, count: value.count)
        }
        return summaries.sorted { a, b in
            if a.entity.sortOrder == b.entity.sortOrder {
                return a.operation.sortOrder < b.operation.sortOrder
            }
            return a.entity.sortOrder < b.entity.sortOrder
        }
    }

    private func savedLocallySyncFailureMessage(for error: Error) -> String {
        if isNetworkConnectivityError(error) {
            return "Saved locally. Will sync when online."
        }
        if error is PostgrestError {
            return "Saved locally. Server sync error. Will retry."
        }
        return "Saved locally. Sync failed. Will retry."
    }

    private func logSyncError(
        rpc: String,
        dealerId: UUID?,
        entityType: SyncEntityType? = nil,
        payloadId: UUID? = nil,
        extraContext: [String: String] = [:],
        error: Error
    ) async {
        // Ignore cancellation errors to avoid noisy logs.
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

        var ctx: [String: String] = [
            "component": "CloudSyncManager",
            "rpc": rpc,
            "error": error.localizedDescription,
            "error_type": String(describing: type(of: error)),
            "ns_error_domain": nsError.domain,
            "ns_error_code": String(nsError.code)
        ]

        if let postgrestError = error as? PostgrestError {
            if let code = postgrestError.code { ctx["postgrest_code"] = code }
            if let detail = postgrestError.detail { ctx["postgrest_detail"] = detail }
            if let hint = postgrestError.hint { ctx["postgrest_hint"] = hint }
            ctx["postgrest_message"] = postgrestError.message
        }

        if let dealerId {
            ctx["dealer_id"] = dealerId.uuidString
        }
        if let entityType {
            ctx["entity_type"] = entityType.rawValue
        }
        if let payloadId {
            ctx["payload_id"] = payloadId.uuidString
        }
        if !extraContext.isEmpty {
            for (k, v) in extraContext {
                ctx[k] = v
            }
        }
        appendCoreDataValidationDetails(from: nsError, into: &ctx)

        let row = ApplicationLogInsert(
            level: "error",
            message: "Sync error: \(rpc)",
            context: ctx,
            userId: dealerId
        )

        do {
            try await writeClient
                .from("application_logs")
                .insert(row)
                .execute()
        } catch {
            // Avoid recursion: only print if logging fails.
            print("CloudSyncManager logSyncError failed: \(error)")
        }
    }

    private func appendCoreDataValidationDetails(from error: NSError, into ctx: inout [String: String]) {
        guard error.domain == NSCocoaErrorDomain else { return }

        func setValue(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            ctx[key] = value
        }

        if let detailed = error.userInfo[NSDetailedErrorsKey] as? [NSError], !detailed.isEmpty {
            ctx["coredata_error_count"] = "\(detailed.count)"
            for (index, detail) in detailed.prefix(5).enumerated() {
                let prefix = "coredata_error_\(index + 1)"
                setValue("\(prefix)_code", "\(detail.code)")
                setValue("\(prefix)_description", detail.localizedDescription)
                if let key = detail.userInfo[NSValidationKeyErrorKey] as? String {
                    setValue("\(prefix)_key", key)
                }
                if let obj = detail.userInfo[NSValidationObjectErrorKey] as? NSManagedObject {
                    setValue("\(prefix)_entity", obj.entity.name ?? "")
                    setValue("\(prefix)_object_id", obj.objectID.uriRepresentation().absoluteString)
                }
            }
        } else {
            if let key = error.userInfo[NSValidationKeyErrorKey] as? String {
                setValue("coredata_validation_key", key)
            }
            if let obj = error.userInfo[NSValidationObjectErrorKey] as? NSManagedObject {
                setValue("coredata_validation_entity", obj.entity.name ?? "")
                setValue("coredata_validation_object_id", obj.objectID.uriRepresentation().absoluteString)
            }
        }
    }

    private func scheduleHideHUD(for state: SyncHUDState) {
        let delay: UInt64
        switch state {
        case .success:
            delay = 1_200_000_000 // ~1.2 seconds
        case .failure:
            delay = 1_800_000_000 // ~1.8 seconds
        case .syncing:
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            if self.syncHUDState == state {
                self.syncHUDState = nil
            }
        }
    }


    // MARK: - Offline Queue Processing
    
    // MARK: - Offline Queue Processing
    
    func processOfflineQueue(dealerId: UUID) async {
        let items = await SyncQueueManager.shared.getAllItems()
        guard !items.isEmpty else { return }
        
        for item in items {
            // Filter by dealerId to prevent cross-user data leaks
            guard item.dealerId == dealerId else { continue }
            
            do {
                switch item.operation {
                case .upsert:
                    try await processUpsert(item)
                case .delete:
                    try await processDelete(item)
                }
                await SyncQueueManager.shared.remove(id: item.id)
            } catch {
                print("Failed to process offline item \(item.id): \(error)")
                let rpcName: String = {
                    switch item.operation {
                    case .upsert:
                        switch item.entityType {
                        case .vehicle: return "sync_vehicles"
                        case .expense: return "sync_expenses"
                        case .sale: return "sync_sales"
                        case .client: return "sync_clients"
                        case .user: return "sync_users"
                        case .account: return "sync_accounts"
                        case .accountTransaction: return "sync_account_transactions"
                        case .template: return "sync_templates"
                        case .debt: return "sync_debts"
                        case .debtPayment: return "sync_debt_payments"
                        }
                    case .delete:
                        switch item.entityType {
                        case .vehicle: return "delete_crm_vehicles"
                        case .expense: return "delete_crm_expenses"
                        case .sale: return "delete_crm_sales"
                        case .client: return "delete_crm_dealer_clients"
                        case .user: return "delete_crm_dealer_users"
                        case .account: return "delete_crm_financial_accounts"
                        case .accountTransaction: return "delete_crm_account_transactions"
                        case .template: return "delete_crm_expense_templates"
                        case .debt: return "delete_crm_debts"
                        case .debtPayment: return "delete_crm_debt_payments"
                        }
                    }
                }()

                let recordId: UUID? = {
                    let decoder = JSONDecoder()
                    switch item.operation {
                    case .delete:
                        return try? decoder.decode(UUID.self, from: item.payload)
                    case .upsert:
                        switch item.entityType {
                        case .vehicle: return (try? decoder.decode(RemoteVehicle.self, from: item.payload))?.id
                        case .expense: return (try? decoder.decode(RemoteExpense.self, from: item.payload))?.id
                        case .sale: return (try? decoder.decode(RemoteSale.self, from: item.payload))?.id
                        case .client: return (try? decoder.decode(RemoteClient.self, from: item.payload))?.id
                        case .user: return (try? decoder.decode(RemoteDealerUser.self, from: item.payload))?.id
                        case .account: return (try? decoder.decode(RemoteFinancialAccount.self, from: item.payload))?.id
                        case .accountTransaction: return (try? decoder.decode(RemoteAccountTransaction.self, from: item.payload))?.id
                        case .template: return (try? decoder.decode(RemoteExpenseTemplate.self, from: item.payload))?.id
                        case .debt: return (try? decoder.decode(RemoteDebt.self, from: item.payload))?.id
                        case .debtPayment: return (try? decoder.decode(RemoteDebtPayment.self, from: item.payload))?.id
                        }
                    }
                }()

                await logSyncError(
                    rpc: rpcName,
                    dealerId: dealerId,
                    entityType: item.entityType,
                    payloadId: recordId,
                    extraContext: [
                        "offline_queue_item_id": item.id.uuidString,
                        "operation": item.operation.rawValue
                    ],
                    error: error
                )
            }
        }
    }

    private func pendingDeleteIds() async -> [SyncEntityType: Set<UUID>] {
        let items = await SyncQueueManager.shared.getAllItems()
        let decoder = JSONDecoder()
        var ids: [SyncEntityType: Set<UUID>] = [:]
        
        for item in items {
            guard item.operation == .delete else { continue }
            if let id = try? decoder.decode(UUID.self, from: item.payload) {
                var set = ids[item.entityType] ?? []
                set.insert(id)
                ids[item.entityType] = set
            }
        }
        return ids
    }

    private func performDeleteRPC(for entity: SyncEntityType, id: UUID, dealerId: UUID) async throws {
        let rpcName: String
        switch entity {
        case .vehicle:
            rpcName = "delete_crm_vehicles"
        case .expense:
            rpcName = "delete_crm_expenses"
        case .sale:
            rpcName = "delete_crm_sales"
        case .client:
            rpcName = "delete_crm_dealer_clients"
        case .user:
            rpcName = "delete_crm_dealer_users"
        case .account:
            rpcName = "delete_crm_financial_accounts"
        case .accountTransaction:
            rpcName = "delete_crm_account_transactions"
        case .template:
            rpcName = "delete_crm_expense_templates"
        case .debt:
            rpcName = "delete_crm_debts"
        case .debtPayment:
            rpcName = "delete_crm_debt_payments"
        }
        
        try await writeClient
            .rpc(
                rpcName,
                params: [
                    "p_id": id.uuidString,
                    "p_dealer_id": dealerId.uuidString
                ]
            )
            .execute()
    }

    private func fetchLocalEntity<T: NSManagedObject>(_ type: T.Type, id: UUID) -> T? {
        let request = NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func deleteEntityById(_ id: UUID, dealerId: UUID, entity: SyncEntityType) async throws {
        switch entity {
        case .vehicle:
            if let vehicle = fetchLocalEntity(Vehicle.self, id: id) {
                await deleteVehicle(vehicle, dealerId: dealerId)
                return
            }
        case .expense:
            if let expense = fetchLocalEntity(Expense.self, id: id) {
                await deleteExpense(expense, dealerId: dealerId)
                return
            }
        case .sale:
            if let sale = fetchLocalEntity(Sale.self, id: id) {
                await deleteSale(sale, dealerId: dealerId)
                return
            }
        case .client:
            if let client = fetchLocalEntity(Client.self, id: id) {
                await deleteClient(client, dealerId: dealerId)
                return
            }
        case .user:
            if let user = fetchLocalEntity(User.self, id: id) {
                await deleteUser(user, dealerId: dealerId)
                return
            }
        case .account:
            if let account = fetchLocalEntity(FinancialAccount.self, id: id) {
                await deleteFinancialAccount(account, dealerId: dealerId)
                return
            }
        case .accountTransaction:
            if let transaction = fetchLocalEntity(AccountTransaction.self, id: id) {
                await deleteAccountTransaction(transaction, dealerId: dealerId)
                return
            }
        case .template:
            if let template = fetchLocalEntity(ExpenseTemplate.self, id: id) {
                await deleteTemplate(template, dealerId: dealerId)
                return
            }
        case .debt:
            if let debt = fetchLocalEntity(Debt.self, id: id) {
                await deleteDebt(debt, dealerId: dealerId)
                return
            }
        case .debtPayment:
            if let payment = fetchLocalEntity(DebtPayment.self, id: id) {
                await deleteDebtPayment(payment, dealerId: dealerId)
                return
            }
        }

        try await performDeleteRPC(for: entity, id: id, dealerId: dealerId)
    }

    private func enqueueDelete(_ entity: SyncEntityType, id: UUID, dealerId: UUID) async {
        if let data = try? JSONEncoder().encode(id) {
            let item = SyncQueueItem(entityType: entity, operation: .delete, payload: data, dealerId: dealerId)
            await SyncQueueManager.shared.enqueue(item: item)
        }
    }

    private func processUpsert(_ item: SyncQueueItem) async throws {
        let decoder = JSONDecoder()
        switch item.entityType {
        case .vehicle:
            let remote = try decoder.decode(RemoteVehicle.self, from: item.payload)
            try await writeClient.rpc("sync_vehicles", params: ["payload": [remote]]).execute()
        case .expense:
            let remote = try decoder.decode(RemoteExpense.self, from: item.payload)
            try await writeClient.rpc("sync_expenses", params: ["payload": [remote]]).execute()
        case .sale:
            let remote = try decoder.decode(RemoteSale.self, from: item.payload)
            try await writeClient.rpc("sync_sales", params: ["payload": [remote]]).execute()
        case .client:
            let remote = try decoder.decode(RemoteClient.self, from: item.payload)
            try await writeClient.rpc("sync_clients", params: ["payload": [remote]]).execute()
        case .user:
            let remote = try decoder.decode(RemoteDealerUser.self, from: item.payload)
            try await writeClient.rpc("sync_users", params: ["payload": [remote]]).execute()
        case .account:
             let remote = try decoder.decode(RemoteFinancialAccount.self, from: item.payload)
             try await writeClient.rpc("sync_accounts", params: ["payload": [remote]]).execute()
        case .accountTransaction:
            let remote = try decoder.decode(RemoteAccountTransaction.self, from: item.payload)
            try await writeClient.rpc("sync_account_transactions", params: ["payload": [remote]]).execute()
        case .template:
             let remote = try decoder.decode(RemoteExpenseTemplate.self, from: item.payload)
             try await writeClient.rpc("sync_templates", params: ["payload": [remote]]).execute()
        case .debt:
            let remote = try decoder.decode(RemoteDebt.self, from: item.payload)
            try await writeClient.rpc("sync_debts", params: ["payload": [remote]]).execute()
        case .debtPayment:
            let remote = try decoder.decode(RemoteDebtPayment.self, from: item.payload)
            try await writeClient.rpc("sync_debt_payments", params: ["payload": [remote]]).execute()
        }
    }

    private func processDelete(_ item: SyncQueueItem) async throws {
        let decoder = JSONDecoder()
        let id = try decoder.decode(UUID.self, from: item.payload)
        try await deleteEntityById(id, dealerId: item.dealerId, entity: item.entityType)
    }

    func upsertVehicle(_ vehicle: Vehicle, dealerId: UUID) async {
        guard let remote = makeRemoteVehicle(from: vehicle, dealerId: dealerId) else { return }
        
        // Instant Sync
        Task {
            do {
                try await writeClient
                    .rpc("sync_vehicles", params: SyncPayload<RemoteVehicle>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertVehicle error: \(error)")
                await logSyncError(
                    rpc: "sync_vehicles",
                    dealerId: dealerId,
                    entityType: .vehicle,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .vehicle, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteVehicle(_ vehicle: Vehicle, dealerId: UUID) async {
        // Soft delete: Update local object, then sync
        vehicle.deletedAt = Date()
        vehicle.updatedAt = Date()
        // We need to save context? The caller usually saves.
        
        guard let remote = makeRemoteVehicle(from: vehicle, dealerId: dealerId) else { return }
        
        do {
            try await writeClient
                .rpc("sync_vehicles", params: SyncPayload<RemoteVehicle>(payload: [remote]))
                .execute()
            
            // If success, we can delete locally or keep it as tombstone?
            // For now, we keep it until next full sync or just delete it now if we trust server?
            // The architecture says: "Physically delete records in Core Data that were successfully marked as deleted on the server"
            // So we can delete it now from Core Data.
            // But we are in a Task, need context.
            // Let's just let the sync loop handle physical deletion, or do it here if we have context.
            // For now, just send to server.
            
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            print("CloudSyncManager deleteVehicle error: \(error)")
            await logSyncError(
                rpc: "sync_vehicles",
                dealerId: dealerId,
                entityType: .vehicle,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .vehicle, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }
    
    // Helper to delete by ID is removed/deprecated in favor of object-based soft delete
    func deleteVehicle(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .vehicle)
        } catch {
            print("CloudSyncManager deleteVehicle(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_vehicles",
                dealerId: dealerId,
                entityType: .vehicle,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.vehicle, id: id, dealerId: dealerId)
        }
    }

    func upsertExpense(_ expense: Expense, dealerId: UUID) async {
        guard let remote = makeRemoteExpense(from: expense, dealerId: dealerId) else { return }
        
        Task {
            do {
                try await writeClient
                    .rpc("sync_expenses", params: SyncPayload<RemoteExpense>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertExpense error: \(error)")
                await logSyncError(
                    rpc: "sync_expenses",
                    dealerId: dealerId,
                    entityType: .expense,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .expense, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteTemplate(_ template: ExpenseTemplate, dealerId: UUID) async {
        template.deletedAt = Date()
        template.updatedAt = Date()
        guard let remote = makeRemoteTemplate(from: template, dealerId: dealerId) else { return }
        
        do {
            try await writeClient
                .rpc("sync_templates", params: SyncPayload<RemoteExpenseTemplate>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_templates",
                dealerId: dealerId,
                entityType: .template,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .template, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }
    
    func deleteExpense(_ expense: Expense, dealerId: UUID) async {
        expense.deletedAt = Date()
        expense.updatedAt = Date()
        guard let remote = makeRemoteExpense(from: expense, dealerId: dealerId) else { return }
        
        do {
            try await writeClient
                .rpc("sync_expenses", params: SyncPayload<RemoteExpense>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_expenses",
                dealerId: dealerId,
                entityType: .expense,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .expense, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }
    
    func deleteExpense(id: UUID, dealerId: UUID) async {
         do {
             try await deleteEntityById(id, dealerId: dealerId, entity: .expense)
         } catch {
             print("CloudSyncManager deleteExpense(id:) error: \(error)")
             await logSyncError(
                 rpc: "delete_crm_expenses",
                 dealerId: dealerId,
                 entityType: .expense,
                 payloadId: id,
                 error: error
             )
             showError("Deleted locally. Will sync when online.")
             await enqueueDelete(.expense, id: id, dealerId: dealerId)
         }
    }

    func upsertSale(_ sale: Sale, dealerId: UUID) async {
        guard let remote = makeRemoteSale(from: sale, dealerId: dealerId) else { return }
        
        Task {
            do {
                try await writeClient
                    .rpc("sync_sales", params: SyncPayload<RemoteSale>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertSale error: \(error)")
                await logSyncError(
                    rpc: "sync_sales",
                    dealerId: dealerId,
                    entityType: .sale,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .sale, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteSale(_ sale: Sale, dealerId: UUID) async {
        sale.deletedAt = Date()
        sale.updatedAt = Date()
        guard let remote = makeRemoteSale(from: sale, dealerId: dealerId) else { return }
        
        do {
            try await writeClient
                .rpc("sync_sales", params: SyncPayload<RemoteSale>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_sales",
                dealerId: dealerId,
                entityType: .sale,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .sale, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }
    
    func deleteSale(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .sale)
        } catch {
            print("CloudSyncManager deleteSale(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_sales",
                dealerId: dealerId,
                entityType: .sale,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.sale, id: id, dealerId: dealerId)
        }
    }

    func upsertDebt(_ debt: Debt, dealerId: UUID) async {
        guard let remote = makeRemoteDebt(from: debt, dealerId: dealerId) else { return }

        Task {
            do {
                try await writeClient
                    .rpc("sync_debts", params: SyncPayload<RemoteDebt>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertDebt error: \(error)")
                await logSyncError(
                    rpc: "sync_debts",
                    dealerId: dealerId,
                    entityType: .debt,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .debt, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteDebt(_ debt: Debt, dealerId: UUID) async {
        debt.deletedAt = Date()
        debt.updatedAt = Date()
        guard let remote = makeRemoteDebt(from: debt, dealerId: dealerId) else { return }

        do {
            try await writeClient
                .rpc("sync_debts", params: SyncPayload<RemoteDebt>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_debts",
                dealerId: dealerId,
                entityType: .debt,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .debt, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }

    func deleteDebt(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .debt)
        } catch {
            print("CloudSyncManager deleteDebt(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_debts",
                dealerId: dealerId,
                entityType: .debt,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.debt, id: id, dealerId: dealerId)
        }
    }

    func upsertDebtPayment(_ payment: DebtPayment, dealerId: UUID) async {
        guard let remote = makeRemoteDebtPayment(from: payment, dealerId: dealerId) else { return }

        Task {
            do {
                try await writeClient
                    .rpc("sync_debt_payments", params: SyncPayload<RemoteDebtPayment>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertDebtPayment error: \(error)")
                await logSyncError(
                    rpc: "sync_debt_payments",
                    dealerId: dealerId,
                    entityType: .debtPayment,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .debtPayment, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteDebtPayment(_ payment: DebtPayment, dealerId: UUID) async {
        payment.deletedAt = Date()
        payment.updatedAt = Date()
        guard let remote = makeRemoteDebtPayment(from: payment, dealerId: dealerId) else { return }

        do {
            try await writeClient
                .rpc("sync_debt_payments", params: SyncPayload<RemoteDebtPayment>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_debt_payments",
                dealerId: dealerId,
                entityType: .debtPayment,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .debtPayment, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }

    func deleteDebtPayment(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .debtPayment)
        } catch {
            print("CloudSyncManager deleteDebtPayment(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_debt_payments",
                dealerId: dealerId,
                entityType: .debtPayment,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.debtPayment, id: id, dealerId: dealerId)
        }
    }

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func upsertUser(_ user: User, dealerId: UUID) async {
        guard let id = user.id else { return }
        let now = Date()
        let createdAt = user.createdAt ?? now
        let updatedAt = user.updatedAt ?? now
        let deletedAt = user.deletedAt
        
        let remote = RemoteDealerUser(
            id: id,
            dealerId: dealerId,
            name: user.name ?? "",
            createdAt: iso8601Formatter.string(from: createdAt),
            updatedAt: iso8601Formatter.string(from: updatedAt),
            deletedAt: deletedAt.map { iso8601Formatter.string(from: $0) }
        )
        
        Task {
            do {
                try await writeClient
                    .rpc("sync_users", params: SyncPayload<RemoteDealerUser>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertUser error: \(error)")
                await logSyncError(
                    rpc: "sync_users",
                    dealerId: dealerId,
                    entityType: .user,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .user, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteUser(_ user: User, dealerId: UUID) async {
        user.deletedAt = Date()
        user.updatedAt = Date()
        guard let id = user.id else { return }
        
        let createdAt = user.createdAt ?? Date()
        let updatedAt = user.updatedAt ?? Date()
        let deletedAt = user.deletedAt

        let remote = RemoteDealerUser(
            id: id,
            dealerId: dealerId,
            name: user.name ?? "",
            createdAt: iso8601Formatter.string(from: createdAt),
            updatedAt: iso8601Formatter.string(from: updatedAt),
            deletedAt: deletedAt.map { iso8601Formatter.string(from: $0) }
        )
        
        do {
            try await writeClient
                .rpc("sync_users", params: SyncPayload<RemoteDealerUser>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_users",
                dealerId: dealerId,
                entityType: .user,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .user, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }

    func deleteUser(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .user)
        } catch {
            print("CloudSyncManager deleteUser(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_dealer_users",
                dealerId: dealerId,
                entityType: .user,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.user, id: id, dealerId: dealerId)
        }
    }

    func upsertClient(_ clientObject: Client, dealerId: UUID) async {
        guard let remote = makeRemoteClient(from: clientObject, dealerId: dealerId) else { return }
        
        Task {
            do {
                try await writeClient
                    .rpc("sync_clients", params: SyncPayload<RemoteClient>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertClient error: \(error)")
                await logSyncError(
                    rpc: "sync_clients",
                    dealerId: dealerId,
                    entityType: .client,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .client, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteFinancialAccount(_ account: FinancialAccount, dealerId: UUID) async {
        account.deletedAt = Date()
        account.updatedAt = Date()
        guard let remote = makeRemoteFinancialAccount(from: account, dealerId: dealerId) else { return }
        
        do {
            try await writeClient
                .rpc("sync_accounts", params: SyncPayload<RemoteFinancialAccount>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_accounts",
                dealerId: dealerId,
                entityType: .account,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .account, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }

    func upsertFinancialAccount(_ account: FinancialAccount, dealerId: UUID) async {
        guard let remote = makeRemoteFinancialAccount(from: account, dealerId: dealerId) else { return }
        
        Task {
            do {
                try await writeClient
                    .rpc("sync_accounts", params: SyncPayload<RemoteFinancialAccount>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertFinancialAccount error: \(error)")
                await logSyncError(
                    rpc: "sync_accounts",
                    dealerId: dealerId,
                    entityType: .account,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .account, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func upsertAccountTransaction(_ transaction: AccountTransaction, dealerId: UUID) async {
        guard let remote = makeRemoteAccountTransaction(from: transaction, dealerId: dealerId) else { return }

        Task {
            do {
                try await writeClient
                    .rpc("sync_account_transactions", params: SyncPayload<RemoteAccountTransaction>(payload: [remote]))
                    .execute()
                await processOfflineQueue(dealerId: dealerId)
            } catch {
                print("CloudSyncManager upsertAccountTransaction error: \(error)")
                await logSyncError(
                    rpc: "sync_account_transactions",
                    dealerId: dealerId,
                    entityType: .accountTransaction,
                    payloadId: remote.id,
                    error: error
                )
                showError(savedLocallySyncFailureMessage(for: error))
                if let data = try? JSONEncoder().encode(remote) {
                    let item = SyncQueueItem(entityType: .accountTransaction, operation: .upsert, payload: data, dealerId: dealerId)
                    await SyncQueueManager.shared.enqueue(item: item)
                }
            }
        }
    }

    func deleteAccountTransaction(_ transaction: AccountTransaction, dealerId: UUID) async {
        transaction.deletedAt = Date()
        transaction.updatedAt = Date()
        guard let remote = makeRemoteAccountTransaction(from: transaction, dealerId: dealerId) else { return }

        do {
            try await writeClient
                .rpc("sync_account_transactions", params: SyncPayload<RemoteAccountTransaction>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_account_transactions",
                dealerId: dealerId,
                entityType: .accountTransaction,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .accountTransaction, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }

    func deleteAccountTransaction(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .accountTransaction)
        } catch {
            print("CloudSyncManager deleteAccountTransaction(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_account_transactions",
                dealerId: dealerId,
                entityType: .accountTransaction,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.accountTransaction, id: id, dealerId: dealerId)
        }
    }

    func deleteClient(_ clientObject: Client, dealerId: UUID) async {
        clientObject.deletedAt = Date()
        clientObject.updatedAt = Date()
        guard let remote = makeRemoteClient(from: clientObject, dealerId: dealerId) else { return }
        
        do {
            try await writeClient
                .rpc("sync_clients", params: SyncPayload<RemoteClient>(payload: [remote]))
                .execute()
            await processOfflineQueue(dealerId: dealerId)
        } catch {
            await logSyncError(
                rpc: "sync_clients",
                dealerId: dealerId,
                entityType: .client,
                payloadId: remote.id,
                extraContext: ["operation": "delete"],
                error: error
            )
            if let data = try? JSONEncoder().encode(remote) {
                let item = SyncQueueItem(entityType: .client, operation: .upsert, payload: data, dealerId: dealerId)
                await SyncQueueManager.shared.enqueue(item: item)
            }
        }
    }
    
    func deleteClient(id: UUID, dealerId: UUID) async {
        do {
            try await deleteEntityById(id, dealerId: dealerId, entity: .client)
        } catch {
            print("CloudSyncManager deleteClient(id:) error: \(error)")
            await logSyncError(
                rpc: "delete_crm_dealer_clients",
                dealerId: dealerId,
                entityType: .client,
                payloadId: id,
                error: error
            )
            showError("Deleted locally. Will sync when online.")
            await enqueueDelete(.client, id: id, dealerId: dealerId)
        }
    }

    // MARK: - Vehicle images

    private func imagePath(dealerId: UUID, vehicleId: UUID) -> String {
        "\(dealerId.uuidString.lowercased())/vehicles/\(vehicleId.uuidString.lowercased()).jpg"
    }

    func uploadVehicleImage(vehicleId: UUID, dealerId: UUID, imageData: Data) async {
        let path = imagePath(dealerId: dealerId, vehicleId: vehicleId)
        print("CloudSyncManager uploadVehicleImage: Starting upload to path: \(path)")
        print("CloudSyncManager uploadVehicleImage: Image data size: \(imageData.count) bytes")
        do {
            let result = try await client.storage
                .from("vehicle-images")
                .upload(
                    path,
                    data: imageData,
                    options: FileOptions(
                        cacheControl: "0",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
            print("CloudSyncManager uploadVehicleImage: SUCCESS! Result: \(result)")
        } catch {
            print("CloudSyncManager uploadVehicleImage: ERROR: \(error)")
            print("CloudSyncManager uploadVehicleImage: Error localizedDescription: \(error.localizedDescription)")
        }
    }

    func deleteVehicleImage(vehicleId: UUID, dealerId: UUID) async {
        do {
            let path = imagePath(dealerId: dealerId, vehicleId: vehicleId)
            _ = try await client.storage
                .from("vehicle-images")
                .remove(paths: [path])
        } catch {
            print("CloudSyncManager deleteVehicleImage error: \(error)")
        }
    }

    private func downloadVehicleImages(dealerId: UUID, vehicles: [RemoteVehicle]) async {
        print("CloudSyncManager: Starting to download images for \(vehicles.count) vehicles")
        for vehicle in vehicles {
            let path = imagePath(dealerId: dealerId, vehicleId: vehicle.id)
            do {
                print("CloudSyncManager: Downloading image from path: \(path)")
                let data = try await client.storage
                    .from("vehicle-images")
                    .download(path: path)
                print("CloudSyncManager: Downloaded image for \(vehicle.id) - \(data.count) bytes")
                ImageStore.shared.save(imageData: data, for: vehicle.id)
            } catch {
                // It's fine if an image does not exist for a vehicle.
                print("CloudSyncManager: No image for vehicle \(vehicle.id) at path \(path)")
            }
        }
        print("CloudSyncManager: Finished downloading images")
    }

    // MARK: - Backups

    func uploadBackupArchive(at url: URL, dealerId: UUID) async {
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            let path = "\(dealerId.uuidString)/backups/\(filename)"
            try await client.storage
                .from("dealer-backups")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: "0",
                        contentType: "application/zip",
                        upsert: true
                    )
                )
            await MainActor.run {
                self.syncHUDState = .success
                self.scheduleHideHUD(for: .success)
                self.lastSyncAt = Date()
            }
        } catch {
            print("CloudSyncManager uploadBackupArchive error: \(error)")
            showError("Backup upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Snapshot fetch & apply

    private func fetchRemoteChanges(dealerId: UUID, since: Date?) async throws -> RemoteSnapshot {
        // Pull a small time window before the last sync to survive clock drift between devices
        let driftBuffer: TimeInterval = 5 * 60 // 5 minutes
        let effectiveSince: Date? = since.map { $0.addingTimeInterval(-driftBuffer) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let sinceString = effectiveSince.map { formatter.string(from: $0) }
        
        // Use the get_changes RPC
        let params: [String: AnyJSON] = [
            "dealer_id": .string(dealerId.uuidString),
            "since": sinceString != nil ? .string(sinceString!) : .string("1970-01-01T00:00:00Z")
        ]
        
        do {
            let snapshot: RemoteSnapshot = try await client
                .rpc("get_changes", params: params)
                .execute()
                .value
            return snapshot
        } catch {
            await logSyncError(rpc: "get_changes", dealerId: dealerId, error: error)
            throw error
        }
    }

    private func filterSnapshot(_ snapshot: RemoteSnapshot, skippingIds: [SyncEntityType: Set<UUID>]) -> RemoteSnapshot {
        // With get_changes, we get exactly what we need. 
        // We might still want to filter out things we just deleted locally to avoid resurrection if the server hasn't processed the delete yet?
        // But if we use LWW and we just deleted locally (updatedAt = now), and server sends us old data (updatedAt < now), we will ignore it in merge.
        // So explicit filtering is less critical if merge logic is robust.
        // However, keeping it doesn't hurt.
        
        guard !skippingIds.isEmpty else { return snapshot }
        
        let vehicleIds = skippingIds[.vehicle] ?? []
        let expenseIds = skippingIds[.expense] ?? []
        let saleIds = skippingIds[.sale] ?? []
        let debtIds = skippingIds[.debt] ?? []
        let debtPaymentIds = skippingIds[.debtPayment] ?? []
        let clientIds = skippingIds[.client] ?? []
        let userIds = skippingIds[.user] ?? []
        let accountIds = skippingIds[.account] ?? []
        let accountTransactionIds = skippingIds[.accountTransaction] ?? []
        let templateIds = skippingIds[.template] ?? []

        let filteredVehicles = snapshot.vehicles.filter { !vehicleIds.contains($0.id) }
        
        // Filter expenses: skip if expense itself is deleted OR if its vehicle is deleted
        let filteredExpenses = snapshot.expenses.filter { expense in
            if expenseIds.contains(expense.id) { return false }
            if let vId = expense.vehicleId, vehicleIds.contains(vId) { return false }
            return true
        }
        
        // Filter sales: skip if sale itself is deleted OR if its vehicle is deleted
        let filteredSales = snapshot.sales.filter { sale in
            if saleIds.contains(sale.id) { return false }
            if vehicleIds.contains(sale.vehicleId) { return false } // vehicleId is non-optional for Sale
            return true
        }
        
        // Filter clients: skip if client itself is deleted OR if its vehicle is deleted
        let filteredClients = snapshot.clients.filter { client in
            if clientIds.contains(client.id) { return false }
            if let vId = client.vehicleId, vehicleIds.contains(vId) { return false }
            return true
        }

        let filteredDebts = snapshot.debts.filter { !debtIds.contains($0.id) }

        let filteredDebtPayments = snapshot.debtPayments.filter { payment in
            if debtPaymentIds.contains(payment.id) { return false }
            if debtIds.contains(payment.debtId) { return false }
            return true
        }
        
        let filteredUsers = snapshot.users.filter { !userIds.contains($0.id) }
        let filteredAccounts = snapshot.accounts.filter { !accountIds.contains($0.id) }
        let filteredAccountTransactions = snapshot.accountTransactions.filter { tx in
            if accountTransactionIds.contains(tx.id) { return false }
            if accountIds.contains(tx.accountId) { return false }
            return true
        }
        let filteredTemplates = snapshot.templates.filter { !templateIds.contains($0.id) }

        return RemoteSnapshot(
            users: filteredUsers,
            accounts: filteredAccounts,
            accountTransactions: filteredAccountTransactions,
            vehicles: filteredVehicles,
            templates: filteredTemplates,
            expenses: filteredExpenses,
            sales: filteredSales,
            debts: filteredDebts,
            debtPayments: filteredDebtPayments,
            clients: filteredClients
        )
    }

    // Ensure that each dealer has at least a couple of basic accounts so that
    // the Add Expense screen never shows an empty list.
    // Note: existingAccounts contains accounts from get_changes for this dealer.
    // We only create defaults if none exist remotely.
    nonisolated private func ensureDefaultAccounts(context _: NSManagedObjectContext, for dealerId: UUID, existingAccounts: [RemoteFinancialAccount], writeClient: SupabaseClient) async -> [RemoteFinancialAccount] {
        // Check if we already have Cash or Bank accounts (including deleted ones to avoid recreating)
        let hasCash = existingAccounts.contains { $0.accountType.lowercased() == "cash" }
        let hasBank = existingAccounts.contains { $0.accountType.lowercased() == "bank" }

        // If accounts already exist remotely, return them (don't create duplicates)
        if hasCash && hasBank {
            return existingAccounts.filter { $0.deletedAt == nil }
        }

        var newAccounts: [RemoteFinancialAccount] = []
        let now = Date()

        if !hasCash {
            newAccounts.append(RemoteFinancialAccount(
                id: UUID(),
                dealerId: dealerId,
                accountType: "Cash",
                balance: 0,
                updatedAt: now,
                deletedAt: nil
            ))
        }

        if !hasBank {
            newAccounts.append(RemoteFinancialAccount(
                id: UUID(),
                dealerId: dealerId,
                accountType: "Bank",
                balance: 0,
                updatedAt: now,
                deletedAt: nil
            ))
        }

        guard !newAccounts.isEmpty else { return existingAccounts.filter { $0.deletedAt == nil } }

        do {
            // Use sync_accounts which now handles duplicate type detection
            try await writeClient
                .rpc("sync_accounts", params: SyncPayload<RemoteFinancialAccount>(payload: newAccounts))
                .execute()
        } catch {
            // If insert fails due to constraint, the accounts already exist
            // The sync_accounts RPC now handles this gracefully
            print("CloudSyncManager ensureDefaultAccounts insert error: \(error)")
        }

        // Return both new and existing non-deleted accounts
        return existingAccounts.filter { $0.deletedAt == nil } + newAccounts
    }

    // MARK: - Merge Logic
    
    private struct MissingCleanupContext {
        let syncStartedAt: Date
        let remoteIds: [SyncEntityType: Set<UUID>]
        let protectedIds: [SyncEntityType: Set<UUID>]
    }
    
    nonisolated private func mergeRemoteChanges(
        _ snapshot: RemoteSnapshot,
        context: NSManagedObjectContext,
        dealerId: UUID,
        missingCleanup: MissingCleanupContext? = nil
    ) throws {
        // Helpers for fetching existing objects
        func fetchExisting<T: NSManagedObject>(entityName: String, ids: [UUID]) -> [UUID: T] {
            let request = NSFetchRequest<T>(entityName: entityName)
            request.predicate = NSPredicate(format: "id IN %@", ids)
            do {
                let results = try context.fetch(request)
                var map: [UUID: T] = [:]
                for obj in results {
                    if let id = obj.value(forKey: "id") as? UUID {
                        map[id] = obj
                    }
                }
                return map
            } catch {
                print("Error fetching existing \(entityName): \(error)")
                return [:]
            }
        }

        // 1. Users
        let userIds = snapshot.users.map { $0.id }
        let existingUsers: [UUID: User] = fetchExisting(entityName: "User", ids: userIds)
        
        func findLocalUserByName(_ name: String) -> User? {
            let request: NSFetchRequest<User> = User.fetchRequest()
            request.predicate = NSPredicate(format: "name ==[c] %@", name)
            return (try? context.fetch(request))?.first
        }

        for u in snapshot.users {
            var obj = existingUsers[u.id]
            
            if obj == nil {
                if let duplicate = findLocalUserByName(u.name) {
                    print("Found local duplicate user for \(u.name). Merging...")
                    obj = duplicate
                    obj?.id = u.id
                } else {
                    obj = User(context: context)
                }
            }
            
            guard let user = obj else { continue }
            
            if u.deletedAt != nil {
                context.delete(user)
                continue
            }
            
            // LWW Check
            if let parsedUpdated = CloudSyncManager.parseDateAndTime(u.updatedAt),
               let localUpdated = user.updatedAt, localUpdated > parsedUpdated {
                continue // Local is newer, ignore remote
            }
            
            user.id = u.id
            user.name = u.name
            user.createdAt = CloudSyncManager.parseDateAndTime(u.createdAt)
            user.updatedAt = CloudSyncManager.parseDateAndTime(u.updatedAt)
            user.deletedAt = nil
            user.deletedAt = nil
        }

        // 2. Accounts
        let accountIds = snapshot.accounts.map { $0.id }
        let existingAccounts: [UUID: FinancialAccount] = fetchExisting(entityName: "FinancialAccount", ids: accountIds)
        
        // Helper to find ALL local duplicates by type
        func findLocalAccountsByType(_ type: String) -> [FinancialAccount] {
            let request: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()
            request.predicate = NSPredicate(format: "accountType ==[c] %@", type)
            return (try? context.fetch(request)) ?? []
        }

        for a in snapshot.accounts {
            var obj = existingAccounts[a.id]
            
            // If not found by ID, check for duplicates by type
            if obj == nil {
                let duplicates = findLocalAccountsByType(a.accountType)
                if !duplicates.isEmpty {
                    print("Found \(duplicates.count) local duplicate accounts for \(a.accountType). Merging...")
                    
                    // Pick the best one to keep (e.g. has balance, or newest)
                    // Prioritize keeping one with non-zero balance
                    let bestMatch = duplicates.sorted { (a, b) in
                        let aHasBalance = abs(a.balance?.decimalValue ?? 0) > 0
                        let bHasBalance = abs(b.balance?.decimalValue ?? 0) > 0
                        if aHasBalance != bHasBalance {
                            return aHasBalance
                        }
                        return (a.updatedAt ?? Date.distantPast) > (b.updatedAt ?? Date.distantPast)
                    }.first
                    
                    if let match = bestMatch {
                        obj = match
                        obj?.id = a.id // Adopt remote ID
                        
                        // DELETE the others to prevent push errors
                        for dup in duplicates where dup != match {
                            print("Deleting extra local duplicate account: \(dup.accountType ?? "Unknown")")
                            context.delete(dup)
                        }
                    }
                } else {
                    obj = FinancialAccount(context: context)
                }
            }
            
            guard let account = obj else { continue }
            
            if a.deletedAt != nil {
                context.delete(account)
                continue
            }
            
            if let localUpdated = account.updatedAt, localUpdated > a.updatedAt {
                continue
            }
            
            account.id = a.id
            account.accountType = a.accountType
            account.balance = NSDecimalNumber(decimal: a.balance)
            account.updatedAt = a.updatedAt
            account.deletedAt = nil
        }

        // 3. Vehicles
        let vehicleIds = snapshot.vehicles.map { $0.id }
        let existingVehicles: [UUID: Vehicle] = fetchExisting(entityName: "Vehicle", ids: vehicleIds)

        for v in snapshot.vehicles {
            let obj = existingVehicles[v.id] ?? Vehicle(context: context)

            if v.deletedAt != nil {
                context.delete(obj)
                continue
            }
            
            // LWW Check
            if let localUpdated = obj.updatedAt, localUpdated > v.updatedAt {
                continue // Local is newer, ignore remote
            }

            obj.id = v.id
            obj.vin = v.vin
            obj.make = v.make
            obj.model = v.model
            obj.year = v.year != nil ? Int32(v.year!) : 0
            obj.purchasePrice = NSDecimalNumber(decimal: v.purchasePrice)

            if let d = CloudSyncManager.parseRemoteDateOnly(v.purchaseDate) {
                obj.purchaseDate = d
            } else {
                obj.purchaseDate = v.createdAt
            }

            obj.status = v.status
            obj.notes = v.notes
            obj.createdAt = v.createdAt
            obj.updatedAt = v.updatedAt
            obj.deletedAt = nil

            if let sp = v.salePrice {
                obj.salePrice = NSDecimalNumber(decimal: sp)
            }

            if let sd = v.saleDate {
                obj.saleDate = CloudSyncManager.parseDateAndTime(sd) ?? CloudSyncManager.parseDateOnly(sd)
            }

            // photoURL is handled separately via image download
            
            if let ap = v.askingPrice {
                obj.askingPrice = NSDecimalNumber(decimal: ap)
            }
            obj.reportURL = v.reportURL
        }

        // 4. Clients
            let clientIds = snapshot.clients.map { $0.id }
            let existingClients: [UUID: Client] = fetchExisting(entityName: "Client", ids: clientIds)
            for c in snapshot.clients {
                let obj = existingClients[c.id] ?? Client(context: context)
                
                if c.deletedAt != nil {
                    context.delete(obj)
                    continue
                }
                
                if let localUpdated = obj.updatedAt, localUpdated > c.updatedAt {
                    continue
                }
                
                obj.id = c.id
                obj.name = c.name
                obj.phone = c.phone
                obj.email = c.email
                obj.notes = c.notes
                obj.requestDetails = c.requestDetails
                obj.preferredDate = c.preferredDate
                obj.createdAt = c.createdAt
                obj.updatedAt = c.updatedAt
                obj.deletedAt = nil
                obj.status = c.status
            }

            // 5. Templates
            let templateIds = snapshot.templates.map { $0.id }
            let existingTemplates: [UUID: ExpenseTemplate] = fetchExisting(entityName: "ExpenseTemplate", ids: templateIds)
            for t in snapshot.templates {
                let obj = existingTemplates[t.id] ?? ExpenseTemplate(context: context)
                
                if t.deletedAt != nil {
                    context.delete(obj)
                    continue
                }
                
                if let localUpdated = obj.updatedAt, localUpdated > t.updatedAt {
                    continue
                }
                
                obj.id = t.id
                obj.name = t.name

                obj.category = t.category
                if let d = t.defaultAmount { obj.defaultAmount = NSDecimalNumber(decimal: d) }
                obj.defaultDescription = t.defaultDescription
                obj.updatedAt = t.updatedAt
                obj.deletedAt = nil
            }

            // 6. Expenses
            let expenseIds = snapshot.expenses.map { $0.id }
            let existingExpenses: [UUID: Expense] = fetchExisting(entityName: "Expense", ids: expenseIds)
            for e in snapshot.expenses {
                let obj = existingExpenses[e.id] ?? Expense(context: context)
                
                if e.deletedAt != nil {
                    context.delete(obj)
                    continue
                }
                
                if let localUpdated = obj.updatedAt, localUpdated > e.updatedAt {
                    continue
                }
                
                obj.id = e.id
                obj.amount = NSDecimalNumber(decimal: e.amount)
                
                if let d = CloudSyncManager.parseRemoteDateOnly(e.date) {
                    obj.date = d
                } else {
                    obj.date = e.createdAt
                }
                
                obj.expenseDescription = e.expenseDescription
                obj.category = e.category
                obj.createdAt = e.createdAt
                obj.updatedAt = e.updatedAt
                obj.deletedAt = nil
            }

            // 7. Sales
            let saleIds = snapshot.sales.map { $0.id }
            let existingSales: [UUID: Sale] = fetchExisting(entityName: "Sale", ids: saleIds)
            for s in snapshot.sales {
                let obj = existingSales[s.id] ?? Sale(context: context)
                
                if s.deletedAt != nil {
                    context.delete(obj)
                    continue
                }
                
                if let localUpdated = obj.updatedAt, localUpdated > s.updatedAt {
                    continue
                }
                
                obj.id = s.id
                obj.amount = NSDecimalNumber(decimal: s.amount)
                
                if let d = CloudSyncManager.parseDateAndTime(s.date) ?? CloudSyncManager.parseDateOnly(s.date) {
                    obj.date = d
                } else {
                    obj.date = s.createdAt
                }
                
                obj.buyerName = s.buyerName
                obj.buyerPhone = s.buyerPhone
                obj.paymentMethod = s.paymentMethod
                obj.createdAt = s.createdAt
                obj.updatedAt = s.updatedAt
                obj.deletedAt = nil
            }

            // 8. Account Transactions
            let accountTransactionIds = snapshot.accountTransactions.map { $0.id }
            let existingAccountTransactions: [UUID: AccountTransaction] = fetchExisting(entityName: "AccountTransaction", ids: accountTransactionIds)
            for t in snapshot.accountTransactions {
                let obj = existingAccountTransactions[t.id] ?? AccountTransaction(context: context)

                if t.deletedAt != nil {
                    context.delete(obj)
                    continue
                }

                if let localUpdated = obj.updatedAt, localUpdated > t.updatedAt {
                    continue
                }

                obj.id = t.id
                obj.transactionType = t.transactionType
                obj.amount = NSDecimalNumber(decimal: t.amount)
                if let parsed = CloudSyncManager.parseDateAndTime(t.date) ?? CloudSyncManager.parseRemoteDateOnly(t.date) {
                    obj.date = parsed
                } else {
                    obj.date = t.createdAt
                }
                obj.note = t.note
                obj.createdAt = t.createdAt
                obj.updatedAt = t.updatedAt
                obj.deletedAt = nil
            }

            // 9. Debts
            let debtIds = snapshot.debts.map { $0.id }
            let existingDebts: [UUID: Debt] = fetchExisting(entityName: "Debt", ids: debtIds)
            for d in snapshot.debts {
                let obj = existingDebts[d.id] ?? Debt(context: context)

                if d.deletedAt != nil {
                    context.delete(obj)
                    continue
                }

                if let localUpdated = obj.updatedAt, localUpdated > d.updatedAt {
                    continue
                }

                obj.id = d.id
                obj.counterpartyName = d.counterpartyName
                obj.counterpartyPhone = d.counterpartyPhone
                obj.direction = d.direction
                obj.amount = NSDecimalNumber(decimal: d.amount)
                obj.notes = d.notes
                if let due = d.dueDate {
                    obj.dueDate = CloudSyncManager.parseRemoteDateOnly(due)
                } else {
                    obj.dueDate = nil
                }
                obj.createdAt = d.createdAt
                obj.updatedAt = d.updatedAt
                obj.deletedAt = nil
            }

            // 10. Debt Payments
            // Build debt map first so we can link the required relationship immediately
            let allDebtIdsForPayments = Set(snapshot.debts.map { $0.id } + snapshot.debtPayments.map { $0.debtId })
            let debtMapForPayments: [UUID: Debt] = fetchExisting(entityName: "Debt", ids: Array(allDebtIdsForPayments))
            
            let debtPaymentIds = snapshot.debtPayments.map { $0.id }
            let existingDebtPayments: [UUID: DebtPayment] = fetchExisting(entityName: "DebtPayment", ids: debtPaymentIds)
            for p in snapshot.debtPayments {
                // Skip if the required debt doesn't exist locally
                guard let debt = debtMapForPayments[p.debtId] else {
                    print("Skipping DebtPayment \(p.id) - debt \(p.debtId) not found")
                    continue
                }
                
                let obj = existingDebtPayments[p.id] ?? DebtPayment(context: context)

                if p.deletedAt != nil {
                    context.delete(obj)
                    continue
                }

                if let localUpdated = obj.updatedAt, localUpdated > p.updatedAt {
                    continue
                }

                obj.id = p.id
                obj.amount = NSDecimalNumber(decimal: p.amount)
                if let parsed = CloudSyncManager.parseDateAndTime(p.date) ?? CloudSyncManager.parseRemoteDateOnly(p.date) {
                    obj.date = parsed
                } else {
                    obj.date = p.createdAt
                }
                obj.note = p.note
                obj.paymentMethod = p.paymentMethod
                obj.createdAt = p.createdAt
                obj.updatedAt = p.updatedAt
                obj.deletedAt = nil
                
                // Link required relationship immediately (before save)
                obj.debt = debt
            }

            // Save first pass (objects created/updated)
            if context.hasChanges {
                try context.save()
            }

            // Second pass: Relationships
            // We need to fetch everything again or use the maps if we kept them updated.
            // For simplicity, let's re-fetch or use the maps we built (but we need to add new ones to maps).
            // Actually, since we are in the same context block, we can just fetch relationships by ID.
            
            // Re-fetch maps to include newly created objects
            let allVehicles: [UUID: Vehicle] = fetchExisting(entityName: "Vehicle", ids: snapshot.vehicles.map { $0.id } + snapshot.clients.compactMap { $0.vehicleId } + snapshot.sales.map { $0.vehicleId } + snapshot.expenses.compactMap { $0.vehicleId })
            let allUsers: [UUID: User] = fetchExisting(entityName: "User", ids: snapshot.users.map { $0.id } + snapshot.expenses.compactMap { $0.userId })
            let allAccounts: [UUID: FinancialAccount] = fetchExisting(entityName: "FinancialAccount", ids: snapshot.accounts.map { $0.id } + snapshot.expenses.compactMap { $0.accountId } + snapshot.debtPayments.compactMap { $0.accountId } + snapshot.accountTransactions.map { $0.accountId } + snapshot.sales.compactMap { $0.accountId })
            let allDebts: [UUID: Debt] = fetchExisting(entityName: "Debt", ids: snapshot.debts.map { $0.id } + snapshot.debtPayments.map { $0.debtId })
            
            // Link Clients -> Vehicles
            for c in snapshot.clients {
                if let vId = c.vehicleId, let client = existingClients[c.id] ?? (try? context.fetch(Client.fetchRequest()).first(where: { $0.id == c.id })) {
                    client.vehicle = allVehicles[vId]
                }
            }
            
            // Link Expenses -> Vehicle, User, Account
            for e in snapshot.expenses {
                 if let expense = existingExpenses[e.id] ?? (try? context.fetch(Expense.fetchRequest()).first(where: { $0.id == e.id })) {
                     if let vId = e.vehicleId { expense.vehicle = allVehicles[vId] }
                     if let uId = e.userId { expense.user = allUsers[uId] }
                     if let aId = e.accountId { expense.account = allAccounts[aId] }
                 }
            }
            
            // Link Sales -> Vehicle
            for s in snapshot.sales {
                if let sale = existingSales[s.id] ?? (try? context.fetch(Sale.fetchRequest()).first(where: { $0.id == s.id })) {
                    if let v = allVehicles[s.vehicleId] {
                        sale.vehicle = v
                    }
                    if let aId = s.accountId {
                        sale.account = allAccounts[aId]
                    } else {
                        sale.account = nil
                    }
                }
            }

            // Link Account Transactions -> Account
            for t in snapshot.accountTransactions {
                if let transaction = existingAccountTransactions[t.id] ?? (try? context.fetch(AccountTransaction.fetchRequest()).first(where: { $0.id == t.id })) {
                    transaction.account = allAccounts[t.accountId]
                }
            }

            // Link Debt Payments -> Debt, Account
            for p in snapshot.debtPayments {
                if let payment = existingDebtPayments[p.id] ?? (try? context.fetch(DebtPayment.fetchRequest()).first(where: { $0.id == p.id })) {
                    payment.debt = allDebts[p.debtId]
                    if let aId = p.accountId {
                        payment.account = allAccounts[aId]
                    }
                }
            }

            // Remove local objects that are not present remotely after a full refresh.
            // Runs only when mergeRemoteChanges is invoked with missingCleanup (force manual sync),
            // and skips any record that has pending queue items to avoid wiping offline creations.
            if let cleanup = missingCleanup {
                func cleanupEntity(entityName: String, type: SyncEntityType) {
                    let remoteIds = cleanup.remoteIds[type] ?? []
                    let protectedIds = cleanup.protectedIds[type] ?? []
                    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    guard let locals = try? context.fetch(request) else { return }
                    
                    for obj in locals {
                        guard let id = obj.value(forKey: "id") as? UUID else { continue }
                        if remoteIds.contains(id) { continue }
                        if protectedIds.contains(id) { continue }
                        
                        let localUpdated = (obj.value(forKey: "updatedAt") as? Date)
                            ?? (obj.value(forKey: "createdAt") as? Date)
                            ?? .distantPast
                        
                        if localUpdated <= cleanup.syncStartedAt {
                            context.delete(obj)
                        }
                    }
                }
                
                cleanupEntity(entityName: "Vehicle", type: .vehicle)
                cleanupEntity(entityName: "Expense", type: .expense)
                cleanupEntity(entityName: "Sale", type: .sale)
                cleanupEntity(entityName: "AccountTransaction", type: .accountTransaction)
                cleanupEntity(entityName: "Debt", type: .debt)
                cleanupEntity(entityName: "DebtPayment", type: .debtPayment)
                cleanupEntity(entityName: "Client", type: .client)
                cleanupEntity(entityName: "User", type: .user)
                cleanupEntity(entityName: "FinancialAccount", type: .account)
                cleanupEntity(entityName: "ExpenseTemplate", type: .template)
            }

            if context.hasChanges {
                try context.save()
            }
        }

    // MARK: - Mapping helpers

    nonisolated private static func parseDateOnly(_ string: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // Use current timezone so date-only strings align with local day boundaries
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }

    /// Interpret a remote date-only/timestamp string as a floating local day.
    /// - Date-only strings are parsed in the current timezone.
    /// - Timestamp strings are normalized to the same UTC day, then rebuilt at local midnight.
    nonisolated private static func parseRemoteDateOnly(_ string: String) -> Date? {
        if let localDate = parseDateOnly(string) {
            return localDate
        }
        if let dateTime = parseDateAndTime(string) {
            return normalizeDateOnly(dateTime)
        }
        return nil
    }

    nonisolated private static func normalizeDateOnly(_ date: Date) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone.current
        return localCalendar.date(from: components) ?? date
    }
    
    /// Formats a date as YYYY-MM-DD in local timezone (matches parseDateOnly)
    nonisolated private static func formatDateOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    struct SyncPayload<T: Encodable>: Encodable {
        let payload: [T]
    }

    // Push local Core Data state to Supabase so we don't lose offline changes when applying a remote snapshot.
    nonisolated private func pushLocalChanges(context: NSManagedObjectContext, dealerId: UUID, writeClient: SupabaseClient, skippingVehicleIds: Set<UUID> = []) async throws {
        let payload = try await context.perform { [self] () throws -> (users: [RemoteDealerUser], accounts: [RemoteFinancialAccount], accountTransactions: [RemoteAccountTransaction], vehicles: [RemoteVehicle], expenses: [RemoteExpense], sales: [RemoteSale], debts: [RemoteDebt], debtPayments: [RemoteDebtPayment], clients: [RemoteClient], templates: [RemoteExpenseTemplate]) in
            // Fetch current local objects
            let userRequest: NSFetchRequest<User> = User.fetchRequest()
            let accountRequest: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()
            let accountTransactionRequest: NSFetchRequest<AccountTransaction> = AccountTransaction.fetchRequest()
            let vehicleRequest: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
            let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
            let saleRequest: NSFetchRequest<Sale> = Sale.fetchRequest()
            let debtRequest: NSFetchRequest<Debt> = Debt.fetchRequest()
            let debtPaymentRequest: NSFetchRequest<DebtPayment> = DebtPayment.fetchRequest()
            let clientRequest: NSFetchRequest<Client> = Client.fetchRequest()
            let templateRequest: NSFetchRequest<ExpenseTemplate> = ExpenseTemplate.fetchRequest()

            let users = try context.fetch(userRequest)
            let accounts = try context.fetch(accountRequest)
            let accountTransactions = try context.fetch(accountTransactionRequest)
            let vehicles = try context
                .fetch(vehicleRequest)
                .filter { vehicle in
                    guard let id = vehicle.id else { return true }
                    return !skippingVehicleIds.contains(id)
                }
            let expenses = try context
                .fetch(expenseRequest)
                .filter { expense in
                    guard let vId = expense.vehicle?.id else { return true }
                    return !skippingVehicleIds.contains(vId)
                }
            let sales = try context
                .fetch(saleRequest)
                .filter { sale in
                    guard let vId = sale.vehicle?.id else { return true }
                    return !skippingVehicleIds.contains(vId)
                }
            let debts = try context.fetch(debtRequest)
            let debtPayments = try context.fetch(debtPaymentRequest)
            let clients = try context
                .fetch(clientRequest)
                .filter { client in
                    guard let vId = client.vehicle?.id else { return true }
                    return !skippingVehicleIds.contains(vId)
                }
            let templates = try context.fetch(templateRequest)

            // Map to remote models
            let remoteUsers: [RemoteDealerUser] = users.compactMap { user -> RemoteDealerUser? in
                guard let id = user.id else { return nil }
                return RemoteDealerUser(
                    id: id,
                    dealerId: dealerId,
                    name: user.name ?? "",
                    createdAt: CloudSyncManager.formatDateAndTime(user.createdAt ?? Date()),
                    updatedAt: CloudSyncManager.formatDateAndTime(user.updatedAt ?? Date()),
                    deletedAt: user.deletedAt.map { CloudSyncManager.formatDateAndTime($0) }
                )
            }

            // Deduplicate accounts by type (case-insensitive) before pushing
            // Keep only one account per type - prefer the one with balance, then newest
            var accountsByType: [String: FinancialAccount] = [:]
            for account in accounts {
                let normalizedType = (account.accountType ?? "").lowercased()
                if let existing = accountsByType[normalizedType] {
                    // Compare to decide which to keep
                    let existingBalance = abs(existing.balance?.decimalValue ?? 0)
                    let newBalance = abs(account.balance?.decimalValue ?? 0)
                    if newBalance > existingBalance ||
                       (newBalance == existingBalance && (account.updatedAt ?? .distantPast) > (existing.updatedAt ?? .distantPast)) {
                        accountsByType[normalizedType] = account
                    }
                } else {
                    accountsByType[normalizedType] = account
                }
            }

            let remoteAccounts: [RemoteFinancialAccount] = accountsByType.values.compactMap { account in
                self.makeRemoteFinancialAccount(from: account, dealerId: dealerId)
            }

            let remoteAccountTransactions: [RemoteAccountTransaction] = accountTransactions.compactMap { transaction in
                self.makeRemoteAccountTransaction(from: transaction, dealerId: dealerId)
            }

            let remoteVehicles: [RemoteVehicle] = vehicles.compactMap { vehicle in
                self.makeRemoteVehicle(from: vehicle, dealerId: dealerId)
            }

            let remoteExpenses: [RemoteExpense] = expenses.compactMap { expense in
                self.makeRemoteExpense(from: expense, dealerId: dealerId)
            }

            let remoteSales: [RemoteSale] = sales.compactMap { sale in
                self.makeRemoteSale(from: sale, dealerId: dealerId)
            }

            let remoteDebts: [RemoteDebt] = debts.compactMap { debt in
                self.makeRemoteDebt(from: debt, dealerId: dealerId)
            }

            let remoteDebtPayments: [RemoteDebtPayment] = debtPayments.compactMap { payment in
                self.makeRemoteDebtPayment(from: payment, dealerId: dealerId)
            }

            let remoteClients: [RemoteClient] = clients.compactMap { client in
                self.makeRemoteClient(from: client, dealerId: dealerId)
            }

            let remoteTemplates: [RemoteExpenseTemplate] = templates.compactMap { template in
                self.makeRemoteTemplate(from: template, dealerId: dealerId)
            }

            return (
                users: remoteUsers,
                accounts: remoteAccounts,
                accountTransactions: remoteAccountTransactions,
                vehicles: remoteVehicles,
                expenses: remoteExpenses,
                sales: remoteSales,
                debts: remoteDebts,
                debtPayments: remoteDebtPayments,
                clients: remoteClients,
                templates: remoteTemplates
            )
        }

        // Push to Supabase. If any of these throws, we fail the sync rather than wiping local data.
        // Push to Supabase using RPCs to handle upserts on views
        if !payload.users.isEmpty {
            try await writeClient
                .rpc("sync_users", params: SyncPayload<RemoteDealerUser>(payload: payload.users))
                .execute()
        }

        if !payload.accounts.isEmpty {
            try await writeClient
                .rpc("sync_accounts", params: SyncPayload<RemoteFinancialAccount>(payload: payload.accounts))
                .execute()
        }

        if !payload.accountTransactions.isEmpty {
            try await writeClient
                .rpc("sync_account_transactions", params: SyncPayload<RemoteAccountTransaction>(payload: payload.accountTransactions))
                .execute()
        }

        if !payload.vehicles.isEmpty {
            try await writeClient
                .rpc("sync_vehicles", params: SyncPayload<RemoteVehicle>(payload: payload.vehicles))
                .execute()
        }

        if !payload.expenses.isEmpty {
            try await writeClient
                .rpc("sync_expenses", params: SyncPayload<RemoteExpense>(payload: payload.expenses))
                .execute()
        }

        if !payload.sales.isEmpty {
            try await writeClient
                .rpc("sync_sales", params: SyncPayload<RemoteSale>(payload: payload.sales))
                .execute()
        }

        if !payload.debts.isEmpty {
            try await writeClient
                .rpc("sync_debts", params: SyncPayload<RemoteDebt>(payload: payload.debts))
                .execute()
        }

        if !payload.debtPayments.isEmpty {
            try await writeClient
                .rpc("sync_debt_payments", params: SyncPayload<RemoteDebtPayment>(payload: payload.debtPayments))
                .execute()
        }

        if !payload.clients.isEmpty {
            try await writeClient
                .rpc("sync_clients", params: SyncPayload<RemoteClient>(payload: payload.clients))
                .execute()
        }

        if !payload.templates.isEmpty {
            try await writeClient
                .rpc("sync_templates", params: SyncPayload<RemoteExpenseTemplate>(payload: payload.templates))
                .execute()
        }
    }

    nonisolated private func makeRemoteFinancialAccount(from account: FinancialAccount, dealerId: UUID) -> RemoteFinancialAccount? {
        guard let id = account.id else { return nil }
        let balanceDecimal = account.balance?.decimalValue ?? 0
        let updatedAt = account.updatedAt ?? Date()
        let type = account.accountType ?? "Account"
        return RemoteFinancialAccount(
            id: id,
            dealerId: dealerId,
            accountType: type,
            balance: balanceDecimal,
            updatedAt: updatedAt,
            deletedAt: account.deletedAt
        )
    }

    nonisolated private func makeRemoteAccountTransaction(from transaction: AccountTransaction, dealerId: UUID) -> RemoteAccountTransaction? {
        guard let id = transaction.id, let accountId = transaction.account?.id else { return nil }
        return RemoteAccountTransaction(
            id: id,
            dealerId: dealerId,
            accountId: accountId,
            transactionType: transaction.transactionType ?? AccountTransactionType.deposit.rawValue,
            amount: transaction.amount?.decimalValue ?? 0,
            date: CloudSyncManager.formatDateAndTime(transaction.date ?? Date()),
            note: transaction.note,
            createdAt: transaction.createdAt ?? Date(),
            updatedAt: transaction.updatedAt ?? Date(),
            deletedAt: transaction.deletedAt
        )
    }

    nonisolated private func makeRemoteTemplate(from template: ExpenseTemplate, dealerId: UUID) -> RemoteExpenseTemplate? {
        guard let id = template.id else { return nil }
        let name = template.name ?? "Template"
        let category = template.category ?? ""
        let defaultAmount = template.defaultAmount?.decimalValue
        return RemoteExpenseTemplate(
            id: id,
            dealerId: dealerId,
            name: name,
            category: category,
            defaultDescription: template.defaultDescription,
            defaultAmount: defaultAmount,
            updatedAt: template.updatedAt ?? Date(),
            deletedAt: template.deletedAt
        )
    }



    nonisolated private static func formatDateAndTime(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    nonisolated private static func parseDateAndTime(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: string) { return date }
        
        // Fallback for standard ISO8601 without fractional seconds
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }

    nonisolated private func makeRemoteVehicle(from vehicle: Vehicle, dealerId: UUID) -> RemoteVehicle? {
        guard let id = vehicle.id else { return nil }
        let year = vehicle.year == 0 ? nil : Int(vehicle.year)
        let purchaseDate = Calendar.current.startOfDay(for: vehicle.purchaseDate ?? Date())

        // For now we don't persist photo URL locally. Cloud image is derived from dealer & vehicle ids.
        return RemoteVehicle(
            id: id,
            dealerId: dealerId,
            vin: vehicle.vin ?? "",
            make: vehicle.make,
            model: vehicle.model,
            year: year,
            purchasePrice: (vehicle.purchasePrice as Decimal?) ?? 0,
            purchaseDate: CloudSyncManager.formatDateOnly(purchaseDate), // Use date only for purchase_date
            status: vehicle.status ?? "on_sale",
            notes: vehicle.notes,
            createdAt: vehicle.createdAt ?? Date(),
            salePrice: vehicle.salePrice as Decimal?,
            saleDate: vehicle.saleDate.map { CloudSyncManager.formatDateAndTime($0) },
            photoURL: nil,
            askingPrice: vehicle.askingPrice as Decimal?,
            reportURL: vehicle.reportURL,
            updatedAt: vehicle.updatedAt ?? Date(),
            deletedAt: vehicle.deletedAt
        )
    }

    nonisolated private func makeRemoteExpense(from expense: Expense, dealerId: UUID) -> RemoteExpense? {
        guard let id = expense.id else { return nil }
        let date = Calendar.current.startOfDay(for: expense.date ?? Date())
        return RemoteExpense(
            id: id,
            dealerId: dealerId,
            amount: (expense.amount as Decimal?) ?? 0,
            date: CloudSyncManager.formatDateOnly(date),
            expenseDescription: expense.expenseDescription,
            category: expense.category ?? "",
            createdAt: expense.createdAt ?? Date(),
            vehicleId: (expense.vehicle?.id),
            userId: (expense.user?.id),
            accountId: (expense.account?.id),
            updatedAt: expense.updatedAt ?? Date(),
            deletedAt: expense.deletedAt
        )
    }

    nonisolated private func makeRemoteSale(from sale: Sale, dealerId: UUID) -> RemoteSale? {
        guard
            let id = sale.id,
            let vehicle = sale.vehicle,
            let vehicleId = vehicle.id
        else { return nil }

        let date = sale.date ?? Date()
        return RemoteSale(
            id: id,
            dealerId: dealerId,
            vehicleId: vehicleId,
            amount: (sale.amount as Decimal?) ?? 0,
            salePrice: (sale.amount as Decimal?) ?? 0,
            profit: nil,
            date: CloudSyncManager.formatDateAndTime(date),
            buyerName: sale.buyerName,
            buyerPhone: sale.buyerPhone,
            paymentMethod: sale.paymentMethod,
            accountId: sale.account?.id,
            notes: nil,
            createdAt: Date(),
            updatedAt: sale.updatedAt ?? Date(),
            deletedAt: sale.deletedAt
        )
    }

    nonisolated private func makeRemoteDebt(from debt: Debt, dealerId: UUID) -> RemoteDebt? {
        guard let id = debt.id else { return nil }
        return RemoteDebt(
            id: id,
            dealerId: dealerId,
            counterpartyName: debt.counterpartyName ?? "",
            counterpartyPhone: debt.counterpartyPhone,
            direction: debt.direction ?? DebtDirection.owedToMe.rawValue,
            amount: debt.amount?.decimalValue ?? 0,
            notes: debt.notes,
            dueDate: debt.dueDate.map { CloudSyncManager.formatDateOnly($0) },
            createdAt: debt.createdAt ?? Date(),
            updatedAt: debt.updatedAt ?? Date(),
            deletedAt: debt.deletedAt
        )
    }

    nonisolated private func makeRemoteDebtPayment(from payment: DebtPayment, dealerId: UUID) -> RemoteDebtPayment? {
        guard let id = payment.id, let debtId = payment.debt?.id else { return nil }
        return RemoteDebtPayment(
            id: id,
            dealerId: dealerId,
            debtId: debtId,
            amount: payment.amount?.decimalValue ?? 0,
            date: CloudSyncManager.formatDateAndTime(payment.date ?? Date()),
            note: payment.note,
            paymentMethod: payment.paymentMethod,
            accountId: payment.account?.id,
            createdAt: payment.createdAt ?? Date(),
            updatedAt: payment.updatedAt ?? Date(),
            deletedAt: payment.deletedAt
        )
    }

    nonisolated private func makeRemoteClient(from client: Client, dealerId: UUID) -> RemoteClient? {
        guard let id = client.id else { return nil }
        return RemoteClient(
            id: id,
            dealerId: dealerId,
            name: client.name ?? "",
            phone: client.phone,
            email: client.email,
            notes: client.notes,
            requestDetails: client.requestDetails,
            preferredDate: client.preferredDate,
            createdAt: client.createdAt ?? Date(),
            status: client.status ?? "new",
            vehicleId: client.vehicle?.id,
            updatedAt: client.updatedAt ?? Date(),
            deletedAt: client.deletedAt
        )
    }
    // MARK: - Deduplication

    func deduplicateData(dealerId: UUID) async throws {
        do {
            // 1. Deduplicate Vehicles by VIN
            // Fetch all vehicles for this dealer
            let vehicles: [RemoteVehicle] = try await client
                .from("crm_vehicles")
                .select()
                .eq("dealer_id", value: dealerId)
                .execute()
                .value
            
            // Group by VIN
            let groupedVehicles = Dictionary(grouping: vehicles, by: { $0.vin })
            
            for (vin, group) in groupedVehicles {
                if group.count > 1 {
                    // Keep the most recently created one
                    let sorted = group.sorted { $0.createdAt > $1.createdAt }
                    let toDelete = sorted.dropFirst()
                    
                    for v in toDelete {
                        print("Deleting duplicate vehicle VIN: \(vin), ID: \(v.id)")
                        do {
                            try await writeClient
                                .rpc("delete_crm_vehicles", params: ["p_id": v.id, "p_dealer_id": dealerId])
                                .execute()
                        } catch {
                            print("Failed to delete duplicate vehicle \(v.id): \(error)")
                        }
                    }
                }
            }
            
            // 2. Deduplicate Clients by Phone
            let clients: [RemoteClient] = try await client
                .from("crm_dealer_clients")
                .select()
                .eq("dealer_id", value: dealerId)
                .execute()
                .value
            
            let groupedClients = Dictionary(grouping: clients, by: { $0.phone })
            
            for (phone, group) in groupedClients {
                if group.count > 1 {
                    let sorted = group.sorted { $0.createdAt > $1.createdAt }
                    let toDelete = sorted.dropFirst()
                    
                    for c in toDelete {
                        let phoneLabel = phone ?? "nil"
                        print("Deleting duplicate client Phone: \(phoneLabel), ID: \(c.id)")
                        do {
                            try await writeClient
                                .rpc("delete_crm_dealer_clients", params: ["p_id": c.id, "p_dealer_id": dealerId])
                                .execute()
                        } catch {
                            print("Failed to delete duplicate client \(c.id): \(error)")
                        }
                    }
                }
            }
            
            // 3. Deduplicate Financial Accounts by name/type (case/whitespace insensitive)
            let accounts: [RemoteFinancialAccount] = try await client
                .from("crm_financial_accounts")
                .select()
                .eq("dealer_id", value: dealerId)
                .execute()
                .value
            
            let groupedAccounts = Dictionary(grouping: accounts, by: { $0.accountType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            
            for (normalizedType, group) in groupedAccounts {
                if normalizedType.isEmpty { continue }
                if group.count > 1 {
                    // Keep the one with non-zero balance if possible, then most recent
                    let sorted = group.sorted { (a, b) in
                        let aHasBalance = abs(a.balance) > 0
                        let bHasBalance = abs(b.balance) > 0
                        if aHasBalance != bHasBalance {
                            return aHasBalance // Keep the one with balance
                        }
                        return a.updatedAt > b.updatedAt // Otherwise keep newest
                    }
                    let toDelete = sorted.dropFirst()
                    
                    for acc in toDelete {
                        print("Deleting duplicate account: \(acc.accountType), ID: \(acc.id)")
                        do {
                            try await writeClient
                                .rpc("delete_crm_financial_accounts", params: ["p_id": acc.id, "p_dealer_id": dealerId])
                                .execute()
                        } catch {
                            print("Failed to delete duplicate account \(acc.id): \(error)")
                        }
                    }
                }
            }
            
            // 3. Deduplicate Users by name (case/whitespace insensitive)
            let users: [RemoteDealerUser] = try await client
                .from("crm_dealer_users")
                .select()
                .eq("dealer_id", value: dealerId)
                .execute()
                .value
            
            let groupedUsers = Dictionary(grouping: users, by: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            
            for (normalizedName, group) in groupedUsers {
                if normalizedName.isEmpty { continue }
                if group.count > 1 {
                    let sorted = group.sorted { $0.createdAt > $1.createdAt }
                    let toDelete = sorted.dropFirst()
                    
                    for u in toDelete {
                        print("Deleting duplicate user Name: \(u.name), ID: \(u.id)")
                        do {
                            try await writeClient
                                .rpc("delete_crm_dealer_users", params: ["p_id": u.id, "p_dealer_id": dealerId])
                                .execute()
                        } catch {
                            print("Failed to delete duplicate user \(u.id): \(error)")
                        }
                    }
                }
            }
            
            // Refresh local cache after remote deletes
            let snapshot = try await fetchRemoteChanges(dealerId: dealerId, since: nil)
            try mergeRemoteChanges(snapshot, context: context, dealerId: dealerId)
        } catch {
            print("Deduplication error: \(error)")
            throw error
        }
    }

    // MARK: - Account Deletion Helper
    
    func deleteAllRemoteData(dealerId: UUID) async throws {
        // Delete in reverse order of dependencies to avoid FK constraints if cascades aren't set
        // Dependencies:
        // Expenses -> Vehicles, Accounts, Users
        // Sales -> Vehicles
        // Clients -> Vehicles
        // Vehicles -> Dealer
        // Accounts -> Dealer
        // Templates -> Dealer
        // DealerUsers -> Dealer
        
        // 1. Expenses
        try await writeClient.from("crm_expenses").delete().eq("dealer_id", value: dealerId).execute()

        // 1.5. Debt Payments
        try await writeClient.from("crm_debt_payments").delete().eq("dealer_id", value: dealerId).execute()
        
        // 2. Sales
        try await writeClient.from("crm_sales").delete().eq("dealer_id", value: dealerId).execute()

        // 2.5. Debts
        try await writeClient.from("crm_debts").delete().eq("dealer_id", value: dealerId).execute()
        
        // 3. Clients
        try await writeClient.from("crm_dealer_clients").delete().eq("dealer_id", value: dealerId).execute()
        
        // 4. Vehicles
        try await writeClient.from("crm_vehicles").delete().eq("dealer_id", value: dealerId).execute()
        
        // 5. Templates
        try await writeClient.from("crm_expense_templates").delete().eq("dealer_id", value: dealerId).execute()

        // 6. Account Transactions
        try await writeClient.from("crm_account_transactions").delete().eq("dealer_id", value: dealerId).execute()

        // 7. Financial Accounts
        try await writeClient.from("crm_financial_accounts").delete().eq("dealer_id", value: dealerId).execute()

        // 8. Dealer Users (The user profile itself in public table)
        try await writeClient.from("crm_dealer_users").delete().eq("dealer_id", value: dealerId).execute()
    }
}

// MARK: - Sync Queue Manager

enum SyncOperationType: String, Codable, CaseIterable, Hashable {
    case upsert
    case delete
}

enum SyncEntityType: String, Codable, CaseIterable, Hashable {
    case vehicle
    case expense
    case sale
    case debt
    case debtPayment
    case client
    case user
    case account
    case accountTransaction
    case template
}

extension SyncOperationType {
    var displayName: String {
        switch self {
        case .upsert: return "Upsert"
        case .delete: return "Delete"
        }
    }

    var sortOrder: Int {
        switch self {
        case .upsert: return 0
        case .delete: return 1
        }
    }
}

extension SyncEntityType {
    var displayName: String {
        switch self {
        case .vehicle: return "Vehicles"
        case .expense: return "Expenses"
        case .sale: return "Sales"
        case .debt: return "Debts"
        case .debtPayment: return "Debt Payments"
        case .client: return "Clients"
        case .user: return "Users"
        case .account: return "Accounts"
        case .accountTransaction: return "Account Transactions"
        case .template: return "Expense Templates"
        }
    }

    var sortOrder: Int {
        switch self {
        case .vehicle: return 0
        case .expense: return 1
        case .sale: return 2
        case .debt: return 3
        case .debtPayment: return 4
        case .client: return 5
        case .user: return 6
        case .account: return 7
        case .accountTransaction: return 8
        case .template: return 9
        }
    }
}

struct SyncQueueSummaryItem: Identifiable {
    let id = UUID()
    let entity: SyncEntityType
    let operation: SyncOperationType
    let count: Int
}

private struct SyncQueueGroupKey: Hashable {
    let entity: SyncEntityType
    let operation: SyncOperationType
}

struct SyncEntityCount: Identifiable {
    let id = UUID()
    let entity: SyncEntityType
    let localCount: Int
    let remoteCount: Int?

    var delta: Int? {
        guard let remoteCount else { return nil }
        return remoteCount - localCount
    }
}

struct SyncDiagnosticsReport: Identifiable {
    let id = UUID()
    let generatedAt: Date
    let lastSyncAt: Date?
    let isSyncing: Bool
    let offlineQueueCount: Int
    let offlineQueueSummary: [SyncQueueSummaryItem]
    let entityCounts: [SyncEntityCount]
    let remoteFetchError: String?
}

struct SyncQueueItem: Codable, Identifiable {
    let id: UUID
    let entityType: SyncEntityType
    let operation: SyncOperationType
    let payload: Data // JSON data of the entity
    let dealerId: UUID
    var retryCount: Int
    let createdAt: Date
    
    init(id: UUID = UUID(), entityType: SyncEntityType, operation: SyncOperationType, payload: Data, dealerId: UUID) {
        self.id = id
        self.entityType = entityType
        self.operation = operation
        self.payload = payload
        self.dealerId = dealerId
        self.retryCount = 0
        self.createdAt = Date()
    }
}

actor SyncQueueManager {
    static let shared = SyncQueueManager()
    
    private let queueFileName = "sync_queue.json"
    private var items: [SyncQueueItem] = []
    
    init() {
        Task {
            await loadQueue()
        }
    }
    
    private var queueFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(queueFileName)
    }
    
    private func loadQueue() async {
        guard let url = queueFileURL, let data = try? Data(contentsOf: url) else { return }
        if let loaded = try? JSONDecoder().decode([SyncQueueItem].self, from: data) {
            self.items = loaded
        }
    }
    
    private func saveQueue() {
        guard let url = queueFileURL else { return }
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url)
        }
    }
    
    func enqueue(item: SyncQueueItem) {
        items.append(item)
        saveQueue()
    }
    
    func dequeue() -> SyncQueueItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        saveQueue()
        return item
    }
    
    func peek() -> SyncQueueItem? {
        items.first
    }
    
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        saveQueue()
    }
    
    func getAllItems() -> [SyncQueueItem] {
        items
    }
    
    func clear() {
        items.removeAll()
        saveQueue()
    }
    
    func itemCount() -> Int {
        items.count
    }
}
