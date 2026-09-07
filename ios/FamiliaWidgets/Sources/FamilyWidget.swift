import WidgetKit
import SwiftUI

/// Widget da tela de início: a família num olhar, sem abrir o app.
struct FamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FamilyWidget", provider: FamilyProvider()) { entry in
            FamilyWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Família")
        .description("Onde cada pessoa está agora.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FamilyEntry: TimelineEntry {
    let date: Date
    let snapshot: FamilySnapshot
}

/// O app grava o retrato no App Group; aqui é só leitura. Sem sessão do
/// Supabase no widget, que roda em outro processo.
struct FamilyProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyEntry {
        FamilyEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyEntry) -> Void) {
        completion(FamilyEntry(date: .now, snapshot: FamilySnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyEntry>) -> Void) {
        let entry = FamilyEntry(date: .now, snapshot: FamilySnapshot.load() ?? .placeholder)
        // O sistema limita a frequência; recarregar a cada 15 min é o
        // equilíbrio entre estar atualizado e não gastar orçamento à toa.
        completion(Timeline(entries: [entry],
                            policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct FamilyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: FamilySnapshot

    /// Quem está em emergência vem primeiro; depois quem está no carro, que é
    /// quem está se mexendo agora; o resto por nome.
    private var ordered: [FamilySnapshot.Entry] {
        snapshot.members.sorted { a, b in
            if a.isEmergency != b.isEmergency { return a.isEmergency }
            if a.isInVehicle != b.isInVehicle { return a.isInVehicle }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Quantas linhas cabem sem empurrar o título para fora. O médio tem a
    /// mesma altura do pequeno e o dobro da largura, então ganha duas colunas
    /// em vez de mais linhas — foi o que estourou com uma família de sete.
    private var rowsPerColumn: Int { 3 }
    private var columns: Int { family == .systemSmall ? 1 : 2 }
    private var capacity: Int { rowsPerColumn * columns }

    /// Quando não cabe todo mundo, a última vaga vira a contagem do resto —
    /// assim ninguém é escondido em silêncio e nada transborda.
    private var visible: [FamilySnapshot.Entry] {
        ordered.count > capacity ? Array(ordered.prefix(capacity - 1)) : ordered
    }
    private var hidden: Int { ordered.count - visible.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.familyName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer()
                if snapshot.members.contains(where: \.isEmergency) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.dangerRed)
                }
            }

            if visible.isEmpty {
                Text("Abra o app para ver a família.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if columns == 1 {
                column(visible, withOverflow: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    column(Array(visible.prefix(rowsPerColumn)), withOverflow: false)
                    column(Array(visible.dropFirst(rowsPerColumn)), withOverflow: true)
                }
            }
        }
    }

    private func column(_ entries: [FamilySnapshot.Entry], withOverflow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // Com pouca gente as linhas ficariam grudadas no topo.
            Spacer(minLength: 0)
            ForEach(entries) { member in
                row(member)
            }
            if withOverflow && hidden > 0 {
                Text("+\(hidden) na família")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, family == .systemSmall ? 30 : 36)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ member: FamilySnapshot.Entry) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                Text(member.emoji).font(.system(size: family == .systemSmall ? 12 : 14))
                Circle()
                    .strokeBorder(member.isEmergency ? Color.dangerRed
                                  : member.isPaused == true ? Color.stoppedGray.opacity(0.5)
                                  : member.isMoving ? Color.accentDeep : Color.stoppedGray,
                                  lineWidth: 2)
            }
            .frame(width: family == .systemSmall ? 22 : 26,
                   height: family == .systemSmall ? 22 : 26)

            VStack(alignment: .leading, spacing: 0) {
                Text(member.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                if family != .systemSmall {
                    // Pausado, o lugar guardado é o de antes da pausa: dizer
                    // "🏠 Casa" aí seria mentir sobre onde a pessoa está.
                    // Na coluna estreita do médio, "No carro · 32 km/h" era
                    // cortado em "No carro · 32 k…"; o ícone de carro ao lado
                    // já diz o "no carro", então aqui fica só a velocidade.
                    Text(member.isPaused == true
                         ? "Pausado"
                         : member.vehicleKmh.map { "\($0) km/h" }
                         ?? (member.place ?? member.statusLine))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if member.isInVehicle {
                Image(systemName: "car.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentDeep)
            }
            if (1...20).contains(member.batteryPct) {
                Text("\(member.batteryPct)%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.dangerRed)
            }
        }
    }
}
