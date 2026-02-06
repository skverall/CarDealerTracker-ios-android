import UIKit
import LinkPresentation

final class ShareLinkItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String
    private let icon: UIImage?

    init(url: URL, title: String, icon: UIImage?) {
        self.url = url
        self.title = title
        self.icon = icon
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        metadata.url = url
        if let icon {
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        return metadata
    }
}
