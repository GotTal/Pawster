import SwiftUI
import Combine

private struct BackgroundMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var pawsterBackgroundMotion: Bool {
        get { self[BackgroundMotionKey.self] }
        set { self[BackgroundMotionKey.self] = newValue }
    }
}

struct PawsterBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pawsterBackgroundMotion) private var motionEnabled
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var paused: Bool {
        !visible || scenePhase != .active || !motionEnabled || reduceMotion || lowPower || contrast == .increased
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if contrast != .increased {
                // Only this decorative layer updates; the List and its rows stay outside the timeline.
                TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: paused)) { timeline in
                    let dark = colorScheme == .dark
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        Self.draw(context, size: size, time: time, dark: dark)
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { visible = true; lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    nonisolated private static func draw(_ context: GraphicsContext, size: CGSize, time: TimeInterval, dark: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let width = size.width, height = size.height
        let bounds = Path(CGRect(origin: .zero, size: size))
        let mint = Color(red: 0.06, green: 0.72, blue: 0.70)
        let blue = Color(red: 0.32, green: 0.57, blue: 0.86)
        let drift = CGFloat(sin(time * .pi / 32))
        let breath = 0.5 + 0.5 * sin(time * .pi / 13)
        let radius = min(width, height) * 0.94

        // Radial gradients give soft edges without full-screen blur or image assets.
        context.fill(bounds, with: .radialGradient(
            Gradient(colors: [mint.opacity(dark ? 0.105 : 0.075), .clear]),
            center: CGPoint(x: width * (0.88 + drift * 0.025), y: height * 0.12),
            startRadius: 0, endRadius: radius))
        context.fill(bounds, with: .radialGradient(
            Gradient(colors: [blue.opacity(dark ? 0.075 : 0.050), .clear]),
            center: CGPoint(x: width * 0.10, y: height * (0.81 - drift * 0.018)),
            startRadius: 0, endRadius: radius * 0.90))

        let spacing = max(64, min(92, width / 5.5))
        var grid = Path()
        for column in 0...Int(width / spacing) {
            let x = CGFloat(column) * spacing
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: height))
        }
        for row in 0...Int(height / spacing) {
            let y = CGFloat(row) * spacing
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(grid, with: .linearGradient(Gradient(stops: [
            .init(color: mint.opacity(dark ? 0.055 : 0.040), location: 0),
            .init(color: .clear, location: 0.42),
            .init(color: .clear, location: 0.64),
            .init(color: blue.opacity(dark ? 0.045 : 0.030), location: 1)
        ]), startPoint: .zero, endPoint: CGPoint(x: width, y: height)), lineWidth: 0.5)

        let routes: [[CGPoint]] = [
            [CGPoint(x: width * 0.64, y: height * 0.12), CGPoint(x: width * 0.81, y: height * 0.12),
             CGPoint(x: width * 0.90, y: height * 0.12 + width * 0.09), CGPoint(x: width * 0.90, y: height * 0.29)],
            [CGPoint(x: width * 0.10, y: height * 0.70), CGPoint(x: width * 0.10, y: height * 0.80),
             CGPoint(x: width * 0.19, y: height * 0.80 + width * 0.09), CGPoint(x: width * 0.39, y: height * 0.80 + width * 0.09)]
        ]
        for (index, points) in routes.enumerated() {
            let color = index == 0 ? mint : blue
            var route = Path(); route.addLines(points)
            context.stroke(route, with: .color(color.opacity(dark ? 0.10 : 0.075)),
                           style: StrokeStyle(lineWidth: 0.65, lineCap: .round, lineJoin: .round))
            for point in [points[0], points[points.count - 1]] {
                let dot = Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
                context.fill(dot, with: .color(color.opacity(0.09 + breath * 0.035)))
            }
        }
    }
}

extension View {
    func pawsterBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { PawsterBackground().ignoresSafeArea() }
    }
}
