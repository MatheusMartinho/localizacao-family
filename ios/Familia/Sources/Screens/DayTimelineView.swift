import SwiftUI

/// Onde a pessoa esteve hoje, montado a partir da trilha gravada.
struct DayTimelineView: View {
    @Bindable var model: AppModel
    let member: FamilyMember

    @State private var loading = true

    private var store: any FamilyStore { model.store }
    private var segments: [DaySegment] { store.daySegments(for: member) }

    private static let hour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        List {
            if loading && segments.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if segments.isEmpty {
                ContentUnavailableView {
                    Label("Sem histórico hoje", systemImage: "clock.badge.questionmark")
                } description: {
                    Text("O histórico começa a ser gravado conforme \(member.name) se move ao longo do dia.")
                }
            } else {
                ForEach(segments.reversed()) { segment in
                    row(segment)
                }
            }
        }
        .navigationTitle("Hoje")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadTrail(for: member.id)
            loading = false
        }
    }

    private func row(_ segment: DaySegment) -> some View {
        HStack(spacing: 14) {
            // Trilho vertical com o marcador, para dar cara de linha do tempo.
            VStack(spacing: 0) {
                Circle()
                    .fill(segment.place == nil ? Color.stoppedGray : Color.accentAdaptive)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.stoppedGray.opacity(0.3))
                    .frame(width: 2)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(segment.label)
                    .font(.headline)
                    .foregroundStyle(segment.place == nil ? .secondary : .primary)
                Text("\(Self.hour.string(from: segment.start)) – \(Self.hour.string(from: segment.end)) · \(duration(segment))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if segment.place == nil {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func duration(_ segment: DaySegment) -> String {
        let m = segment.minutes
        if m < 60 { return "\(m) min" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h) h" : "\(h) h \(rest) min"
    }
}
