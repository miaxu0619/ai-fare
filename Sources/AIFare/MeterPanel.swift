import SwiftUI

struct MeterPanel: View {
    @EnvironmentObject private var store: FareStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AI FARE", systemImage: "taxi")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Circle().fill(store.isMetering ? .green : .gray).frame(width: 7, height: 7)
                Text(store.isMetering ? "计价中" : "待命")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .buttonStyle(.plain)
                .help("退出 AI Fare")
            }

            Text(store.sessionFareText)
                .font(.system(size: 42, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.70, blue: 0.22))
                .contentTransition(.numericText())
                .shadow(color: .orange.opacity(0.45), radius: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.snapshot.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text("\(store.snapshot.model) · \(store.quotaText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Plus ¥144 / 月 × 本周额度消耗；本次按今日 Token 占比拆分。")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                    if let error = store.readError {
                        Text(error).font(.system(size: 10)).foregroundStyle(.red.opacity(0.9))
                    }
                }
                Spacer(minLength: 4)
                Button("← 返回计价器") { withAnimation(.snappy) { expanded = false } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.70, blue: 0.22))
            } else {
                Text(store.activeDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))

                Divider().overlay(.white.opacity(0.13))

                HStack(spacing: 18) {
                    Metric(label: "本次 TOKEN", value: store.tokenText)
                    Metric(label: "套餐分摊", value: store.weeklyFareText)
                }

                Button("查看明细") { withAnimation(.snappy) { expanded = true } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.70, blue: 0.22))
            }
        }
        .padding(16)
        .frame(width: 300, height: 228, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.055, green: 0.065, blue: 0.085).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.42))
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
        }
    }
}
