//
//  RevenueCatKeyProvider.swift
//  Ezcar24Business
//
//  Centralizes API key selection for RevenueCat to avoid using test keys in release builds.
//

import Foundation

enum RevenueCatKeyProvider {
    static var currentKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String, key.starts(with: "appl_") {
            return key
        }
        return "appl_AcjVeBViWQjASmtxDkldEkmIvFf"
    }
}
