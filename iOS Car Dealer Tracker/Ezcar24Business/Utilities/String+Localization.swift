//
//  String+Localization.swift
//  Ezcar24Business
//
//  Extensions to support manual localization lookup required for immediate
//  in-app language switching without restart.
//

import Foundation
import SwiftUI

extension String {
    /// Returns the localized string for this key using the currently selected app language.
    /// This bypasses the default Bundle.main lookup which relies on system language preferences.
    @MainActor
    var localizedString: String {
        let language = RegionSettingsManager.shared.selectedLanguage.rawValue
        
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // Fallback to default lookup if bundle not found
            return NSLocalizedString(self, comment: "")
        }
        
        return NSLocalizedString(self, tableName: nil, bundle: bundle, value: self, comment: "")
    }
    
    /// Returns a LocalizedStringKey wrapping the manually localized value.
    /// Useful for passing to SwiftUI views that expect a Key but need the *value* to be correct immediately.
    @MainActor
    var localizedKey: LocalizedStringKey {
        return LocalizedStringKey(self.localizedString)
    }
}
