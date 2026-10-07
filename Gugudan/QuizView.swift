import SwiftUI
import UIKit

struct QuizView: View {
    let config: QuizConfig

    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss

    enum Feedback: Equatable {
        case none
        case correct
        case wrong(Int)
    }

    @State private var picker: ProblemPicker?
    @State private var current: Problem?
    @State private var input = ""
    @State private var feedback: Feedback = .none
    @State private var questionCount: Int?   // 타임어택은 nil
    @State private var answered = 0
    @State private var correct = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var mistakes: [Problem] = []
    @State private var remaining = QuizMode.timeAttackSeconds
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var finished = false
    @State private var isNewRecord = false
    @State private var round = 0
    @State private var shakes: CGFloat = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if finished {
                ResultView(
                    mode: config.mode,
                    answered: answered,
                    correct: correct,
                    bestStreak: bestStreak,
                    elapsed: endDate.timeIntervalSince(startDate),
                    mistakes: mistakes,
                    isNewRecord: isNewRecord,
                    best: stats.bestTimeAttack,
                    onRetry: start,
                    onHome: { dismiss() }
                )
            } else if let current {
                quiz(current)
            } else {
                ContentUnavailableView("풀 문제가 없어요", systemImage: "checkmark.seal")
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(config.mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if picker == nil { start() } }
        .onReceive(timer) { _ in tick() }
    }

    // MARK: - 문제 화면

    private func quiz(_ problem: Problem) -> some View {
        VStack(spacing: 20) {
            header
            Spacer(minLength: 0)
            card(problem)
            Spacer(minLength: 0)
            Keypad(
                canSubmit: !input.isEmpty && feedback == .none,
                onDigit: typeDigit,
                onDelete: { if feedback == .none, !input.isEmpty { input.removeLast() } },
                onSubmit: submit
            )
        }
        .padding()
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                if let questionCount {
                    Text("\(min(answered + 1, questionCount)) / \(questionCount)")
                        .font(.headline.monospacedDigit())
                } else {
                    Label("\(remaining)초", systemImage: "timer")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(remaining <= 10 ? Color.red : Color.primary)
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                if streak >= 3 {
                    Label("\(streak)연속", systemImage: "flame.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                        .transition(.scale.combined(with: .opacity))
                }
                Label("\(correct)", systemImage: "checkmark.circle.fill")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
            }
            ProgressView(value: progress)
                .tint(questionCount == nil ? Color.orange : Color.accentColor)
                .animation(.linear, value: progress)
        }
        .animation(.spring, value: streak >= 3)
    }

    private var progress: Double {
        if let questionCount {
            return Double(answered) / Double(questionCount)
        }
        return Double(remaining) / Double(QuizMode.timeAttackSeconds)
    }

