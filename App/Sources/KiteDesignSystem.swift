import SwiftUI
import UIKit

/**
 Kite Design System 2.0

 One place for color, type, spacing, radius, elevation, motion and the small
 set of surfaces the app is built from. Screens use these tokens instead of
 inventing their own corner radius or shadow.

 The palette is deliberately narrow: a deep ink navy, a calm paper light
 theme, and one bright teal used only for "go" (primary action, active tab,
 the route). Red/amber are reserved for danger and caution, never decoration.

 Light and dark are separate palettes, not an inversion. Dark uses a near-black
 canvas with blue-grey surfaces so the route and the arrow stay the brightest
 things on a night drive; light uses warm paper so sunlight does not wash out
 the labels.
 */
enum KiteColor {
    // MARK: Brand

    /// Filled primary action. Bright teal in both modes, with ink text.
    static let accent = adaptive(0x0FA79A, 0x2DD4BF)
    /// Text on an accent fill.
    static let onAccent = adaptive(0x04241F, 0x04241F)
    /// Teal for icons and text on a normal surface (darker by day).
    static let accentText = adaptive(0x0B7A70, 0x5EEAD4)
    /// A soft teal wash behind selected chips and secondary actions.
    static let accentSoft = adaptive(0xD9F5F0, 0x123B38)

    // MARK: Surfaces

    /// Whole-page background behind lists and settings.
    static let canvas = adaptive(0xF3F6F9, 0x0B1320)
    /// Floating sheets and cards.
    static let surface = adaptive(0xFFFFFF, 0x16212F)
    /// A card on top of a sheet.
    static let surfaceRaised = adaptive(0xFFFFFF, 0x1D2A3A)
    /// Chips, segmented controls, map buttons.
    static let fill = adaptive(0xE9EFF5, 0x253345)
    /// Hairlines and card edges.
    static let stroke = adaptive(0x0F172A, 0xFFFFFF).opacity(0.10)
    static let strokeStrong = adaptive(0x0F172A, 0xFFFFFF).opacity(0.18)

    // MARK: Text

    static let ink = adaptive(0x0F172A, 0xF1F5F9)
    static let inkSecondary = adaptive(0x526173, 0xA9B7C6)
    static let onInk = adaptive(0xFFFFFF, 0x0B1320)

    // MARK: Meaning

    /// The chosen route line and the navigation puck ring.
    static let route = adaptive(0x2563EB, 0x60A5FA)
    static let success = adaptive(0x15803D, 0x4ADE80)
    static let danger = adaptive(0xB91C1C, 0xF87171)
    static let warning = adaptive(0xB45309, 0xFBBF24)
    static let warningSoft = adaptive(0xFEF3E2, 0x3A2A10)
    static let transit = adaptive(0x7C3AED, 0xC4B5FD)
    static let camera = adaptive(0xEA580C, 0xFB923C)
    static let police = adaptive(0x2563EB, 0x93C5FD)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/** Type ramp. Rounded for the brand, monospaced digits for anything that moves. */
enum KiteText {
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func title(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func headline(_ size: CGFloat = 19) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .regular) }
    static func label(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold) }
    static func caption(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium) }
    /// Numbers that must not jitter while driving (distance, ETA, speed).
    static func digits(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/** A 4-point spacing scale. Every gap in the new screens comes from here. */
enum KiteSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum KiteRadius {
    static let chip: CGFloat = 12
    static let button: CGFloat = 16
    static let card: CGFloat = 22
    static let sheet: CGFloat = 28
    static let floatingSheet: CGFloat = 34
}

enum KiteElevation {
    /// Floating map buttons and chips.
    static let low = (color: Color.black.opacity(0.12), radius: CGFloat(6), y: CGFloat(2))
    /// Cards above a sheet.
    static let medium = (color: Color.black.opacity(0.16), radius: CGFloat(14), y: CGFloat(6))
    /// Sheets over the map.
    static let high = (color: Color.black.opacity(0.28), radius: CGFloat(24), y: CGFloat(-2))
}

/** Motion. Reduce Motion turns travel into a fade instead of a slide. */
enum KiteMotion {
    static let snap = Animation.spring(response: 0.28, dampingFraction: 0.90)
    static let sheet = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let gentle = Animation.easeOut(duration: 0.20)
    static let banner = Animation.spring(response: 0.38, dampingFraction: 0.82)

    static func travel(reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

// MARK: - Surfaces

/** A standard Kite card: one radius, one border, one shadow, everywhere. */
struct KiteCard: ViewModifier {
    var padding: CGFloat = KiteSpace.m
    var radius: CGFloat = KiteRadius.card
    var raised = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(raised ? KiteColor.surfaceRaised : KiteColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(KiteColor.stroke, lineWidth: 1)
                    )
                    .shadow(color: KiteElevation.medium.color, radius: KiteElevation.medium.radius,
                            y: KiteElevation.medium.y)
            )
    }
}

extension View {
    func kiteCard(padding: CGFloat = KiteSpace.m, radius: CGFloat = KiteRadius.card,
                  raised: Bool = false) -> some View {
        modifier(KiteCard(padding: padding, radius: radius, raised: raised))
    }
}

/** Frosted surface for controls that float over the map. */
struct KiteGlass<S: Shape>: ViewModifier {
    let shape: S
    var strong = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(KiteColor.surface.opacity(strong ? 0.94 : (scheme == .dark ? 0.72 : 0.80))))
                    .overlay(shape.stroke(KiteColor.strokeStrong, lineWidth: 0.75))
                    .shadow(color: KiteElevation.medium.color, radius: 10, y: 3)
            )
    }
}

