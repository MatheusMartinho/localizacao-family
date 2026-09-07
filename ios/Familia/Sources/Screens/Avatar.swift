import SwiftUI

/// Avatar do membro: foto da galeria quando existe, senão o emoji escolhido.
/// O anel indica o status de movimento.
struct AvatarView: View {
    let member: FamilyMember
    var size: CGFloat = 50
    var ring: CGFloat = 3
    /// Fundo escuro (globo, onboarding) usa o limão; claro usa o verde profundo.
    var onDark = false
    /// Sobrepõe a cor do anel — o alarme de pânico usa vermelho.
    var ringOverride: Color? = nil

    var body: some View {
        ZStack {
            Circle().fill(.background.secondary)

            if let photo = member.photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.circle)
            } else {
                Text(member.emoji).font(.system(size: size * 0.54))
            }

            Circle()
                .strokeBorder(ringOverride ?? Color.movement(member.isMoving, onDark: onDark),
                              lineWidth: ring)
        }
        .frame(width: size, height: size)
    }
}
