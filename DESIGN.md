# Família — Linguagem de Design

Apps nativos com identidade visual idêntica. Mapa em tela cheia, superfícies flutuantes de vidro, acento verde-limão neon.

## Nome do app
**Família** (bundle: `com.matheus.familia`)

## Paleta

| Token          | Hex       | Uso |
|----------------|-----------|-----|
| `accent`       | `#D4FF3F` | Verde-limão neon: pins, rotas, progresso, CTA, status "em movimento" |
| `accentDark`   | `#A8CC2A` | Variante para texto sobre claro |
| `ink`          | `#101210` | Preto quase puro: texto primário, botões escuros |
| `inkSoft`      | `#3A3D38` | Texto secundário |
| `paper`        | `#F4F5F2` | Off-white: cartões, sheets |
| `stopped`      | `#8E93A6` | Cinza-azulado: status "parado" |
| `danger`       | `#FF5A4E` | Bateria baixa, SOS |
| Dark mode      |           | `paper→#1A1C19`, `ink→#F4F5F2`, accent igual |

## Tipografia
- iOS: SF Pro (system), Rounded para números grandes
- Títulos: bold, tracking apertado. Números de destaque (distância, tempo): extra-bold tabular.

## Componentes-chave (iguais nos dois apps)
1. **Mapa full-screen** de ponta a ponta, UI flutuando por cima.
2. **Avatar pin**: círculo com foto/emoji, anel `accent` de 3pt, ponta de gota; pulso animado quando em movimento; badge de bateria.
3. **Pílula de status** presa no topo: "Maria · Em movimento há 12 min" com ponto pulsante `accent` (movimento) ou `stopped` (parado).
4. **Bottom card / sheet** de vidro (blur) com cantos 28pt: lista da família — avatar, nome, lugar aproximado, distância de você, status + tempo, bateria.
5. **Barra de ações flutuante** inferior: mapa / centralizar / lista, em pílula de vidro.
6. **Tela de detalhe do membro**: cartão grande com nome, status, "há quanto tempo", bateria, endereço aproximado, botões (rota até ele, notificar).
7. **Onboarding/convite**: criar família → código de 6 letras enorme em `accent` sobre `ink`, botão compartilhar.

## Materiais
- **iOS**: Liquid Glass em TUDO que flutua — `.glassEffect()`, `GlassEffectContainer`, `.buttonStyle(.glass)`, tint `accent` nos CTAs. Nada de retângulos opacos sobre o mapa.

## Motion
- Pins deslizam suavemente entre atualizações (animação de 1s, easing).
- Pulso no anel do avatar quando em movimento.
- Sheets com spring físico.

## Status de movimento (lógica compartilhada)
- `is_moving = speed > 1.4 m/s` sustentado por 30s (ou atividade motion do SO).
- Transição para "parado" após 90s abaixo do limiar.
- `state_since` = quando o estado atual começou → exibido como "há X min".