extension View {
    func kiteGlass<S: Shape>(_ shape: S, strong: Bool = false) -> some View {
        modifier(KiteGlass(shape: shape, strong: strong))
    }
}

// MARK: - Controls

struct KitePrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    var compact = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KiteText.headline(compact ? 16 : 18))
            .foregroundColor(KiteColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, compact ? KiteSpace.s : KiteSpace.m)
            .background(
                RoundedRectangle(cornerRadius: KiteRadius.button, style: .continuous)
                    .fill(KiteColor.accent)
                    .opacity(enabled ? 1 : 0.45)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: KiteRadius.button, style: .continuous))
    }
}

struct KiteSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KiteText.headline(16))
            .foregroundColor(KiteColor.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, KiteSpace.m)
            .background(
                RoundedRectangle(cornerRadius: KiteRadius.button, style: .continuous)
                    .fill(KiteColor.fill)
                    .opacity(enabled ? 1 : 0.45)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/** A 44×44 (or larger) circle button: map FABs, sheet close buttons. */
struct KiteCircleButton: View {
    let icon: String
    var tint: Color = KiteColor.ink
    var size: CGFloat = 44
    /// Map controls float over the map and need the frosted backing; sheet
    /// controls sit on a solid surface and only need the fill.
    var material = false
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(material ? KiteColor.surface.opacity(0.94) : KiteColor.fill)
                        .overlay(Circle().strokeBorder(KiteColor.strokeStrong, lineWidth: 0.75))
                        .shadow(color: material ? KiteElevation.low.color : .clear,
                                radius: material ? KiteElevation.low.radius : 0,
                                y: material ? KiteElevation.low.y : 0)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? icon)
    }
}

/** A small pill: filters, facts, status. */
struct KiteChip: View {
    let text: String
    var icon: String?
    var selected = false
    var tint: Color = KiteColor.accentText

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
            Text(text).font(KiteText.label(14)).lineLimit(1)
        }
        .foregroundColor(selected ? KiteColor.onTonal : KiteColor.inkSecondary)
        .padding(.horizontal, KiteSpace.s)
        .frame(height: 34)
        .background(Capsule().fill(selected ? KiteColor.accentSoft : KiteColor.fill))
        .overlay(Capsule().strokeBorder(selected ? tint.opacity(0.55) : .clear, lineWidth: 1))
    }
}

extension KiteColor {
    /// Text on a soft teal chip.
    static let onTonal = accentText
}

/** Sheet grabber. The only drag indicator used by Kite's own sheets. */
struct KiteGrabber: View {
    var body: some View {
        Capsule()
            .fill(KiteColor.inkSecondary.opacity(0.4))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }
}

/** Section heading with an optional trailing action. */
struct KiteSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title)).font(KiteText.headline(17)).foregroundColor(KiteColor.ink)
                if let subtitle {
                    Text(L10n.text(subtitle)).font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary)
                }
            }
            Spacer(minLength: KiteSpace.xs)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(L10n.text(actionTitle)).font(KiteText.label(14)).foregroundColor(KiteColor.accentText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/** Empty states share one shape so they do not look like errors. */
struct KiteEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: KiteSpace.s) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(KiteColor.accentText)
                .frame(width: 64, height: 64)
                .background(Circle().fill(KiteColor.accentSoft))
            Text(L10n.text(title)).font(KiteText.headline()).foregroundColor(KiteColor.ink)
            Text(L10n.text(detail))
                .font(KiteText.body(15)).foregroundColor(KiteColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) { Text(L10n.text(actionTitle)) }
                    .buttonStyle(KiteSecondaryButtonStyle(height: 46))
                    .frame(maxWidth: 260)
                    .padding(.top, KiteSpace.xxs)
            }
        }
        .padding(KiteSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

/** Respects Reduce Motion for every new transition. */
struct KiteMotionReader<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @ViewBuilder var content: (Bool) -> Content

    var body: some View { content(reduce) }
}