    private func card(_ problem: Problem) -> some View {
        VStack(spacing: 8) {
            Text(problem.text)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(input.isEmpty ? "?" : input)
                .font(.system(size: 60, weight: .semibold, design: .rounded))
                .foregroundStyle(answerColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: input)
            Group {
                switch feedback {
                case .wrong(let answer): Text("정답은 \(answer)")
                case .correct: Text("정답!")
                case .none: Text(" ")
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(feedback == .correct ? Color.green : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(Shake(animatableData: shakes))
        .animation(.easeOut(duration: 0.15), value: feedback)
    }

    private var answerColor: Color {
        switch feedback {
        case .none: input.isEmpty ? .secondary : .accentColor
        case .correct: .green
        case .wrong: .red
        }
    }

    private var cardBackground: Color {
        switch feedback {
        case .none: Color(.secondarySystemGroupedBackground)
        case .correct: Color.green.opacity(0.15)
        case .wrong: Color.red.opacity(0.15)
        }
    }

    // MARK: - 로직

    private func start() {
        let pool: [Problem]
        switch config.mode {
        case .practice, .timeAttack:
            pool = Problem.all(dans: config.dans)
        case .review:
            pool = stats.weakProblems
        }
        switch config.mode {
        case .practice: questionCount = QuizMode.practiceCount
        case .timeAttack: questionCount = nil
        case .review: questionCount = min(30, max(10, pool.count * 2))
        }

        round += 1
        var newPicker = ProblemPicker(pool: pool, stats: stats)
        current = newPicker.next()
        picker = newPicker
        input = ""
        feedback = .none
        answered = 0
        correct = 0
        streak = 0
        bestStreak = 0
        mistakes = []
        remaining = QuizMode.timeAttackSeconds
        startDate = Date()
        isNewRecord = false
        finished = false
    }

    private func typeDigit(_ digit: Int) {
        guard feedback == .none, input.count < 2 else { return }
        if input.isEmpty && digit == 0 { return }
        input.append(String(digit))
    }

    private func submit() {
        guard let problem = current, feedback == .none, let value = Int(input) else { return }
        let isCorrect = value == problem.answer
        stats.record(problem, correct: isCorrect)
        answered += 1

        if isCorrect {
            correct += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            feedback = .correct
            Haptics.notify(.success)
        } else {
            streak = 0
            mistakes.append(problem)
            feedback = .wrong(problem.answer)
            Haptics.notify(.error)
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        }

        let thisRound = round
        Task {
            try? await Task.sleep(for: .seconds(isCorrect ? 0.4 : 1.4))
            guard thisRound == round, !finished else { return }
            advance()
        }
    }

    private func advance() {
        input = ""
        feedback = .none
        if let questionCount, answered >= questionCount {
            finish()
        } else {
            current = picker?.next()
        }
    }

    private func tick() {
        guard config.mode == .timeAttack, !finished, current != nil else { return }
        withAnimation { remaining -= 1 }
        if remaining <= 0 { finish() }
    }

    private func finish() {
        guard !finished else { return }
        endDate = Date()
        if config.mode == .timeAttack {
            isNewRecord = stats.submitTimeAttack(score: correct)
        }
        finished = true
        Haptics.notify(.success)
    }
}

// MARK: - 키패드

struct Keypad: View {
    let canSubmit: Bool
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { n in digit(n) }
                }
            }
            GridRow {
                key(fill: Color(.tertiarySystemFill), action: onDelete) {
                    Image(systemName: "delete.left")
                }
                digit(0)
                key(fill: canSubmit ? Color.accentColor : Color.accentColor.opacity(0.35), action: onSubmit) {
                    Image(systemName: "checkmark").foregroundStyle(.white)
                }
            }
        }
    }

    private func digit(_ n: Int) -> some View {
        key(fill: Color(.secondarySystemGroupedBackground), action: { onDigit(n) }) {
            Text("\(n)")
        }
    }

    private func key<Content: View>(fill: Color, action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label()
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 결과

struct ResultView: View {
    let mode: QuizMode
    let answered: Int
    let correct: Int
    let bestStreak: Int
    let elapsed: TimeInterval
    let mistakes: [Problem]
    let isNewRecord: Bool
    let best: Int
    let onRetry: () -> Void
    let onHome: () -> Void

    private var accuracy: Double {
        answered == 0 ? 0 : Double(correct) / Double(answered)
    }

    private var uniqueMistakes: [Problem] {
        var seen = Set<Problem>()
        return mistakes.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(accuracy >= 0.9 ? "🏆" : accuracy >= 0.7 ? "👍" : "💪")
                        .font(.system(size: 80))
                    Text(mode == .timeAttack ? "\(correct)개 맞혔어요!" : "\(answered)문제 중 \(correct)개 정답")
                        .font(.title.bold())
                    if isNewRecord {
                        Text("🎉 신기록!")
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 24)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(title: "정답률", value: "\(Int((accuracy * 100).rounded()))%")
                        StatTile(title: "최고 연속", value: "\(bestStreak)")
                    }
                    GridRow {
                        if mode == .timeAttack {
                            StatTile(title: "최고 기록", value: "\(best)개")
                        } else {
                            StatTile(title: "걸린 시간", value: timeString)
                        }
                        StatTile(title: "틀린 문제", value: "\(mistakes.count)")
                    }
                }

                if !uniqueMistakes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("다시 보기").font(.headline)
                        ForEach(uniqueMistakes) { p in
                            HStack {
                                Text(p.text)
                                Spacer()
                                Text("\(p.answer)").bold()
                            }
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label("다시 하기", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))

                    Button(action: onHome) {
                        Text("처음으로")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                }
            }
            .padding()
        }
    }

    private var timeString: String {
        let s = Int(elapsed.rounded())
        return s >= 60 ? "\(s / 60)분 \(s % 60)초" : "\(s)초"
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.system(.title, design: .rounded).bold())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Helpers

struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

enum Haptics {
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
