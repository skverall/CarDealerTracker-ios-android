import SwiftUI
import AuthenticationServices

/// UIKit wrapper for ASWebAuthenticationSession - opens system browser for OAuth
struct NotionAuthSessionWrapper: UIViewControllerRepresentable {
    let url: URL
    let onCallback: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> NotionAuthViewController {
        let controller = NotionAuthViewController()
        controller.url = url
        controller.onCallback = onCallback
        controller.onCancel = onCancel
        return controller
    }
    
    func updateUIViewController(_ uiViewController: NotionAuthViewController, context: Context) {}
}

/// Controller that manages ASWebAuthenticationSession
class NotionAuthViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    var url: URL!
    var onCallback: ((URL) -> Void)?
    var onCancel: (() -> Void)?
    private var authSession: ASWebAuthenticationSession?
    private var hasStarted = false
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Only start once
        if !hasStarted {
            hasStarted = true
            startAuthSession()
        }
    }
    
    private func startAuthSession() {
        authSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "ezcar24"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                if let callbackURL = callbackURL {
                    self?.onCallback?(callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    self?.onCancel?()
                } else {
                    // Other error or user cancelled
                    self?.onCancel?()
                }
            }
        }
        
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? UIWindow()
    }
}

/// SwiftUI sheet for Notion OAuth - uses system browser
struct NotionAuthSheet: View {
    let url: URL
    let onCallback: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NotionAuthSessionWrapper(
            url: url,
            onCallback: { callbackUrl in
                onCallback(callbackUrl)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
        .edgesIgnoringSafeArea(.all)
    }
}

/// Legacy view for backwards compatibility - kept for any existing references
struct NotionAuthView: UIViewRepresentable {
    let url: URL
    let onCallback: (URL) -> Void
    
    func makeUIView(context: Context) -> UIView {
        // Placeholder - actual auth should use NotionAuthSheet
        let view = UIView()
        view.backgroundColor = .systemBackground
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}