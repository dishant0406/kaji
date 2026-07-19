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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .padding(.top, SettingsMetrics.sectionHeaderTopPadding)
                .padding(.bottom, SettingsMetrics.sectionHeaderBottomPadding)

            content

            if let footer {
                Text(footer)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsMetrics.horizontalPadding)
                    .padding(.top, SettingsMetrics.sectionFooterTopPadding)
                    .padding(.bottom, SettingsMetrics.sectionFooterBottomPadding)
            }

            if showsDivider {
                Rectangle()
                    .fill(KajiTheme.border)
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
                .kajiFont(size: SettingsMetrics.labelFontSize)
                .foregroundStyle(KajiTheme.fg)
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
            KajiSwitch(isOn: $isOn)
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
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(detail)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            KajiSwitch(isOn: $isOn)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}

struct SettingsDetailStatusRow: View {
    let label: String
    let detail: String
    let status: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(detail)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(status)
                .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
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
            KajiSelect(
                options: Option.allCases.map {
                    KajiSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0.rawValue)
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
            KajiInput(
                placeholder: placeholder,
                text: $text,
                width: width,
                monospaced: monospaced
            )
        }
    }
}

struct SettingsDetailPickerRow<Value: Hashable>: View {
    let label: String
    let detail: String
    let options: [KajiSelectOption<Value>]
    @Binding var selection: Value
    var width: CGFloat = SettingsMetrics.controlWidth

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(detail)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            KajiSelect(options: options, selection: $selection, width: width)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}

struct SettingsStatusActionRow<Actions: View>: View {
    let icon: String
    let label: String
    let detail: String
    let status: String
    let statusColor: Color
    @ViewBuilder let actions: Actions

    init(
        icon: String,
        label: String,
        detail: String,
        status: String,
        statusColor: Color = KajiTheme.fgMuted,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.label = label
        self.detail = detail
        self.status = status
        self.statusColor = statusColor
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            KajiIcon(systemName: icon, size: 16)
                .frame(width: 18)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(status)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                        .foregroundStyle(statusColor)
                }
                Text(detail)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                actions
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }
}
