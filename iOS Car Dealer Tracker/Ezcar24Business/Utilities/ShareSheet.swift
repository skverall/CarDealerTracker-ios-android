import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let completion: (() -> Void)?

    init(
        items: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        completion: (() -> Void)? = nil
    ) {
        self.items = items
        self.excludedActivityTypes = excludedActivityTypes
        self.completion = completion
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension UIActivity.ActivityType {
    static let saveToFiles = UIActivity.ActivityType("com.apple.DocumentManagerUICore.SaveToFiles")
}
