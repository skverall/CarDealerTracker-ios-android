//
//  AppReviewManager.swift
//  Ezcar24Business
//
//  Lightweight, non-intrusive in-app review prompts
//

import CoreData
import StoreKit
import UIKit

enum ReviewTrigger {
    case expenseThreshold
    case firstSale
}

final class AppReviewManager {
    static let shared = AppReviewManager()

    private let defaults = UserDefaults.standard
    private let hasPromptedKey = "appReview.hasPrompted"
    private let lastPromptKey = "appReview.lastPromptAt"
    private let installDateKey = "appReview.installDate"

    private let minExpenseCount = 3
    private let minSaleCount = 1

    private init() {
        if defaults.object(forKey: installDateKey) == nil {
            defaults.set(Date(), forKey: installDateKey)
        }
    }

    func handleExpenseAdded(context: NSManagedObjectContext) {
        guard shouldRequestReview(trigger: .expenseThreshold, context: context) else { return }
        requestReview()
    }

    func handleSaleAdded(context: NSManagedObjectContext) {
        guard shouldRequestReview(trigger: .firstSale, context: context) else { return }
        requestReview()
    }

    private func shouldRequestReview(trigger: ReviewTrigger, context: NSManagedObjectContext) -> Bool {
        guard !defaults.bool(forKey: hasPromptedKey) else { return false }

        switch trigger {
        case .expenseThreshold:
            return fetchCount(entityName: "Expense", context: context) >= minExpenseCount
        case .firstSale:
            return fetchCount(entityName: "Sale", context: context) >= minSaleCount
        }
    }

    private func fetchCount(entityName: String, context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        var count = 0
        context.performAndWait {
            count = (try? context.count(for: request)) ?? 0
        }
        return count
    }

    private func requestReview() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            SKStoreReviewController.requestReview(in: scene)
            self.defaults.set(true, forKey: self.hasPromptedKey)
            self.defaults.set(Date(), forKey: self.lastPromptKey)
        }
    }
}
