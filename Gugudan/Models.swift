import Foundation
import Observation

struct Problem: Hashable, Codable, Identifiable {
    let a: Int
    let b: Int

    var id: String { "\(a)x\(b)" }
    var answer: Int { a * b }
    var text: String { "\(a) × \(b)" }
}

extension Problem {
    init?(id: String) {
        let parts = id.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(a: parts[0], b: parts[1])
    }

    enum Kind: CaseIterable {
        case teens, twoByOne, twoByTwo

        var title: String {
            switch self {
            case .teens: "19단"
            case .twoByOne: "두 자리 × 한 자리"
            case .twoByTwo: "두 자리 × 두 자리"
            }
        }
    }

    var kind: Kind {
        if (11...19).contains(a) && (11...19).contains(b) { return .teens }
        if a < 10 || b < 10 { return .twoByOne }
        return .twoByTwo
    }
}

/// 출제 범위 프리셋
enum Level: String, CaseIterable, Identifiable {
    case teens, twoByOne, twoByTwo, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teens: "19단"
        case .twoByOne: "두 자리 × 한 자리"
        case .twoByTwo: "두 자리 × 두 자리"
        case .custom: "직접 설정"
        }
    }

    /// custom은 nil (사용자 설정 범위 사용)
    var ranges: (a: ClosedRange<Int>, b: ClosedRange<Int>)? {
        switch self {
        case .teens: (11...19, 11...19)
        case .twoByOne: (11...99, 2...9)
        case .twoByTwo: (11...99, 11...99)
        case .custom: nil
        }
    }
}

enum QuizMode: Hashable {
    case practice
    case timeAttack
    case review

    static let practiceCount = 20
    static let timeAttackSeconds = 120

    var title: String {
        switch self {
        case .practice: "연습하기"
        case .timeAttack: "타임어택"
        case .review: "오답 집중"
        }
    }
}

struct QuizConfig: Hashable {
    var aRange: ClosedRange<Int>
    var bRange: ClosedRange<Int>
    var mode: QuizMode

    func contains(_ p: Problem) -> Bool {
        aRange.contains(p.a) && bRange.contains(p.b)
    }
}

/// 문제별 정답/오답/풀이시간 기록. UserDefaults에 저장된다.
@Observable
final class StatsStore {
    struct Record: Codable {
        var correct = 0
        var wrong = 0
        var totalTime: Double = 0   // 맞힌 문제의 풀이 시간 합 (초)
        var total: Int { correct + wrong }
    }

    private(set) var records: [String: Record] = [:]
    private(set) var bestTimeAttack = 0

    private let recordsKey = "records.v2"
    private let bestKey = "bestTimeAttack.v2"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
        bestTimeAttack = defaults.integer(forKey: bestKey)
    }

    func record(_ problem: Problem, correct: Bool, time: Double) {
        var r = records[problem.id, default: Record()]
        if correct {
            r.correct += 1
            r.totalTime += time
        } else {
            r.wrong += 1
        }
        records[problem.id] = r
        save()
    }

    /// 신기록이면 true
    func submitTimeAttack(score: Int) -> Bool {
        guard score > bestTimeAttack else { return false }
        bestTimeAttack = score
        UserDefaults.standard.set(score, forKey: bestKey)
        return true
    }

    func reset() {
        records = [:]
        bestTimeAttack = 0
        UserDefaults.standard.removeObject(forKey: recordsKey)
        UserDefaults.standard.removeObject(forKey: bestKey)
    }

    // MARK: - 분석

    /// 틀린(또는 풀이를 본) 횟수가 맞힌 횟수에 비해 많을수록 커진다.
    private func weakness(_ r: Record) -> Double {
        Double(r.wrong) * 2 / Double(r.correct + 1)
    }

    func weight(for problem: Problem) -> Double {
        guard let r = records[problem.id] else { return 1.5 }
        return min(6, 1 + weakness(r))
    }

    func isWeak(_ problem: Problem) -> Bool {
        guard let r = records[problem.id], r.wrong > 0 else { return false }
        return weakness(r) >= 0.5
    }

    /// 약한 순으로 정렬된 약점 문제들
    var weakProblems: [Problem] {
        records
            .compactMap { key, r -> (Problem, Double)? in
                guard let p = Problem(id: key), isWeak(p) else { return nil }
                return (p, weakness(r))
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
            .map(\.0)
    }

    var totalAnswered: Int { records.values.reduce(0) { $0 + $1.total } }
    var totalCorrect: Int { records.values.reduce(0) { $0 + $1.correct } }

    struct Summary {
        var answered = 0
        var correct = 0
        var time: Double = 0
        var accuracy: Double? { answered == 0 ? nil : Double(correct) / Double(answered) }
        var averageTime: Double? { correct == 0 ? nil : time / Double(correct) }
    }

    func summary(of kind: Problem.Kind) -> Summary {
        var s = Summary()
        for (key, r) in records {
            guard let p = Problem(id: key), p.kind == kind else { continue }
            s.answered += r.total
            s.correct += r.correct
            s.time += r.totalTime
        }
        return s
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }
}

