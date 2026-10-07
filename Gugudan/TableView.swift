import SwiftUI

struct TableView: View {
    @Environment(StatsStore.self) private var stats

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(2...9, id: \.self) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(a)단")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                            .padding(.bottom, 2)
                        ForEach(1...9, id: \.self) { b in
                            let p = Problem(a: a, b: b)
                            HStack {
                                Text(p.text)
                                Spacer()
                                Text("\(p.answer)").bold()
                            }
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(stats.isWeak(p) ? Color.red : Color.primary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding()

            Text("빨간색은 자주 틀리는 문제예요")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("구구단표")
    }
}

#Preview {
    NavigationStack { TableView() }.environment(StatsStore())
}
