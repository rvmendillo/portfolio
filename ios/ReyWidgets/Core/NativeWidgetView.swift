import SwiftUI

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x12192C
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct NativeWidgetView: View {
    let design: NativeDesign
    let data: Data
    var compact = false
    var large = false
    var status: String?
    var reserveActionSpace = false
    private func resolve(_ text: String) -> String { Bindings.render(text, data: data) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 6) {
                Image(systemName: design.symbol).foregroundStyle(Color(hex: design.accent))
                Text(resolve(design.title)).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.2).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.trailing, reserveActionSpace ? 30 : 0)
            Spacer(minLength: 0)
            switch design.layout {
            case .metric:
                Text(resolve(design.value)).font(.system(size: compact ? 28 : 36, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.35).lineLimit(2).foregroundStyle(Color(hex: design.accent))
                Text(resolve(design.subtitle)).font(.system(size: 12)).lineLimit(compact ? 2 : 3).opacity(0.75)
            case .clock:
                Text(Date(), style: .time).font(.system(size: compact ? 32 : 46, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.4).lineLimit(1).foregroundStyle(Color(hex: design.accent))
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.system(size: 12)).opacity(0.75)
            case .list:
                ForEach(Array(design.rows.prefix(large ? 7 : 3).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color(hex: design.accent)).frame(width: 5, height: 5).padding(.top, 5)
                        Text(resolve(row)).font(.system(size: 13, weight: .medium)).lineLimit(large ? 2 : 1)
                    }
                }
            case .progress:
                Text(resolve(design.value)).font(.system(size: compact ? 27 : 34, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.4).lineLimit(1).foregroundStyle(Color(hex: design.accent))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color(hex: design.accent)).frame(width: proxy.size.width * min(1, max(0, design.progress)))
                    }
                }.frame(height: 6)
                Text(resolve(design.subtitle)).font(.system(size: 12)).lineLimit(2).opacity(0.75)
            }
            Spacer(minLength: 0)
            Text(status ?? resolve(design.footer)).font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1).opacity(0.5)
        }
        .padding(compact ? 16 : 20)
        .foregroundStyle(Color(hex: design.foreground))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(hex: design.background))
        .accessibilityElement(children: .combine)
    }
}
