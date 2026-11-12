// NeoSpring document adapted from Mak5er/AirCard-iOS RespringHelper.swift,
// commit 40640c4d827aeab8d798285b57d24fcf6be070d0 (MIT notice: ThirdParty/AirCard-MIT.txt).
// Original mechanism credited to @neonmodder123 and @skadz108; upstream also cites rooootdev/neospring.
import SwiftUI
import WebKit
import UIKit

struct NeoSpringRequest: Identifiable {
    let id: UUID
}

enum NeoSpringOutcome: Equatable {
    case ended, cancelled, interrupted, timedOut
    case failed(String)
}

@MainActor
final class NeoSpringController: ObservableObject {
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: Self.preferenceKey) }
    }
    @Published private(set) var request: NeoSpringRequest?
    private static let preferenceKey = "automaticNeoSpring"
    private let defaults: UserDefaults
    private let timeout: Duration
    private let isForeground: @MainActor () -> Bool
    private var timeoutTask: Task<Void, Never>?
    private var completion: ((NeoSpringOutcome) -> Void)?

    init(defaults: UserDefaults = .standard, timeout: Duration = .seconds(15),
         isForeground: (@MainActor () -> Bool)? = nil) {
        self.defaults = defaults; self.timeout = timeout
        self.isForeground = isForeground ?? { UIApplication.shared.applicationState == .active }
        automatic = defaults.bool(forKey: Self.preferenceKey)
    }

    func start(completion: @escaping (NeoSpringOutcome) -> Void) throws {
        guard request == nil else { throw BridgeError.message(L10n.text("error.neoSpringActive")) }
        guard isForeground() else { throw BridgeError.message(L10n.text("error.neoSpringForeground")) }
        let current = NeoSpringRequest(id: UUID())
        self.completion = completion; request = current
        let delay = timeout
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.complete(current.id, outcome: .timedOut)
        }
    }

    func complete(_ id: UUID, outcome: NeoSpringOutcome) {
        guard request?.id == id else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        request = nil
        let callback = completion; completion = nil; callback?(outcome)
    }
    func cancel() { if let request { complete(request.id, outcome: .cancelled) } }
    func didEnterBackground() { if let request { complete(request.id, outcome: .interrupted) } }
}

private enum NeoSpringDocument {
    static let html = """
<!DOCTYPE html>
<html style="background:#000">
    <body style="margin:0;background:#000">
        <!-- big credit to @neonmodder123 & @skadz108 (neospring) -->
        <iframe id="frame" srcdoc="" sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe>
        <script>
            const frame = document.getElementById('frame');
            const funfun = `
                <html style="background:#000">
                <body style="margin:0;background:#000">
                    <script>
                        const container = document.createElement('div');
                        container.style.cssText = 'perspective: 1px; perspective-origin: 9999999% 9999999%;';
                        document.body.appendChild(container);
    
                        for (let i = 0; i < 500; i++) {
                            let d = document.createElement('div');
                            d.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(100px); -webkit-backdrop-filter: blur(100px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';
                            container.appendChild(d);
                        }
    
                        const neoSpringTimer = setInterval(() => {
                            navigator.share({ title: 'R', text: 'R'.repeat(100000) }).catch(() => {});
                            let x = new Uint8Array(1024 * 1024 * 10);
                            crypto.getRandomValues(x);
                        }, 0);
                        const stopNeoSpring = () => {
                            clearInterval(neoSpringTimer);
                            container.remove();
                        };
                        window.addEventListener('message', event => {
                            if (event.data === 'PawsterStopNeoSpring') stopNeoSpring();
                        });
                        setTimeout(stopNeoSpring, 12000);
                    <\\/script>
                </body>
                </html>
            `;
    
            frame.srcdoc = funfun;
        </script>
    </body>
</html>
"""
    static let stopScript = "document.getElementById('frame')?.contentWindow?.postMessage('PawsterStopNeoSpring', '*')"
}

struct NeoSpringScreen: View {
    let request: NeoSpringRequest
    let complete: (NeoSpringOutcome) -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            NeoSpringWebView(request: request, complete: complete).id(request.id).ignoresSafeArea()
            ProgressView("NeoSpring…")
                .tint(.white).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            VStack {
                Button(L10n.text("action.cancel")) { complete(.cancelled) }.buttonStyle(.bordered).tint(.white)
                Spacer()
            }.padding()
        }
        .background(.black)
        .interactiveDismissDisabled()
    }
}

private struct NeoSpringWebView: UIViewRepresentable {
    let request: NeoSpringRequest
    let complete: (NeoSpringOutcome) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.backgroundColor = .black; view.isOpaque = true
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        // Load once per session; SwiftUI updates must not restart the rendering workload.
        view.loadHTMLString(NeoSpringDocument.html, baseURL: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopped = true; uiView.navigationDelegate = nil
        uiView.evaluateJavaScript(NeoSpringDocument.stopScript, completionHandler: nil)
        uiView.stopLoading()
        uiView.loadHTMLString("<html><body></body></html>", baseURL: nil)
    }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var stopped = false
        let complete: (NeoSpringOutcome) -> Void
        init(complete: @escaping (NeoSpringOutcome) -> Void) { self.complete = complete }
        nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }; self.complete(.ended)
            }
        }
        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }; self.complete(.failed(message))
            }
        }
        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }; self.complete(.failed(message))
            }
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(.tint)
                configuration.label.foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? L10n.text("accessibility.checked") : L10n.text("accessibility.unchecked"))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
