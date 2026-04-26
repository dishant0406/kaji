import SwiftUI

enum SettingsMetrics {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 6
    static let sectionHeaderTopPadding: CGFloat = 10
    static let sectionHeaderBottomPadding: CGFloat = 4
    static let sectionFooterTopPadding: CGFloat = 6
    static let sectionFooterBottomPadding: CGFloat = 10
    static let labelFontSize: CGFloat = 12
    static let footnoteFontSize: CGFloat = 11
    static let controlWidth: CGFloat = 210
}

struct SettingsContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let showsDivider: Bool
    @ViewBuilder var content: Content

    init(
        _ title: String,
        footer: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: SettingsMetrics.footnoteFontSize, weight: .semibold))
                .foregroundStyle(DroidTheme.fgDim)
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .padding(.top, SettingsMetrics.sectionHeaderTopPadding)
                .padding(.bottom, SettingsMetrics.sectionHeaderBottomPadding)

            content

            if let footer {
                Text(footer)
                    .font(.system(size: SettingsMetrics.footnoteFontSize))
                    .foregroundStyle(DroidTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsMetrics.horizontalPadding)
                    .padding(.top, SettingsMetrics.sectionFooterTopPadding)
                    .padding(.bottom, SettingsMetrics.sectionFooterBottomPadding)
            }

            if showsDivider {
                Rectangle()
                    .fill(DroidTheme.border)
                    .frame(height: 1)
                    .padding(.horizontal, SettingsMetrics.horizontalPadding)
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: SettingsMetrics.labelFontSize))
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            content
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}

struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(label) {
            DroidSwitch(isOn: $isOn)
        }
    }
}

struct SettingsDetailToggleRow: View {
    let label: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: SettingsMetrics.labelFontSize, weight: .medium))
                    .foregroundStyle(DroidTheme.fg)
                Text(detail)
                    .font(.system(size: SettingsMetrics.footnoteFontSize))
                    .foregroundStyle(DroidTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            DroidSwitch(isOn: $isOn)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}

struct SettingsPickerRow<Option: CaseIterable & Identifiable & RawRepresentable>: View
    where Option.RawValue == String, Option.AllCases: RandomAccessCollection
{
    let label: String
    @Binding var selection: String
    var width: CGFloat = SettingsMetrics.controlWidth

    var body: some View {
        SettingsRow(label) {
            DroidSelect(
                options: Option.allCases.map {
                    DroidSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0.rawValue)
                },
                selection: $selection,
                width: width
            )
        }
    }
}

struct SettingsInputRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = SettingsMetrics.controlWidth
    var monospaced = false

    var body: some View {
        SettingsRow(label) {
            DroidInput(
                placeholder: placeholder,
                text: $text,
                width: width,
                monospaced: monospaced
            )
        }
    }
}
