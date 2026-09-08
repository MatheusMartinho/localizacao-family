import SwiftUI

/// Cartões de viagem no topo da lista da família: a sua (com opção de
/// encerrar) e a de quem está a caminho.
struct TripSection: View {
    @Bindable var model: AppModel
    @State private var checkedIn = false

    private var store: any FamilyStore { model.store }
    private var othersTrips: [FamilyTrip] {
        store.activeTrips.filter { $0.travelerID != store.selfMember?.id }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let trip = store.myActiveTrip {
                // Aqui o "Cheguei" já encerra a viagem e a família recebe o
                // aviso de chegada — um check-in por cima seria aviso dobrado.
                myTripCard(trip)
            } else {
                if !store.places.isEmpty { startButton }
                checkInButton
            }
            ForEach(othersTrips) { trip in
                otherTripCard(trip)
            }
        }
    }

    /// Menu, e não `confirmationDialog`: o diálogo herdava o tint verde do app
    /// e desenhava os destinos em verde-escuro sobre o vidro escuro — ilegível.
    /// O menu usa a cor de rótulo do sistema e ainda rola sozinho quando a
    /// família tem muitos lugares marcados.
    private var startButton: some View {
        Menu {
            ForEach(store.places) { place in
                Button {
                    model.startTrip(to: place)
                } label: {
                    Text("\(place.emoji)  \(place.name)")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(Color.accentAdaptive)
                Text("Avisar que estou a caminho")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }

    /// O contrário do botão de pânico, e o que a família mais pede: um toque
    /// para dizer que está tudo bem. Fica logo abaixo do "estou a caminho"
    /// porque é a mesma conversa — avisar sem precisar escrever.
    private var checkInButton: some View {
        Button {
            model.sendCheckIn()
            checkedIn = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.accentAdaptive)
                Text("Avisar que cheguei bem")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .alert("Avisamos sua família", isPresented: $checkedIn) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Todo mundo da família recebeu que você chegou bem.")
        }
    }

    private func myTripCard(_ trip: FamilyTrip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(Color.accentAdaptive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A caminho de \(trip.destinationLabel)")
                        .font(.subheadline.weight(.semibold))
                    Text("Saiu \(FamilyMember.coarse(since: trip.startedAt)) · sua família está acompanhando")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button("Cheguei") { model.finishMyTrip(arrived: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentAdaptive)
                Button("Cancelar") { model.finishMyTrip(arrived: false) }
                    .buttonStyle(.bordered)
                    .tint(Color.stoppedGray)
            }
            .font(.subheadline)
        }
        .padding(14)
        .glassEffect(.regular.tint(.accentAdaptive.opacity(0.12)), in: .rect(cornerRadius: 20))
    }

    /// Sem estado de "atrasado": o cartão diz para onde a pessoa vai e desde
    /// quando saiu. Quem quiser saber se está demorando olha o relógio — o app
    /// não pinta de vermelho em cima de um palpite de rota.
    private func otherTripCard(_ trip: FamilyTrip) -> some View {
        let traveler = store.member(id: trip.travelerID)
        return HStack(spacing: 12) {
            if let traveler {
                AvatarView(member: traveler, size: 40, ring: 2.5)
            } else {
                Text(trip.travelerEmoji).font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.travelerName) está a caminho")
                    .font(.subheadline.weight(.semibold))
                Text("\(trip.destinationLabel) · saiu \(FamilyMember.coarse(since: trip.startedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
