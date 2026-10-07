import SwiftUI

struct StatsView: View {
    @Environment(StatsStore.self) private var stats
    @State private var confirmReset = false
    @State private var shown: Problem?

    var body: some View {
        List {
            Section("요약") {
                LabeledContent("푼 문제", value: "\(stats.totalAnswered)개")
                LabeledContent("전체 정답률", value: overallAccuracy)
                LabeledContent("타임어택 최고", value: "\(stats.bestTimeAttack)개")
            }

            Section("유형별") {
                ForEach(Problem.Kind.allCases, id: \.self) { kind in
                    let summary = stats.summary(of: kind)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(kind.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let avg = summary.averageTime {
                                Label(String(format: "평균 %.1f초", avg), systemImage: "stopwatch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let acc = summary.accuracy {
                            HStack(spacing: 12) {
                                ProgressView(value: acc).tint(color(for: acc))
                                Text("\(Int((acc * 100).rounded()))%")
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .trailing)
                            }
                        } else {
                            Text("아직 기록 없음").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("자주 틀리는 문제") {
                let weak = Array(stats.weakProblems.prefix(10))
                if weak.isEmpty {
                    Text("없어요! 👏").foregroundStyle(.secondary)
                }
                ForEach(weak) { p in
                    let r = stats.records[p.id] ?? .init()
                    Button {
                        shown = p
                    } label: {
                        HStack {
                            Text("\(p.text) = \(p.answer)")
                                .font(.system(.body, design: .rounded).bold())
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Text("✗ \(r.wrong)  ✓ \(r.correct)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("기록 초기화", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("내 기록")
        .sheet(item: $shown) { p in
            HandCalcSheet(problem: p)
        }
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
