import SwiftUI

enum Route: Hashable {
    case quiz(QuizConfig)
    case table
    case stats
}

struct HomeView: View {
    @Environment(StatsStore.self) private var stats
    @AppStorage("level") private var level: Level = .twoByTwo
    @AppStorage("customAMin") private var customAMin = 11
    @AppStorage("customAMax") private var customAMax = 99
    @AppStorage("customBMin") private var customBMin = 11
    @AppStorage("customBMax") private var customBMax = 19
    @State private var path: [Route] = []

    private var ranges: (a: ClosedRange<Int>, b: ClosedRange<Int>) {
        level.ranges ?? (
            min(customAMin, customAMax)...max(customAMin, customAMax),
            min(customBMin, customBMax)...max(customBMin, customBMax)
        )
    }

    private func config(_ mode: QuizMode) -> QuizConfig {
        QuizConfig(aRange: ranges.a, bRange: ranges.b, mode: mode)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    levelPicker
                    modes
                    more
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("99단")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .quiz(let config): QuizView(config: config)
                case .table: TableView()
                case .stats: StatsView()
                }
            }
        }
    }

    // MARK: - 범위 선택

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("범위").font(.title3.bold())

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Level.allCases) { item in
                    let isOn = level == item
                    Button {
                        level = item
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.system(.headline, design: .rounded))
                            Text(rangeText(item))
                                .font(.caption.monospacedDigit())
                                .opacity(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(
                            isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(PressStyle())
                    .sensoryFeedback(.selection, trigger: isOn)
                }
            }

            if level == .custom {
                VStack(spacing: 4) {
                    RangeStepper(title: "앞 수", low: $customAMin, high: $customAMax)
                    Divider()
                    RangeStepper(title: "뒤 수", low: $customBMin, high: $customBMax)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .animation(.snappy, value: level)
    }

    private func rangeText(_ item: Level) -> String {
        let r = item.ranges ?? ranges
        return "\(r.a.lowerBound)~\(r.a.upperBound) × \(r.b.lowerBound)~\(r.b.upperBound)"
    }

    // MARK: - 모드

    private var modes: some View {
        VStack(spacing: 12) {
            let weakCount = stats.weakProblems.count

            NavigationLink(value: Route.quiz(config(.practice))) {
                ModeCard(
                    title: "연습하기",
                    subtitle: "\(QuizMode.practiceCount)문제 · 모르면 💡 풀이 보기",
                    systemImage: "pencil",
                    tint: .blue
                )
            }

            NavigationLink(value: Route.quiz(config(.timeAttack))) {
                ModeCard(
                    title: "타임어택",
                    subtitle: "\(QuizMode.timeAttackSeconds / 60)분 도전 · 최고 기록 \(stats.bestTimeAttack)개",
                    systemImage: "timer",
                    tint: .orange
                )
            }

            NavigationLink(value: Route.quiz(config(.review))) {
                ModeCard(
                    title: "오답 집중",
                    subtitle: weakCount == 0 ? "약한 문제가 없어요 👏" : "틀리거나 풀이 본 문제 \(weakCount)개 복습",
                    systemImage: "exclamationmark.arrow.circlepath",
                    tint: .red
                )
            }
            .disabled(weakCount == 0)
        }
        .buttonStyle(PressStyle())
    }

    private var more: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.table) {
                SmallCard(title: "곱셈표", systemImage: "tablecells")
            }
            NavigationLink(value: Route.stats) {
                SmallCard(title: "내 기록", systemImage: "chart.bar.xaxis")
            }
        }
        .buttonStyle(PressStyle())
    }
}

struct RangeStepper: View {
    let title: String
    @Binding var low: Int
    @Binding var high: Int

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).frame(width: 44, alignment: .leading)
            Stepper("\(low)", value: $low, in: 2...99).fixedSize()
            Spacer()
            Text("~").foregroundStyle(.secondary)
            Spacer()
            Stepper("\(high)", value: $high, in: 2...99).fixedSize()
        }
        .font(.body.monospacedDigit())
    }
}

// MARK: - Components

struct ModeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct SmallCard: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    HomeView().environment(StatsStore())
}
