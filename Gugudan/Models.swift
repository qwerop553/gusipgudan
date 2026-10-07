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

    static func all(dans: some Sequence<Int>) -> [Problem] {
        dans.flatMap { a in (1...9).map { Problem(a: a, b: $0) } }
    }
}

enum QuizMode: Hashable {
    case practice
    case timeAttack
    case review

    static let practiceCount = 20
    static let timeAttackSeconds = 60

    var title: String {
        switch self {
        case .practice: "연습하기"
        case .timeAttack: "타임어택"
        case .review: "오답 집중"
        }
    }
}

struct QuizConfig: Hashable {
    var dans: [Int]
    var mode: QuizMode
}

/// 문제별 정답/오답 기록. UserDefaults에 저장된다.
@Observable
final class StatsStore {
    struct Record: Codable {
        var correct = 0
        var wrong = 0
        var total: Int { correct + wrong }
    }

    private(set) var records: [String: Record] = [:]
    private(set) var bestTimeAttack = 0

    private let recordsKey = "records.v1"
    private let bestKey = "bestTimeAttack.v1"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
        bestTimeAttack = defaults.integer(forKey: bestKey)
    }

    func record(_ problem: Problem, correct: Bool) {
        var r = records[problem.id, default: Record()]
        if correct { r.correct += 1 } else { r.wrong += 1 }
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

    /// 틀린 횟수가 맞힌 횟수에 비해 많을수록 커진다. 0이면 약점 아님.
    private func weakness(_ r: Record) -> Double {
        Double(r.wrong) * 2 / Double(r.correct + 1)
    }

    /// 출제 가중치: 약한 문제일수록, 안 풀어본 문제는 살짝 더 자주 나온다.
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

    func accuracy(dan: Int) -> Double? {
        let rs = (1...9).compactMap { records[Problem(a: dan, b: $0).id] }
        let total = rs.reduce(0) { $0 + $1.total }
        guard total > 0 else { return nil }
        return Double(rs.reduce(0) { $0 + $1.correct }) / Double(total)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }
}

/// 가중치 랜덤 출제. 같은 문제가 연달아 나오지 않게 한다.
struct ProblemPicker {
    let pool: [Problem]
    let stats: StatsStore
    private var last: Problem?

    init(pool: [Problem], stats: StatsStore) {
        self.pool = pool
        self.stats = stats
    }

    mutating func next() -> Problem? {
        let candidates = pool.count > 1 ? pool.filter { $0 != last } : pool
        guard let fallback = candidates.last else { return nil }
        let weights = candidates.map { stats.weight(for: $0) }
        var r = Double.random(in: 0..<weights.reduce(0, +))
        var picked = fallback
        for (p, w) in zip(candidates, weights) {
            r -= w
            if r < 0 { picked = p; break }
        }
        last = picked
        return picked
    }
}
