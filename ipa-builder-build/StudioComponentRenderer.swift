import SwiftUI

struct StudioComponentRenderer: View {
    let component: StudioComponent

    @State private var input = ""
    @State private var toggle = true
    @State private var value = 0.5
    @State private var count = 1
    @State private var choice = "One"
    @State private var date = Date()
    @State private var tint = Color.indigo

    var body: some View {
        Group {
            switch component.kind {
            case .text:
                Text(component.text)
                    .font(.system(size: component.fontSize, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .button:
                Text(component.text)
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        .indigo.gradient,
                        in: RoundedRectangle(cornerRadius: component.cornerRadius)
                    )
                    .foregroundStyle(.white)

            case .textField:
                TextField(component.text, text: $input)
                    .textFieldStyle(.roundedBorder)

            case .secureField:
                SecureField(component.text, text: $input)
                    .textFieldStyle(.roundedBorder)

            case .textEditor:
                TextEditor(text: $input)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    }
                    .overlay(alignment: .topLeading) {
                        if input.isEmpty {
                            Text(component.text)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }

            case .image:
                Image(systemName: component.text.isEmpty ? "photo" : component.text)
                    .resizable()
                    .scaledToFit()
                    .padding(8)

            case .symbol:
                Image(systemName: component.text.isEmpty ? "sparkles" : component.text)
                    .font(.system(size: min(component.width, component.height) * 0.48))
                    .foregroundStyle(.indigo)

            case .label:
                Label(
                    component.text,
                    systemImage: component.detail.isEmpty ? "star.fill" : component.detail
                )

            case .toggle:
                Toggle(component.text, isOn: $toggle)

            case .slider:
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.text).font(.caption)
                    Slider(value: $value)
                }

            case .stepper:
                Stepper("\(component.text): \(count)", value: $count)

            case .picker:
                Picker(component.text, selection: $choice) {
                    ForEach(component.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

            case .datePicker:
                DatePicker(component.text, selection: $date)

            case .colorPicker:
                ColorPicker(component.text, selection: $tint)

            case .progress:
                VStack(spacing: 8) {
                    ProgressView(value: component.value)
                    Text(component.text).font(.caption)
                }

            case .gauge:
                Gauge(value: component.value) {
                    Text(component.text)
                }
                .gaugeStyle(.accessoryCircular)

            case .divider:
                Divider()

            case .spacer:
                Label("Spacer", systemImage: "arrow.up.and.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 6)
                    )

            case .link:
                Label(component.text, systemImage: "link")
                    .foregroundStyle(.indigo)

            case .menu:
                Menu(component.text) {
                    Button("Option 1") {}
                    Button("Option 2") {}
                }

            case .navigationLink:
                HStack {
                    Text(component.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.horizontal, 10)

            case .list:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...4, id: \.self) { index in
                        HStack {
                            Image(systemName: "circle.fill").font(.caption2)
                            Text("\(component.text) \(index)")
                            Spacer()
                        }
                        .padding(8)
                        Divider()
                    }
                }
                .background(
                    .quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            case .scrollView:
                ScrollView {
                    VStack {
                        ForEach(1...6, id: \.self) { index in
                            Text("Scrollable item \(index)")
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(
                                    .quaternary,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                    }
                }

            case .vStack:
                VStack(spacing: 6) {
                    Text(component.text.isEmpty ? "VStack" : component.text)
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .padding(8)
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(.quaternary)
                }

            case .hStack:
                HStack(spacing: 6) {
                    Text(component.text.isEmpty ? "HStack" : component.text)
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .padding(8)
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(.quaternary)
                }

            case .zStack:
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.indigo.opacity(0.12))
                    Circle()
                        .fill(.indigo.opacity(0.25))
                        .padding(20)
                    Text(component.text.isEmpty ? "ZStack" : component.text)
                }

            case .form:
                VStack(alignment: .leading) {
                    Text(component.text.isEmpty ? "Form" : component.text)
                        .font(.headline)
                    TextField("Field", text: $input)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Option", isOn: $toggle)
                }
                .padding(10)
                .background(
                    .quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            case .section:
                VStack(alignment: .leading) {
                    Text(component.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("Section content")
                }
                .padding(10)
                .background(
                    .quaternary.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            case .capsule:
                Capsule()
                    .fill(.indigo.opacity(0.18))
                    .overlay { Text(component.text) }

            case .roundedRectangle:
                RoundedRectangle(cornerRadius: component.cornerRadius)
                    .fill(.indigo.opacity(0.16))
                    .overlay { Text(component.text) }

            case .circle:
                Circle()
                    .fill(.indigo.opacity(0.18))
                    .overlay { Text(component.text).font(.caption) }

            case .webView:
                VStack(spacing: 5) {
                    Image(systemName: "safari").font(.largeTitle)
                    Text(component.detail.isEmpty ? "https://apple.com" : component.detail)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    .quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            case .map:
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary.opacity(0.35))
                    VStack(spacing: 5) {
                        Image(systemName: "map.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.indigo)
                        Text(component.detail.isEmpty ? "Map" : component.detail)
                            .font(.caption)
                    }
                }

            case .shareLink:
                Label(component.text, systemImage: "square.and.arrow.up")
                    .padding(8)
                    .background(.quaternary, in: Capsule())
            }
        }
        .clipped()
    }
}
