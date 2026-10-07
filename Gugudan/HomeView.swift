import SwiftUI

enum Route: Hashable {
    case quiz(QuizConfig)
    case table
    case stats
}

struct HomeView: View {
    @Environment(StatsStore.self) private var stats
    @AppStorage("selectedDans") private var selectedRaw = "2,3,4,5,6,7,8,9"
    @State private var path: [Route] = []

    private var selected: [Int] {
        selectedRaw.split(separator: ",").compactMap { Int($0) }.sorted()
    }

    private func setSelected(_ dans: Set<Int>) {
        selectedRaw = dans.sorted().map(String.init).joined(separator: ",")
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    danPicker
                    modes
                    more
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("구구단")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .quiz(let config): QuizView(config: config)
                case .table: TableView()
                case .stats: StatsView()
                }
            }
        }
    }

    // MARK: - 단 선택

    private var danPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("단 선택").font(.title3.bold())
                Spacer()
                Button(selected.count == 8 ? "모두 해제" : "전체 선택") {
                    setSelected(selected.count == 8 ? [] : Set(2...9))
                }
                .font(.subheadline.weight(.semibold))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(2...9, id: \.self) { dan in
                    let isOn = selected.contains(dan)
                    Button {
                        var s = Set(selected)
                        if isOn { s.remove(dan) } else { s.insert(dan) }
                        setSelected(s)
                    } label: {
                        Text("\(dan)단")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
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
        }
    }

    // MARK: - 모드

    private var modes: some View {
        VStack(spacing: 12) {
            let noDans = selected.isEmpty
            let weakCount = stats.weakProblems.count

            NavigationLink(value: Route.quiz(QuizConfig(dans: selected, mode: .practice))) {
                ModeCard(
                    title: "연습하기",
                    subtitle: "\(QuizMode.practiceCount)문제 · 틀린 문제는 더 자주 나와요",
                    systemImage: "pencil",
                    tint: .blue
                )
            }
            .disabled(noDans)

            NavigationLink(value: Route.quiz(QuizConfig(dans: selected, mode: .timeAttack))) {
                ModeCard(
                    title: "타임어택",
                    subtitle: "\(QuizMode.timeAttackSeconds)초 도전 · 최고 기록 \(stats.bestTimeAttack)개",
                    systemImage: "timer",
                    tint: .orange
                )
            }
            .disabled(noDans)

            NavigationLink(value: Route.quiz(QuizConfig(dans: [], mode: .review))) {
                ModeCard(
                    title: "오답 집중",
                    subtitle: weakCount == 0 ? "약한 문제가 없어요 👏" : "약한 문제 \(weakCount)개 복습",
                    systemImage: "exclamationmark.arrow.circlepath",
                    tint: .red
                )
            }
            .disabled(weakCount == 0)

            if noDans {
                Text("연습할 단을 하나 이상 골라주세요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var more: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.table) {
                SmallCard(title: "구구단표", systemImage: "tablecells")
            }
            NavigationLink(value: Route.stats) {
                SmallCard(title: "내 기록", systemImage: "chart.bar.xaxis")
            }
        }
        .buttonStyle(PressStyle())
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
