import SwiftUI
import UIKit
import VelaCore

struct MapPaletteView: View {
    @ObservedObject var settings: AppSettings
    @State private var dark = false

    private var palette: Binding<MapPalette> {
        dark ? $settings.nightMapPalette : $settings.dayMapPalette
    }

    var body: some View {
        Form {
            Picker("Lighting", selection: $dark) {
                Text("Day").tag(false)
                Text("Night").tag(true)
            }.pickerStyle(.segmented)

            Section("Presets") {
                ForEach(MapPalette.presets(dark: dark)) { preset in
                    Button {
                        palette.wrappedValue = preset.palette
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            ForEach(MapPaletteField.allCases) { field in
                                Circle().fill(Color(hex: preset.palette[field])).frame(width: 12, height: 12)
                            }
                            if palette.wrappedValue == preset.palette {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(palette.wrappedValue == preset.palette ? .isSelected : [])
                }
            }

            Section("Map colors") {
                ForEach(MapPaletteField.allCases) { field in
                    ColorPicker(field.title, selection: Binding(
                        get: { Color(hex: palette.wrappedValue[field]) },
                        set: { color in
                            guard let rgb = Self.rgb(color) else { return }
                            palette.wrappedValue[field] = rgb
                        }), supportsOpacity: false)
                }
            }

            Section("App colors") {
                optionalPicker("Accent", value: $settings.mapUIAccent, fallback: 0x14B8A6)
                optionalPicker("Day panels", value: $settings.mapUIDayPanel, fallback: 0xFFFFFF)
                optionalPicker("Night panels", value: $settings.mapUINightPanel, fallback: 0x151F30)
                Button("Reset app colors") {
                    settings.mapUIAccent = nil
                    settings.mapUIDayPanel = nil
                    settings.mapUINightPanel = nil
                }
            }
        }
        .navigationTitle("Colors")
        .kiteList()
    }

    private func optionalPicker(_ title: String, value: Binding<UInt32?>, fallback: UInt32) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(hex: value.wrappedValue ?? fallback) },
            set: { color in if let rgb = Self.rgb(color) { value.wrappedValue = rgb } }
        ), supportsOpacity: false)
    }

    private static func rgb(_ color: Color) -> UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ channel: CGFloat) -> UInt32 { UInt32((max(0, min(channel, 1)) * 255).rounded()) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}
