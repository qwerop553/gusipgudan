import SwiftUI

struct StatsView: View {
    @Environment(StatsStore.self) private var stats
    @State private var confirmReset = false

    var body: some View {
        List {
            Section("요약") {
                LabeledContent("푼 문제", value: "\(stats.totalAnswered)개")
                LabeledContent("전체 정답률", value: overallAccuracy)
                LabeledContent("타임어택 최고", value: "\(stats.bestTimeAttack)개")
            }

            Section("단별 정답률") {
                ForEach(2...9, id: \.self) { dan in
                    HStack(spacing: 12) {
                        Text("\(dan)단")
                            .frame(width: 40, alignment: .leading)
                        if let acc = stats.accuracy(dan: dan) {
                            ProgressView(value: acc)
                                .tint(color(for: acc))
                            Text("\(Int((acc * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        } else {
                            Text("아직 기록 없음").foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }

            Section("자주 틀리는 문제") {
                let weak = Array(stats.weakProblems.prefix(10))
                if weak.isEmpty {
                    Text("없어요! 👏").foregroundStyle(.secondary)
                }
                ForEach(weak) { p in
                    let r = stats.records[p.id] ?? .init()
                    HStack {
                        Text("\(p.text) = \(p.answer)")
                            .font(.system(.body, design: .rounded).bold())
                        Spacer()
                        Text("✗ \(r.wrong)  ✓ \(r.correct)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("기록 초기화", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("내 기록")
        .confirmationDialog("모든 기록을 지울까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("초기화", role: .destructive) { stats.reset() }
        }
    }

    private var overallAccuracy: String {
        guard stats.totalAnswered > 0 else { return "-" }
        return "\(Int((Double(stats.totalCorrect) / Double(stats.totalAnswered) * 100).rounded()))%"
    }

    private func color(for accuracy: Double) -> Color {
        accuracy >= 0.9 ? .green : accuracy >= 0.7 ? .orange : .red
    }
}

#Preview {
    NavigationStack { StatsView() }.environment(StatsStore())
}
