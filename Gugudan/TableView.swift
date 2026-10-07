import SwiftUI

struct TableView: View {
    @Environment(StatsStore.self) private var stats
    @AppStorage("tableNumber") private var number = 11
    @State private var shown: Problem?

    var body: some View {
        List {
            Section {
                Stepper(value: $number, in: 2...99) {
                    Text("\(number)단")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: number)
                }
                Slider(value: Binding(get: { Double(number) }, set: { number = Int($0.rounded()) }), in: 2...99, step: 1)
            }

            Section {
                ForEach(1...19, id: \.self) { b in
                    let p = Problem(a: number, b: b)
                    Button {
                        shown = p
                    } label: {
                        HStack {
                            Text(p.text)
                            Spacer()
                            Text("\(p.answer)").bold()
                        }
                        .font(.system(.title3, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(stats.isWeak(p) ? Color.red : Color.primary)
                        .contentShape(Rectangle())
                    }
                }
            } footer: {
                Text("눌러서 손계산 풀이 보기 · 빨간색은 자주 틀리는 문제")
            }
        }
        .navigationTitle("곱셈표")
        .sheet(item: $shown) { p in
            HandCalcSheet(problem: p)
        }
    }
}

#Preview {
    NavigationStack { TableView() }.environment(StatsStore())
}
