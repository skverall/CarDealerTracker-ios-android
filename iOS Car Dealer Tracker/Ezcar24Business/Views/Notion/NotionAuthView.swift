import SwiftUI
import WebKit

struct NotionAuthView: UIViewRepresentable {
    let url: URL
    let onCallback: (URL) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let onCallback: (URL) -> Void
        
        init(onCallback: @escaping (URL) -> Void) {
            self.onCallback = onCallback
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.scheme == "ezcar24" {
                onCallback(url)
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Navigation failed: \(error)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Provisional navigation failed: \(error)")
        }
    }
}

struct NotionAuthSheet: View {
    let url: URL
    let onCallback: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            NotionAuthView(url: url) { callbackUrl in
                onCallback(callbackUrl)
                dismiss()
            }
            .navigationTitle("Connect to Notion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}