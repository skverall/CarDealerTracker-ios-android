import CoreData
import PDFKit
import RevenueCat
import Supabase
import XCTest
@testable import Ezcar24Business

@MainActor
final class Ezcar24BusinessRegressionTests: XCTestCase {
    private var persistenceController: PersistenceController!
    private var context: NSManagedObjectContext!
    private var temporaryURLs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        CloudSyncManager.clearAllSyncTimestamps()
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.viewContext
        ImageStore.shared.setActiveDealerId(nil)
    }

    override func tearDownWithError() throws {
        CloudSyncManager.clearAllSyncTimestamps()
        ImageStore.shared.setActiveDealerId(nil)
        SubscriptionManager.shared.logOut()
        temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryURLs.removeAll()
        context = nil
        persistenceController = nil
        try super.tearDownWithError()
    }

    func testEmailReminderBannerShowsWithoutConfirmationSignals() {
        XCTAssertTrue(
            SessionStore.shouldShowEmailReminderBanner(
                emailConfirmedAt: nil,
                confirmedAt: nil,
                metadata: [:]
            )
        )
    }

    func testEmailReminderBannerHidesForISO8601ConfirmationString() {
        XCTAssertFalse(
            SessionStore.shouldShowEmailReminderBanner(
                emailConfirmedAt: nil,
                confirmedAt: nil,
                metadata: ["email_confirmed_at": "2026-03-07T02:30:00Z"]
            )
        )
    }

    func testEmailReminderBannerHidesForEpochConfirmationString() {
        XCTAssertFalse(
            SessionStore.shouldShowEmailReminderBanner(
                emailConfirmedAt: nil,
                confirmedAt: nil,
                metadata: ["email_confirmed_at": "1741314600"]
            )
        )
    }

    func testImageStoreUsesLatestDealerNamespaceImmediately() {
        let previousDealerId = UUID()
        let currentDealerId = UUID()
        let vehicleId = UUID()
        let photoId = UUID()

        ImageStore.shared.setActiveDealerId(previousDealerId)
        ImageStore.shared.setActiveDealerId(currentDealerId)

        let imageURL = ImageStore.shared.imageURL(for: vehicleId)
        let photoURL = ImageStore.shared.photoURL(vehicleId: vehicleId, photoId: photoId)

        XCTAssertTrue(imageURL.path.contains(currentDealerId.uuidString))
        XCTAssertFalse(imageURL.path.contains(previousDealerId.uuidString))
        XCTAssertTrue(photoURL.path.contains(currentDealerId.uuidString))
        XCTAssertFalse(photoURL.path.contains(previousDealerId.uuidString))
    }

    func testHostedTestsSkipRevenueCatBootstrap() async {
        let manager = await prepareSubscriptionManager()

        manager.fetchOfferings()
        await drainMainQueue()

        XCTAssertFalse(Purchases.isConfigured)
        XCTAssertNil(manager.currentOffering)
        XCTAssertNil(manager.errorMessage)
        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(manager.isCheckingStatus)
    }

    func testSubscriptionManagerKeepsBonusFallbackWithoutRevenueCatConfiguration() async {
        let manager = await prepareSubscriptionManager()
        let bonusUntil = Date().addingTimeInterval(3_600)

        manager.updateReferralBonus(until: bonusUntil, months: 2)
        await drainMainQueue()

        XCTAssertTrue(manager.isProAccessActive)
        XCTAssertNotNil(manager.bonusAccessUntil)
        XCTAssertEqual(manager.bonusAccessUntil?.timeIntervalSince1970 ?? 0, bonusUntil.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(manager.bonusMonths, 2)

        manager.restorePurchases()

        XCTAssertEqual(manager.restoreStatus, .noPurchases)
        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(manager.isRestoring)
        XCTAssertTrue(manager.isProAccessActive)
    }

    func testExpenseDateSortUsesCreationTimeForSameDayRecords() throws {
        let businessDate = Date(timeIntervalSince1970: 1_741_305_600)
        let earlierCreatedAt = businessDate.addingTimeInterval(43_680)
        let laterCreatedAt = businessDate.addingTimeInterval(53_280)
        let vehicle = makeVehicle(
            make: "Sort",
            model: "Check",
            status: "owned",
            purchasePrice: 10_000,
            purchaseDate: businessDate.addingTimeInterval(-86_400)
        )
        let earlierExpense = makeExpense(
            description: "Earlier",
            amount: 120,
            date: businessDate,
            vehicle: vehicle,
            updatedAt: earlierCreatedAt
        )
        earlierExpense.createdAt = earlierCreatedAt
        earlierExpense.updatedAt = earlierCreatedAt

        let laterExpense = makeExpense(
            description: "Later",
            amount: 20,
            date: businessDate,
            vehicle: vehicle,
            updatedAt: laterCreatedAt
        )
        laterExpense.createdAt = laterCreatedAt
        laterExpense.updatedAt = laterCreatedAt

        try context.save()

        let viewModel = ExpenseViewModel(context: context)
        viewModel.sortOption = .dateDesc
        viewModel.fetchExpenses()

        XCTAssertEqual(viewModel.expenses.count, 2)
        XCTAssertEqual(viewModel.expenses.first?.objectID, laterExpense.objectID)
        XCTAssertEqual(viewModel.expenses.last?.objectID, earlierExpense.objectID)
    }

    func testSyncQueueLoadsPersistedItemsOnFirstAccess() async throws {
        let queueURL = try makeTemporaryQueueURL()
        let dealerId = UUID()
        let item = SyncQueueItem(
            entityType: .vehicle,
            operation: .upsert,
            payload: Data("{}".utf8),
            dealerId: dealerId
        )

        let persisted = try JSONEncoder().encode([item])
        try persisted.write(to: queueURL, options: .atomic)

        let queue = SyncQueueManager(queueFileURL: queueURL)
        let loadedItems = await queue.getAllItems()

        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertEqual(loadedItems.first?.id, item.id)
        XCTAssertEqual(loadedItems.first?.dealerId, dealerId)
    }

    func testSyncQueueBacksOffFailuresAndDeadLettersPoisonItems() async throws {
        let queueURL = try makeTemporaryQueueURL()
        let dealerId = UUID()
        let item = SyncQueueItem(
            entityType: .expense,
            operation: .upsert,
            payload: Data("{}".utf8),
            dealerId: dealerId
        )
        let queue = SyncQueueManager(queueFileURL: queueURL)

        await queue.enqueue(item: item)
        let initialProcessableItems = await queue.processableItems(for: dealerId)
        XCTAssertEqual(initialProcessableItems.count, 1)

        let start = Date(timeIntervalSince1970: 1_741_400_000)
        let firstFailure = await queue.markFailure(id: item.id, errorDescription: "network", now: start)

        XCTAssertEqual(firstFailure?.retryCount, 1)
        XCTAssertNotNil(firstFailure?.nextAttemptAt)
        XCTAssertNil(firstFailure?.deadLetteredAt)
        let blockedItems = await queue.processableItems(for: dealerId, now: start.addingTimeInterval(29))
        XCTAssertTrue(blockedItems.isEmpty)
        let resumedItems = await queue.processableItems(for: dealerId, now: start.addingTimeInterval(31))
        XCTAssertEqual(resumedItems.count, 1)

        var lastFailure: SyncQueueItem? = firstFailure
        for attempt in 2...SyncQueueManager.maxRetryCount {
            lastFailure = await queue.markFailure(
                id: item.id,
                errorDescription: "network-\(attempt)",
                now: start.addingTimeInterval(TimeInterval(attempt * 600))
            )
        }

        XCTAssertEqual(lastFailure?.retryCount, SyncQueueManager.maxRetryCount)
        XCTAssertNil(lastFailure?.nextAttemptAt)
        XCTAssertNotNil(lastFailure?.deadLetteredAt)
        let deadLetteredItems = await queue.processableItems(for: dealerId, now: start.addingTimeInterval(86_400))
        XCTAssertTrue(deadLetteredItems.isEmpty)

        let reloadedQueue = SyncQueueManager(queueFileURL: queueURL)
        let reloadedItems = await reloadedQueue.getAllItems()
        let reloadedItem = reloadedItems.first
        XCTAssertEqual(reloadedItem?.retryCount, SyncQueueManager.maxRetryCount)
        XCTAssertNotNil(reloadedItem?.deadLetteredAt)
        XCTAssertEqual(reloadedItem?.lastErrorDescription, "network-\(SyncQueueManager.maxRetryCount)")
    }

    func testSyncQueueCompactsRepeatedUpsertsForSameRecord() async throws {
        let queueURL = try makeTemporaryQueueURL()
        let dealerId = UUID()
        let recordId = UUID()
        let first = SyncQueueItem(
            entityType: .vehicle,
            operation: .upsert,
            payload: Data("{\"version\":1}".utf8),
            dealerId: dealerId,
            recordId: recordId
        )
        let second = SyncQueueItem(
            entityType: .vehicle,
            operation: .upsert,
            payload: Data("{\"version\":2}".utf8),
            dealerId: dealerId,
            recordId: recordId
        )
        let queue = SyncQueueManager(queueFileURL: queueURL)

        await queue.enqueue(item: first)
        await queue.enqueue(item: second)

        let items = await queue.getAllItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, second.id)
        XCTAssertEqual(items.first?.recordId, recordId)
    }

    func testSyncQueueDeleteSupersedesQueuedUpsertForSameRecord() async throws {
        let queueURL = try makeTemporaryQueueURL()
        let dealerId = UUID()
        let recordId = UUID()
        let upsert = SyncQueueItem(
            entityType: .client,
            operation: .upsert,
            payload: Data("{\"state\":\"draft\"}".utf8),
            dealerId: dealerId,
            recordId: recordId
        )
        let delete = SyncQueueItem(
            entityType: .client,
            operation: .delete,
            payload: try JSONEncoder().encode(recordId),
            dealerId: dealerId,
            recordId: recordId
        )
        let queue = SyncQueueManager(queueFileURL: queueURL)

        await queue.enqueue(item: upsert)
        await queue.enqueue(item: delete)

        let items = await queue.getAllItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, delete.id)
        XCTAssertEqual(items.first?.operation, .delete)
        XCTAssertEqual(items.first?.recordId, recordId)
    }

    func testQueueSnapshotSeparatesReadyWaitingAndDeadLetters() {
        let dealerId = UUID()
        let now = Date(timeIntervalSince1970: 1_741_720_000)
        let ready = SyncQueueItem(
            entityType: .vehicle,
            operation: .upsert,
            payload: Data("{}".utf8),
            dealerId: dealerId,
            createdAt: now.addingTimeInterval(-900)
        )
        let waiting = SyncQueueItem(
            entityType: .expense,
            operation: .upsert,
            payload: Data("{}".utf8),
            dealerId: dealerId,
            createdAt: now.addingTimeInterval(-600),
            lastAttemptAt: now.addingTimeInterval(-60),
            nextAttemptAt: now.addingTimeInterval(180),
            lastErrorDescription: "retry later"
        )
        let deadLetter = SyncQueueItem(
            entityType: .sale,
            operation: .delete,
            payload: Data("{}".utf8),
            dealerId: dealerId,
            retryCount: SyncQueueManager.maxRetryCount,
            createdAt: now.addingTimeInterval(-300),
            lastAttemptAt: now.addingTimeInterval(-30),
            lastErrorDescription: "dead letter",
            deadLetteredAt: now.addingTimeInterval(-30)
        )

        let snapshot = CloudSyncManager.queueSnapshot(from: [waiting, deadLetter, ready], now: now)

        XCTAssertEqual(snapshot.totalCount, 3)
        XCTAssertEqual(snapshot.readyCount, 1)
        XCTAssertEqual(snapshot.waitingCount, 1)
        XCTAssertEqual(snapshot.deadLetterCount, 1)
        XCTAssertEqual(snapshot.oldestQueuedAt, ready.createdAt)
        XCTAssertEqual(snapshot.nextRetryAt, waiting.nextAttemptAt)
        XCTAssertEqual(snapshot.lastDeadLetterAt, deadLetter.deadLetteredAt)
    }

    func testDiagnosticsIssuePrefersNewestDeadLetterOverStoredFailure() {
        let storedAt = Date(timeIntervalSince1970: 1_741_700_000)
        let deadLetterAt = storedAt.addingTimeInterval(120)
        let queue = SyncQueueSnapshot(
            totalCount: 1,
            readyCount: 0,
            waitingCount: 0,
            deadLetterCount: 1,
            oldestQueuedAt: storedAt.addingTimeInterval(-300),
            nextRetryAt: nil,
            lastDeadLetterAt: deadLetterAt
        )

        let issue = CloudSyncManager.diagnosticsIssue(
            storedMessage: "Old sync error",
            storedAt: storedAt,
            queue: queue
        )

        XCTAssertEqual(issue?.message, "Offline queue has dead-letter items that need manual attention.")
        XCTAssertEqual(issue?.at, deadLetterAt)
    }

    func testDiagnosticsHealthStatusDistinguishesHealthyDegradedAndBlocked() {
        let lastSyncAt = Date(timeIntervalSince1970: 1_741_730_000)
        let healthyQueue = SyncQueueSnapshot(
            totalCount: 0,
            readyCount: 0,
            waitingCount: 0,
            deadLetterCount: 0,
            oldestQueuedAt: nil,
            nextRetryAt: nil,
            lastDeadLetterAt: nil
        )
        let degradedQueue = SyncQueueSnapshot(
            totalCount: 2,
            readyCount: 1,
            waitingCount: 1,
            deadLetterCount: 0,
            oldestQueuedAt: lastSyncAt.addingTimeInterval(-300),
            nextRetryAt: lastSyncAt.addingTimeInterval(60),
            lastDeadLetterAt: nil
        )
        let blockedQueue = SyncQueueSnapshot(
            totalCount: 1,
            readyCount: 0,
            waitingCount: 0,
            deadLetterCount: 1,
            oldestQueuedAt: lastSyncAt.addingTimeInterval(-600),
            nextRetryAt: nil,
            lastDeadLetterAt: lastSyncAt.addingTimeInterval(-30)
        )

        XCTAssertEqual(
            CloudSyncManager.diagnosticsHealthStatus(
                lastSyncAt: lastSyncAt,
                remoteFetchError: nil,
                issue: nil,
                queue: healthyQueue
            ),
            .healthy
        )
        XCTAssertEqual(
            CloudSyncManager.diagnosticsHealthStatus(
                lastSyncAt: lastSyncAt,
                remoteFetchError: nil,
                issue: nil,
                queue: degradedQueue
            ),
            .degraded
        )
        XCTAssertEqual(
            CloudSyncManager.diagnosticsHealthStatus(
                lastSyncAt: lastSyncAt,
                remoteFetchError: nil,
                issue: SyncDiagnosticsIssue(message: "blocked", at: lastSyncAt),
                queue: blockedQueue
            ),
            .blocked
        )
    }

    func testAutoSyncPolicyRequiresConnectedSignedInUnlockedState() {
        let now = Date(timeIntervalSince1970: 1_741_740_000)

        XCTAssertTrue(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: false,
                isSignedIn: true,
                isConnected: true,
                isSyncing: false,
                lastAutoSyncAt: nil,
                now: now,
                minimumInterval: 20
            )
        )
        XCTAssertFalse(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: true,
                showPasswordReset: false,
                isSignedIn: true,
                isConnected: true,
                isSyncing: false,
                lastAutoSyncAt: nil,
                now: now,
                minimumInterval: 20
            )
        )
        XCTAssertFalse(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: true,
                isSignedIn: true,
                isConnected: true,
                isSyncing: false,
                lastAutoSyncAt: nil,
                now: now,
                minimumInterval: 20
            )
        )
        XCTAssertFalse(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: false,
                isSignedIn: false,
                isConnected: true,
                isSyncing: false,
                lastAutoSyncAt: nil,
                now: now,
                minimumInterval: 20
            )
        )
        XCTAssertFalse(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: false,
                isSignedIn: true,
                isConnected: false,
                isSyncing: false,
                lastAutoSyncAt: nil,
                now: now,
                minimumInterval: 20
            )
        )
        XCTAssertFalse(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: false,
                isSignedIn: true,
                isConnected: true,
                isSyncing: true,
                lastAutoSyncAt: nil,
                now: now,
                minimumInterval: 20
            )
        )
    }

    func testAutoSyncPolicyThrottlesRapidRepeats() {
        let now = Date(timeIntervalSince1970: 1_741_740_000)
        let lastAutoSyncAt = now.addingTimeInterval(-10)

        XCTAssertFalse(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: false,
                isSignedIn: true,
                isConnected: true,
                isSyncing: false,
                lastAutoSyncAt: lastAutoSyncAt,
                now: now,
                minimumInterval: 20
            )
        )
        XCTAssertTrue(
            AuthGateView.shouldRunAutoSync(
                isGuestMode: false,
                showPasswordReset: false,
                isSignedIn: true,
                isConnected: true,
                isSyncing: false,
                lastAutoSyncAt: lastAutoSyncAt,
                now: now,
                minimumInterval: 5
            )
        )
    }

    func testPreferredAutoSyncStrategyUsesFullSyncUntilFirstSuccess() {
        XCTAssertEqual(AuthGateView.preferredAutoSyncStrategy(lastSyncAt: nil), .full)
        XCTAssertEqual(
            AuthGateView.preferredAutoSyncStrategy(lastSyncAt: Date(timeIntervalSince1970: 1_741_740_000)),
            .incremental
        )
    }

    func testDiagnosticsExportTextIncludesOperationalContext() {
        let dealerId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let report = SyncDiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 1_741_750_000),
            lastSyncAt: Date(timeIntervalSince1970: 1_741_749_000),
            lastPushAt: Date(timeIntervalSince1970: 1_741_749_500),
            lastFailureAt: Date(timeIntervalSince1970: 1_741_749_700),
            lastFailureMessage: "Offline queue has dead-letter items that need manual attention.",
            isSyncing: false,
            health: .blocked,
            offlineQueueCount: 3,
            queueSnapshot: SyncQueueSnapshot(
                totalCount: 3,
                readyCount: 1,
                waitingCount: 1,
                deadLetterCount: 1,
                oldestQueuedAt: Date(timeIntervalSince1970: 1_741_748_000),
                nextRetryAt: Date(timeIntervalSince1970: 1_741_751_000),
                lastDeadLetterAt: Date(timeIntervalSince1970: 1_741_749_700)
            ),
            offlineQueueSummary: [
                SyncQueueSummaryItem(entity: .vehicle, operation: .upsert, count: 2),
                SyncQueueSummaryItem(entity: .expense, operation: .delete, count: 1)
            ],
            entityCounts: [
                SyncEntityCount(entity: .vehicle, localCount: 10, remoteCount: 9),
                SyncEntityCount(entity: .expense, localCount: 3, remoteCount: 3)
            ],
            remoteFetchError: "timeout"
        )

        let text = report.exportText(
            context: SyncDiagnosticsExportContext(
                dealerId: dealerId,
                isConnected: false,
                deviceName: "QA iPhone",
                systemVersion: "18.2",
                appVersion: "1.0 (100)"
            )
        )

        XCTAssertTrue(text.contains("Dealer: \(dealerId.uuidString)"))
        XCTAssertTrue(text.contains("Device: QA iPhone"))
        XCTAssertTrue(text.contains("Network: Offline"))
        XCTAssertTrue(text.contains("Health: Blocked"))
        XCTAssertTrue(text.contains("Queue Dead Letters: 1"))
        XCTAssertTrue(text.contains("Last Issue: Offline queue has dead-letter items that need manual attention."))
        XCTAssertTrue(text.contains("Remote Fetch Error: timeout"))
        XCTAssertTrue(text.contains("- Vehicles: Upsert x2"))
        XCTAssertTrue(text.contains("- Vehicles: local 10, remote 9, delta -1"))
    }

    func testNextPushAnchorOnlyMovesForward() {
        let current = Date(timeIntervalSince1970: 1_741_700_000)
        let older = current.addingTimeInterval(-120)
        let newer = current.addingTimeInterval(240)

        XCTAssertEqual(CloudSyncManager.nextPushAnchor(current: nil, candidate: current), current)
        XCTAssertEqual(CloudSyncManager.nextPushAnchor(current: current, candidate: nil), current)
        XCTAssertEqual(CloudSyncManager.nextPushAnchor(current: current, candidate: older), current)
        XCTAssertEqual(CloudSyncManager.nextPushAnchor(current: current, candidate: newer), newer)
    }

    func testQueueAnchorCandidateUsesPayloadTimestampAndIgnoresRawDelete() throws {
        let dealerId = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_741_710_000)
        let remoteVehicle = RemoteVehicle(
            id: UUID(),
            dealerId: dealerId,
            vin: "QUEUE-ANCHOR-1",
            make: "Anchor",
            model: "Vehicle",
            year: 2024,
            purchasePrice: 10_000,
            purchaseAccountId: nil,
            purchaseDate: "2026-03-07T00:00:00Z",
            status: "owned",
            notes: nil,
            createdAt: updatedAt.addingTimeInterval(-600),
            salePrice: nil,
            saleDate: nil,
            photoURL: nil,
            askingPrice: nil,
            reportURL: nil,
            mileage: nil,
            updatedAt: updatedAt,
            deletedAt: nil
        )
        let upsertItem = SyncQueueItem(
            entityType: .vehicle,
            operation: .upsert,
            payload: try JSONEncoder().encode(remoteVehicle),
            dealerId: dealerId,
            recordId: remoteVehicle.id
        )
        let deleteItem = SyncQueueItem(
            entityType: .vehicle,
            operation: .delete,
            payload: try JSONEncoder().encode(remoteVehicle.id),
            dealerId: dealerId,
            recordId: remoteVehicle.id
        )

        XCTAssertEqual(CloudSyncManager.queueAnchorCandidate(for: upsertItem), updatedAt)
        XCTAssertNil(CloudSyncManager.queueAnchorCandidate(for: deleteItem))
    }

    func testQueueAnchorCandidateParsesStringTimestampForUserPayload() throws {
        let dealerId = UUID()
        let updatedAtString = "2026-03-07T02:30:00.000Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = try XCTUnwrap(formatter.date(from: updatedAtString))
        let remoteUser = RemoteDealerUser(
            id: UUID(),
            dealerId: dealerId,
            name: "Queue User",
            firstName: nil,
            lastName: nil,
            email: "queue@example.com",
            phone: nil,
            avatarURL: nil,
            createdAt: "2026-03-07T02:00:00.000Z",
            updatedAt: updatedAtString,
            deletedAt: nil
        )
        let item = SyncQueueItem(
            entityType: .user,
            operation: .upsert,
            payload: try JSONEncoder().encode(remoteUser),
            dealerId: dealerId,
            recordId: remoteUser.id
        )

        XCTAssertEqual(CloudSyncManager.queueAnchorCandidate(for: item), expectedDate)
    }

    func testPrepareLocalPushPayloadUsesDeltaWindowAndSkipsProtectedVehicleTree() async throws {
        let dealerId = UUID()
        let lowerBound = Date(timeIntervalSince1970: 1_741_600_000)
        let upperBound = lowerBound.addingTimeInterval(600)

        let oldVehicle = makeVehicle(
            make: "Old",
            model: "Alpha",
            status: "owned",
            purchasePrice: 10_000,
            purchaseDate: lowerBound.addingTimeInterval(-3_600),
            updatedAt: lowerBound.addingTimeInterval(-1)
        )
        let includedVehicle = makeVehicle(
            make: "Included",
            model: "Bravo",
            status: "owned",
            purchasePrice: 11_000,
            purchaseDate: lowerBound.addingTimeInterval(-1_800),
            updatedAt: lowerBound.addingTimeInterval(120)
        )
        let futureVehicle = makeVehicle(
            make: "Future",
            model: "Charlie",
            status: "owned",
            purchasePrice: 12_000,
            purchaseDate: lowerBound.addingTimeInterval(-900),
            updatedAt: upperBound.addingTimeInterval(1)
        )
        let skippedVehicle = makeVehicle(
            make: "Skipped",
            model: "Delta",
            status: "owned",
            purchasePrice: 13_000,
            purchaseDate: lowerBound.addingTimeInterval(-600),
            updatedAt: lowerBound.addingTimeInterval(240)
        )

        let includedExpense = makeExpense(
            description: "Included expense",
            amount: 500,
            date: lowerBound.addingTimeInterval(180),
            vehicle: includedVehicle,
            updatedAt: lowerBound.addingTimeInterval(180)
        )
        _ = makeExpense(
            description: "Skipped expense",
            amount: 700,
            date: lowerBound.addingTimeInterval(300),
            vehicle: skippedVehicle,
            updatedAt: lowerBound.addingTimeInterval(300)
        )

        _ = oldVehicle
        _ = futureVehicle
        try context.save()

        let manager = makeCloudSyncManager()
        let payload = try await manager.prepareLocalPushPayload(
            context: context,
            dealerId: dealerId,
            window: .init(changedAfter: lowerBound, changedBeforeOrAt: upperBound),
            skippingVehicleIds: [try XCTUnwrap(skippedVehicle.id)]
        )

        XCTAssertEqual(Set(payload.vehicles.map(\.id)), [try XCTUnwrap(includedVehicle.id)])
        XCTAssertEqual(Set(payload.expenses.map(\.id)), [try XCTUnwrap(includedExpense.id)])
        XCTAssertTrue(payload.sales.isEmpty)
        XCTAssertTrue(payload.clients.isEmpty)
    }

    func testSyncQueueQuarantinesCorruptedPersistenceFile() async throws {
        let queueURL = try makeTemporaryQueueURL()
        let directoryURL = queueURL.deletingLastPathComponent()
        try Data("not-json".utf8).write(to: queueURL, options: .atomic)

        let queue = SyncQueueManager(queueFileURL: queueURL)
        let loadedItems = await queue.getAllItems()

        XCTAssertTrue(loadedItems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueURL.path))

        let files = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.lastPathComponent.contains("sync_queue-corrupted-") })
    }

    func testRangeArchiveExcludesSoftDeletedRecordsFromMetadataAndExports() async throws {
        let rangeStart = Date(timeIntervalSince1970: 1_741_305_600)
        let rangeEnd = rangeStart.addingTimeInterval(86_400)

        let visibleSoldVehicle = makeVehicle(
            make: "VisibleSoldMake",
            model: "Alpha",
            status: "sold",
            purchasePrice: 10_000,
            salePrice: 14_000,
            purchaseDate: rangeStart.addingTimeInterval(-86_400),
            saleDate: rangeStart.addingTimeInterval(3_600)
        )
        _ = makeVehicle(
            make: "DeletedSoldMake",
            model: "Bravo",
            status: "sold",
            purchasePrice: 8_000,
            salePrice: 12_000,
            purchaseDate: rangeStart.addingTimeInterval(-86_400),
            saleDate: rangeStart.addingTimeInterval(7_200),
            deletedAt: rangeStart.addingTimeInterval(10_800)
        )
        _ = makeVehicle(
            make: "VisibleInventoryMake",
            model: "Charlie",
            status: "owned",
            purchasePrice: 9_500,
            purchaseDate: rangeStart.addingTimeInterval(-43_200)
        )
        _ = makeVehicle(
            make: "DeletedInventoryMake",
            model: "Delta",
            status: "owned",
            purchasePrice: 7_500,
            purchaseDate: rangeStart.addingTimeInterval(-21_600),
            deletedAt: rangeStart.addingTimeInterval(14_400)
        )

        makeExpense(
            description: "Visible expense",
            amount: 500,
            date: rangeStart.addingTimeInterval(1_800),
            vehicle: visibleSoldVehicle
        )
        makeExpense(
            description: "Deleted expense",
            amount: 900,
            date: rangeStart.addingTimeInterval(5_400),
            vehicle: visibleSoldVehicle,
            deletedAt: rangeStart.addingTimeInterval(16_200)
        )

        _ = makeClient(name: "Visible Client")
        _ = makeClient(name: "Deleted Client", deletedAt: rangeStart.addingTimeInterval(18_000))

        try context.save()

        let manager = BackupExportManager(context: context)
        let archiveURL = try await manager.createRangeArchive(
            for: DateInterval(start: rangeStart, end: rangeEnd),
            dealerId: nil
        )
        temporaryURLs.append(archiveURL)

        let archiveData = try Data(contentsOf: archiveURL)
        let payload = try JSONDecoder().decode(BackupArchivePayload.self, from: archiveData)

        XCTAssertEqual(payload.metadata.expenseTotal, Decimal(500))
        XCTAssertEqual(payload.metadata.salesTotal, Decimal(14_000))
        for file in payload.files {
            let temporaryFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryFileURL.path))
        }

        let expensesCSV = try decodedTextFile(prefix: "expenses-", from: payload)
        XCTAssertTrue(expensesCSV.contains("Visible expense"))
        XCTAssertFalse(expensesCSV.contains("Deleted expense"))

        let vehiclesCSV = try decodedTextFile(prefix: "vehicles-", from: payload)
        XCTAssertTrue(vehiclesCSV.contains("VisibleSoldMake"))
        XCTAssertTrue(vehiclesCSV.contains("VisibleInventoryMake"))
        XCTAssertFalse(vehiclesCSV.contains("DeletedSoldMake"))
        XCTAssertFalse(vehiclesCSV.contains("DeletedInventoryMake"))

        let clientsCSV = try decodedTextFile(prefix: "clients-", from: payload)
        XCTAssertTrue(clientsCSV.contains("Visible Client"))
        XCTAssertFalse(clientsCSV.contains("Deleted Client"))

        let pdfText = try decodedPDFText(from: payload)
        XCTAssertTrue(pdfText.contains("VisibleSoldMake"))
        XCTAssertFalse(pdfText.contains("DeletedSoldMake"))
    }

    private func decodedTextFile(prefix: String, from payload: BackupArchivePayload) throws -> String {
        guard let file = payload.files.first(where: { $0.name.hasPrefix(prefix) }) else {
            throw TestError.missingPayloadFile(prefix)
        }
        guard let data = Data(base64Encoded: file.base64) else {
            throw TestError.invalidBase64(file.name)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func decodedPDFText(from payload: BackupArchivePayload) throws -> String {
        guard let file = payload.files.first(where: { $0.contentType == "application/pdf" }) else {
            throw TestError.missingPayloadFile("application/pdf")
        }
        guard let data = Data(base64Encoded: file.base64) else {
            throw TestError.invalidBase64(file.name)
        }
        guard let document = PDFDocument(data: data), let text = document.string else {
            throw TestError.unreadablePDF(file.name)
        }
        return text
    }

    private func prepareSubscriptionManager() async -> SubscriptionManager {
        XCTAssertFalse(Purchases.isConfigured)
        let manager = SubscriptionManager.shared
        manager.logOut()
        await drainMainQueue()
        return manager
    }

    private func makeCloudSyncManager() -> CloudSyncManager {
        CloudSyncManager(
            client: SupabaseClient(
                supabaseURL: URL(string: "https://example.com")!,
                supabaseKey: "dummy"
            ),
            context: context
        )
    }

    private func makeTemporaryQueueURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        temporaryURLs.append(directoryURL)
        return directoryURL.appendingPathComponent("sync_queue.json")
    }

    private func drainMainQueue() async {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 1.0)
    }

    @discardableResult
    private func makeVehicle(
        make: String,
        model: String,
        status: String,
        purchasePrice: Decimal,
        salePrice: Decimal? = nil,
        purchaseDate: Date,
        saleDate: Date? = nil,
        deletedAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> Vehicle {
        let vehicle = Vehicle(context: context)
        vehicle.id = UUID()
        vehicle.make = make
        vehicle.model = model
        vehicle.status = status
        vehicle.year = 2024
        vehicle.vin = UUID().uuidString
        vehicle.purchasePrice = NSDecimalNumber(decimal: purchasePrice)
        vehicle.purchaseDate = purchaseDate
        vehicle.salePrice = salePrice.map { NSDecimalNumber(decimal: $0) }
        vehicle.saleDate = saleDate
        vehicle.createdAt = purchaseDate
        vehicle.updatedAt = updatedAt ?? purchaseDate
        vehicle.deletedAt = deletedAt
        return vehicle
    }

    @discardableResult
    private func makeExpense(
        description: String,
        amount: Decimal,
        date: Date,
        vehicle: Vehicle,
        deletedAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> Expense {
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.expenseDescription = description
        expense.amount = NSDecimalNumber(decimal: amount)
        expense.category = "vehicle"
        expense.date = date
        expense.createdAt = date
        expense.updatedAt = updatedAt ?? date
        expense.deletedAt = deletedAt
        expense.vehicle = vehicle
        return expense
    }

    @discardableResult
    private func makeClient(name: String, deletedAt: Date? = nil, updatedAt: Date? = nil) -> Client {
        let client = Client(context: context)
        client.id = UUID()
        client.name = name
        client.createdAt = Date()
        client.updatedAt = updatedAt ?? Date()
        client.deletedAt = deletedAt
        return client
    }
}

private enum TestError: Error {
    case missingPayloadFile(String)
    case invalidBase64(String)
    case unreadablePDF(String)
}
