import SwiftUI

@MainActor
struct KajiAccordionStyle {
    var verticalPadding: CGFloat = 0
    var contentTopPadding: CGFloat = 8
    var contentLeadingPadding: CGFloat = 0
    var railContentLeadingPadding: CGFloat = 0
    var railWidth: CGFloat = 1
    var railHeight: CGFloat = 18
    var railTopPadding: CGFloat = 4
    var railColor: Color = KajiTheme.borderStrong.opacity(0.4)
    var showsRail = false

    static let plain = KajiAccordionStyle()

    static let transcriptThinking = KajiAccordionStyle(
        verticalPadding: 7,
        contentTopPadding: 8,
        contentLeadingPadding: 0,
        railContentLeadingPadding: 14,
        railWidth: 2,
        railHeight: 18,
        railTopPadding: 3,
        railColor: KajiTheme.borderStrong.opacity(0.42),
        showsRail: true
    )

    static let transcriptTool = KajiAccordionStyle(
        verticalPadding: 6,
        contentTopPadding: 10,
        contentLeadingPadding: 0
    )

    static let parentAgent = KajiAccordionStyle(
        verticalPadding: 8,
        contentTopPadding: 8,
        contentLeadingPadding: 22
    )

    static let missionControlEvidence = KajiAccordionStyle(
        verticalPadding: 0,
        contentTopPadding: 4,
        contentLeadingPadding: 0
    )
}

struct KajiAccordionItem<Header: View, Content: View>: View {
    let isExpanded: Bool
    var isEnabled = true
    var accessibilityLabel: String
    var style: KajiAccordionStyle = .plain
    let onToggle: () -> Void
    @ViewBuilder let header: (Bool) -> Header
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredContentHeight: CGFloat = 0
    @State private var isContentMounted = false
    @State private var unmountTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trigger
            panel
        }
        .padding(.leading, style.showsRail ? style.railContentLeadingPadding : 0)
        .padding(.vertical, style.verticalPadding)
        .overlay(alignment: .topLeading) { rail }
        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: isExpanded)
        .onAppear { isContentMounted = isExpanded }
        .onChange(of: isExpanded) { _, expanded in
            updateMountedState(expanded: expanded)
        }
        .onDisappear { unmountTask?.cancel() }
    }

    private var trigger: some View {
        Button(action: toggle) {
            header(isExpanded)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .kajiPointer(isEnabled ? .pointingHand : .arrow)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var panel: some View {
        if isContentMounted {
            ZStack(alignment: .topLeading) {
                contentBody
                    .opacity(isExpanded ? 1 : 0)
            }
            .frame(height: visibleContentHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .background(alignment: .topLeading) { measuringContent }
            .accessibilityHidden(!isExpanded)
        }
    }

    private var contentBody: some View {
        content()
            .padding(.top, style.contentTopPadding)
            .padding(.leading, style.contentLeadingPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measuringContent: some View {
        contentBody
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay {
                GeometryReader { proxy in
                    Color.clear.preference(key: KajiAccordionContentHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(KajiAccordionContentHeightPreferenceKey.self) { height in
                guard height.isFinite, height >= 0 else { return }
                measuredContentHeight = ceil(height)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var rail: some View {
        if style.showsRail {
            Capsule()
                .fill(style.railColor)
                .frame(width: style.railWidth, height: railHeight)
                .padding(.top, style.railTopPadding)
        }
    }

    private var visibleContentHeight: CGFloat {
        isExpanded ? measuredContentHeight : 0
    }

    private var railHeight: CGFloat {
        guard isExpanded else { return style.railHeight }
        return max(style.railHeight, style.railTopPadding + measuredContentHeight + style.contentTopPadding)
    }

    private func toggle() {
        guard isEnabled else { return }
        onToggle()
    }

    private func updateMountedState(expanded: Bool) {
        unmountTask?.cancel()
        guard !expanded else {
            isContentMounted = true
            return
        }
        unmountTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 90 : 280))
            guard !Task.isCancelled else { return }
            isContentMounted = false
        }
    }
}

private struct KajiAccordionContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
