import SwiftUI
import MapKit

/// Detalhe no Watch: mini-mapa com o pin do membro + fatos rápidos.
struct WatchMemberDetail: View {
    @Bindable var model: WatchModel
    let memberID: String

    private var member: FamilyMember? { model.store.member(id: memberID) }

    var body: some View {
        Group {
            if let member {
                content(for: member)
            } else {
                Text("Membro não encontrado")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(member?.name ?? "")
    }

    private func content(for member: FamilyMember) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: member.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )))) {
                    Annotation(member.name, coordinate: member.coordinate) {
                        ZStack {
                            Circle().fill(.background)
                            Text(member.emoji).font(.system(size: 15))
                            Circle().strokeBorder(
                                member.isMoving ? Color.accentLime : Color.stoppedGray,
                                lineWidth: 2.5)
                        }
                        .frame(width: 30, height: 30)
                    }
                    .annotationTitles(.hidden)
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)

                HStack(spacing: 6) {
                    Circle()
                        .fill(member.isMoving ? Color.accentLime : Color.stoppedGray)
                        .frame(width: 8, height: 8)
                    Text(member.statusLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(member.isMoving ? Color.accentLime : Color.stoppedGray)
                }

                if let place = member.placeHint {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Label("\(member.batteryPct)%", systemImage: "battery.75percent")
                        .foregroundStyle(Color.battery(member.batteryPct))
                    Spacer()
                    if let me = model.store.selfMember, !member.isSelf {
                        Label(member.distance(to: me),
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .foregroundStyle(Color.accentLime)
                    }
                }
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 4)
            }
        }
    }
}