/// 출제기. 범위 문제는 균등 랜덤 + 약점 문제를 일정 확률로 섞고,
/// 목록 문제(오답 집중)는 약한 문제일수록 자주 낸다. 같은 문제는 연달아 나오지 않는다.
struct ProblemPicker {
    enum Pool {
        case ranges(ClosedRange<Int>, ClosedRange<Int>)
        case list([Problem])
    }

    let pool: Pool
    let stats: StatsStore
    private var last: Problem?

    init(pool: Pool, stats: StatsStore) {
        self.pool = pool
        self.stats = stats
    }

    var isEmpty: Bool {
        if case .list(let list) = pool { return list.isEmpty }
        return false
    }

    mutating func next() -> Problem? {
        let picked: Problem?
        switch pool {
        case .list(let list):
            picked = weighted(from: list)
        case .ranges(let aRange, let bRange):
            let weak = stats.weakProblems.filter { aRange.contains($0.a) && bRange.contains($0.b) && $0 != last }
            if !weak.isEmpty && Double.random(in: 0..<1) < 0.3 {
                picked = weak.randomElement()
            } else {
                var p = Problem(a: .random(in: aRange), b: .random(in: bRange))
                for _ in 0..<5 where p == last {
                    p = Problem(a: .random(in: aRange), b: .random(in: bRange))
                }
                picked = p
            }
        }
        last = picked
        return picked
    }

    private func weighted(from list: [Problem]) -> Problem? {
        let candidates = list.count > 1 ? list.filter { $0 != last } : list
        guard let fallback = candidates.last else { return nil }
        let weights = candidates.map { stats.weight(for: $0) }
        var r = Double.random(in: 0..<weights.reduce(0, +))
        for (p, w) in zip(candidates, weights) {
            r -= w
            if r < 0 { return p }
        }
        return fallback
    }
}

/// 손으로 푸는 세로셈(필산) 과정
struct HandCalc {
    struct Row {
        var prefix = ""          // "×", "+" 등
        var digits: String       // 실제 숫자 (오른쪽 정렬)
        var shift = 0            // 오른쪽에 비워두는 자리 수 (자리 올림)
        var note: String?        // 옆에 붙는 설명
    }

    enum Line {
        case row(Row)
        case rule
    }

    let lines: [Line]
    let width: Int
    /// 암산용 분해: 47 × 38 = 47×30 + 47×8 = 1410 + 376
    let mental: String?

    init(_ p: Problem) {
        // 자리 수가 많은 쪽을 위로
        let top = max(p.a, p.b)
        let bottom = min(p.a, p.b)
        let bottomDigits = String(bottom).reversed().map { Int(String($0))! }

        var lines: [Line] = [
            .row(Row(digits: String(top))),
            .row(Row(prefix: "×", digits: String(bottom))),
            .rule,
        ]

        let partials = bottomDigits.enumerated().filter { $0.element != 0 }
        if partials.count <= 1 {
            lines.append(.row(Row(digits: String(top * bottom))))
        } else {
            for (place, d) in partials {
                let multiplier = d * Int(pow(10, Double(place)))
                lines.append(.row(Row(digits: String(top * d), shift: place, note: "\(top)×\(multiplier)")))
            }
            lines.append(.rule)
            lines.append(.row(Row(digits: String(top * bottom))))
        }
        self.lines = lines
        self.width = lines.reduce(0) { w, line in
            if case .row(let r) = line { return max(w, r.digits.count + r.shift) }
            return w
        }

        if partials.count > 1 {
            let terms = partials.reversed().map { place, d in (d * Int(pow(10, Double(place))), top * d * Int(pow(10, Double(place)))) }
            mental = "\(top)×\(terms.map { String($0.0) }.joined(separator: " + \(top)×"))\n= \(terms.map { String($0.1) }.joined(separator: " + ")) = \(top * bottom)"
        } else if top >= 10 && bottom > 1 {
            // 47 × 8 = 40×8 + 7×8 = 320 + 56
            let tens = top / 10 * 10, ones = top % 10
            mental = ones == 0 ? nil : "\(tens)×\(bottom) + \(ones)×\(bottom)\n= \(tens * bottom) + \(ones * bottom) = \(top * bottom)"
        } else {
            mental = nil
        }
    }
}
