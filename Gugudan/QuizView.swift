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
        case revealed   // 풀이 보기
    }

    @State private var picker: ProblemPicker?
    @State private var current: Problem?
    @State private var input = ""
    @State private var feedback: Feedback = .none
    @State private var questionCount: Int?   // 타임어택은 nil
    @State private var answered = 0
    @State private var correct = 0
    @State private var correctTime: Double = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var mistakes: [Problem] = []
    @State private var remaining = QuizMode.timeAttackSeconds
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var questionStart = Date()
    @State private var finished = false
    @State private var isNewRecord = false
    @State private var step = 0   // 예약된 자동 넘김을 취소하기 위한 토큰
    @State private var shakes: CGFloat = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if finished {
                ResultView(
                    mode: config.mode,
                    answered: answered,
                    correct: correct,
                    averageTime: correct == 0 ? nil : correctTime / Double(correct),
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
        VStack(spacing: 16) {
            header
            Spacer(minLength: 0)
            card(problem)
            if feedback == .none || isWrong {
                Button(action: reveal) {
                    Label("풀이 보기", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.orange)
            }
            Spacer(minLength: 0)
            if feedback == .revealed {
                Button(action: advance) {
                    Label("다음 문제", systemImage: "arrow.right")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            } else {
                Keypad(
                    canSubmit: !input.isEmpty && feedback == .none,
                    onDigit: typeDigit,
                    onDelete: { if feedback == .none, !input.isEmpty { input.removeLast() } },
                    onSubmit: submit
                )
            }
        }
        .padding()
    }

    private var isWrong: Bool {
        if case .wrong = feedback { return true }
        return false
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                if let questionCount {
                    Text("\(min(answered + 1, questionCount)) / \(questionCount)")
                        .font(.headline.monospacedDigit())
                } else {
                    Label(timeLeftString, systemImage: "timer")
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

    private var timeLeftString: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var progress: Double {
        if let questionCount {
            return Double(answered) / Double(questionCount)
        }
        return Double(remaining) / Double(QuizMode.timeAttackSeconds)
    }

    @ViewBuilder
    private func card(_ problem: Problem) -> some View {
        Group {
            if feedback == .revealed {
                HandCalcView(calc: HandCalc(problem))
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    Text(problem.text)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(input.isEmpty ? "?" : input)
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .foregroundStyle(answerColor)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: input)
                    Group {
                        switch feedback {
                        case .wrong(let answer): Text("정답은 \(answer)")
                        case .correct: Text("정답!")
                        case .none, .revealed: Text(" ")
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(feedback == .correct ? Color.green : Color.red)
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(Shake(animatableData: shakes))
        .animation(.easeOut(duration: 0.15), value: feedback)
    }

    private var answerColor: Color {
        switch feedback {
        case .none: input.isEmpty ? .secondary : .accentColor
        case .correct: .green
        case .wrong, .revealed: .red
        }
    }

    private var cardBackground: Color {
        switch feedback {
        case .none, .revealed: Color(.secondarySystemGroupedBackground)
        case .correct: Color.green.opacity(0.15)
        case .wrong: Color.red.opacity(0.15)
        }
    }

    // MARK: - 로직

    private func start() {
        let pool: ProblemPicker.Pool
        switch config.mode {
        case .practice:
            pool = .ranges(config.aRange, config.bRange)
            questionCount = QuizMode.practiceCount
        case .timeAttack:
            pool = .ranges(config.aRange, config.bRange)
            questionCount = nil
        case .review:
            let weak = stats.weakProblems
            pool = .list(weak)
            questionCount = min(30, max(10, weak.count * 2))
        }

        step += 1
        var newPicker = ProblemPicker(pool: pool, stats: stats)
        current = newPicker.next()
        picker = newPicker
        input = ""
        feedback = .none
        answered = 0
        correct = 0
        correctTime = 0
        streak = 0
        bestStreak = 0
        mistakes = []
        remaining = QuizMode.timeAttackSeconds
        startDate = Date()
        questionStart = Date()
        isNewRecord = false
        finished = false
    }

    private func typeDigit(_ digit: Int) {
        guard feedback == .none, input.count < 4 else { return }
        if input.isEmpty && digit == 0 { return }
        input.append(String(digit))
    }

    private func submit() {
        guard let problem = current, feedback == .none, let value = Int(input) else { return }
        let isCorrect = value == problem.answer
        let time = Date().timeIntervalSince(questionStart)
        stats.record(problem, correct: isCorrect, time: time)
        answered += 1

        if isCorrect {
            correct += 1
            correctTime += time
            streak += 1
            bestStreak = max(bestStreak, streak)
            feedback = .correct
            Haptics.notify(.success)
        } else {
            missed(problem)
            feedback = .wrong(problem.answer)
            Haptics.notify(.error)
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        }

        let thisStep = step
        Task {
            try? await Task.sleep(for: .seconds(isCorrect ? 0.4 : 1.6))
            guard thisStep == step, !finished else { return }
            advance()
        }
    }

    /// 손계산 풀이 보기. 아직 답을 안 냈으면 틀린 것으로 기록한다.
    private func reveal() {
        guard let problem = current, feedback == .none || isWrong else { return }
        if feedback == .none {
            stats.record(problem, correct: false, time: 0)
            answered += 1
            missed(problem)
        }
        step += 1   // 오답 후 자동 넘김 취소
        input = ""
        feedback = .revealed
        Haptics.tap()
    }

    private func missed(_ problem: Problem) {
        streak = 0
        mistakes.append(problem)
    }

    private func advance() {
        step += 1
        input = ""
        feedback = .none
        if let questionCount, answered >= questionCount {
            finish()
        } else {
            current = picker?.next()
            questionStart = Date()
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

// MARK: - 손계산(세로셈) 풀이

struct HandCalcView: View {
    let calc: HandCalc

    private let font = Font.system(size: 30, weight: .semibold, design: .monospaced)

    var body: some View {
        VStack(spacing: 16) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(Array(calc.lines.enumerated()), id: \.offset) { index, line in
                    switch line {
                    case .rule:
                        GridRow {
                            Text(String(repeating: " ", count: calc.width + 2))
                                .font(font)
                                .frame(height: 6)
                                .overlay(Rectangle().fill(Color.secondary).frame(height: 2))
                            Color.clear.frame(width: 0, height: 0)
                        }
                    case .row(let row):
                        let isResult = index == calc.lines.count - 1
                        GridRow {
                            rowText(row)
                                .font(font)
                                .foregroundStyle(isResult ? Color.accentColor : Color.primary)
                                .gridColumnAlignment(.trailing)
                            Text(row.note ?? "")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
            }
            .fixedSize()

            if let mental = calc.mental {
                VStack(spacing: 4) {
                    Text("암산 팁").font(.caption.bold()).foregroundStyle(.orange)
                    Text(mental)
                        .font(.system(.callout, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 앞쪽 기호 + 오른쪽 정렬된 숫자 + 자리 올림 표시(흐린 0)
    private func rowText(_ row: HandCalc.Row) -> Text {
        let pad = String(repeating: " ", count: max(0, calc.width - row.digits.count - row.shift))
        let prefix = row.prefix.isEmpty ? " " : row.prefix
        return Text(prefix + " " + pad + row.digits)
            + Text(String(repeating: "0", count: row.shift)).foregroundColor(Color.secondary.opacity(0.4))
    }
}

// MARK: - 키패드

struct Keypad: View {
    let canSubmit: Bool
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
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
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, minHeight: 58)
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
    let averageTime: Double?
    let elapsed: TimeInterval
    let mistakes: [Problem]
    let isNewRecord: Bool
    let best: Int
    let onRetry: () -> Void
    let onHome: () -> Void

    @State private var shown: Problem?

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
                        StatTile(title: "평균 풀이", value: averageTime.map { String(format: "%.1f초", $0) } ?? "-")
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
                        Text("눌러서 손계산 풀이 보기").font(.caption).foregroundStyle(.secondary)
                        ForEach(uniqueMistakes) { p in
                            Button {
                                shown = p
                            } label: {
                                HStack {
                                    Text(p.text)
                                    Spacer()
                                    Text("\(p.answer)").bold()
                                    Image(systemName: "lightbulb").font(.footnote).foregroundStyle(.orange)
                                }
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(.red)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
        .sheet(item: $shown) { p in
            HandCalcSheet(problem: p)
        }
    }

    private var timeString: String {
        let s = Int(elapsed.rounded())
        return s >= 60 ? "\(s / 60)분 \(s % 60)초" : "\(s)초"
    }
}

/// 문제 하나의 손계산 풀이를 보여주는 시트
struct HandCalcSheet: View {
    let problem: Problem

    var body: some View {
        VStack(spacing: 24) {
            Text("\(problem.text) = \(problem.answer)")
                .font(.system(.title, design: .rounded).bold())
            HandCalcView(calc: HandCalc(problem))
        }
        .padding()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
