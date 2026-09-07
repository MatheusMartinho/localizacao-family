# Família 📍

App de localização familiar em tempo real: iOS (SwiftUI + Liquid Glass + Live
Activity + widget + Apple Watch) sobre um backend Supabase.

```
├── DESIGN.md                  # Linguagem visual
├── backend/supabase/          # Migrações SQL (tabelas, RLS, realtime, RPCs)
└── ios/                       # App iOS + Widgets (Live Activity) + Watch
```

## Rodando sem backend (modo demo)

O app abre em **modo demo** enquanto `Config.swift` estiver com os placeholders:
uma família de sete se movendo por São Paulo — dois no carro, três juntos na casa
da vó, e você. Serve para ver todo o visual funcionando na hora, e é como se
testa layout com família grande sem inventar contas de verdade no banco.

- `cd ios && xcodegen generate && open Familia.xcodeproj` → rode o scheme `Familia`.
- Com o Supabase já configurado, `FAMILIA_FORCE_DEMO=1` no ambiente do scheme
  (ou `SIMCTL_CHILD_FAMILIA_FORCE_DEMO=1 xcrun simctl launch …`) força a família
  fake mesmo assim. Só em builds `DEBUG`.

## Conectando o backend real (Supabase)

1. Crie um projeto grátis em [supabase.com](https://supabase.com) (região São Paulo).
2. No SQL Editor, rode **na ordem** todos os arquivos de
   `backend/supabase/migrations/`, do `0001` ao `0007`. Cada um traz no
   cabeçalho o porquê de existir.
3. Em **Project Settings → API Keys**, copie o host do projeto
   (`seu-projeto.supabase.co`) e a chave publishable (`sb_publishable_…`).
4. Copie [`ios/Secrets.example.xcconfig`](ios/Secrets.example.xcconfig) para
   `ios/Secrets.xcconfig` e preencha. **Esse arquivo é ignorado pelo git** — as
   credenciais não moram no código-fonte. Só a chave publishable: a
   `service_role` ignora o RLS e nunca pode entrar num app cliente.
5. Em **Authentication → Providers → Email**, desligue o **"Confirm email"**. Sem isso,
   cada pessoa precisa clicar num link no e-mail antes de conseguir entrar.

> A chave publishable **não é segredo** — ela é extraível de qualquer build
> instalado, por design. Guardá-la fora do repositório é higiene, não proteção.
> Quem protege os dados é o RLS: sem sessão, toda tabela devolve zero linhas, e
> com uma sessão de fora da família, também.

### Assinatura de código

Compile **com assinatura** (o padrão do Xcode). Com `CODE_SIGNING_ALLOWED=NO` o app
não consegue gravar no Keychain, a sessão do Supabase não persiste e todas as
requisições saem sem o token — o sintoma é um `not authenticated` inexplicável.

Depois disso: cada pessoa cria conta, uma cria a família (que gera um código de
convite) e as outras entram com esse código. A localização sincroniza via Realtime.

### Sobre o código de convite

O código tem **10 caracteres** de um alfabeto de 32 (sem I, O, 0 e 1, que se
confundem ao ditar), sorteados com `pgcrypto`. Ele começou com 6 caracteres
hexadecimais, e isso era um problema real: 16,7 milhões de combinações, com o
`join_family` respondendo a ~2 req/s por conexão e distinguindo "código
inválido" de sucesso. Cerca de 50 h de força bruta em paralelo entravam numa
família — e entrar numa família é ver a localização ao vivo de todo mundo nela.
Com 10 caracteres o espaço vai a ~1,1 quatrilhão. A migração `0007` troca o
gerador e sorteia códigos novos para as famílias que já existiam.

## Globo 3D

Quando alguém da família está a mais de 1 000 km, o mapa plano vira um oceano
inútil — aí o app oferece o **globo 3D** (RealityKit): Terra, atmosfera, céu com
milhares de estrelas e Via Láctea, pins da família e um arco pontilhado entre
você e a pessoa selecionada. Gira sozinho devagar, arrasta com inércia, belisca
para aproximar e "voa" suavemente até quem você tocar.

### Céu

Coloque uma foto em `ios/Familia/Resources/sky.jpg` (ou `.png`) e ela vira o
**fundo da tela** do globo. Não precisa ser equiretangular — justamente por
isso ela entra como fundo plano em vez de envolver uma esfera, onde uma foto
comum ficaria esticada. Sem esse arquivo, o app desenha um céu procedural com
Via Láctea, poeira e ~40 mil estrelas.

### Texturas

`ios/Familia/Resources/` traz a Terra fotográfica da **NASA** (domínio público,
sem exigência de atribuição):

| Arquivo | Origem | Tamanho |
|---|---|---|
| `earth_day.jpg` | [Blue Marble Next Generation](https://visibleearth.nasa.gov/images/73909/) (NASA Earth Observatory) | 4096×2048 |
| `earth_night.jpg` | [Earth at Night / VIIRS](https://visibleearth.nasa.gov/images/79765/) | 2048×1024 |

Para trocar por outra Terra, basta substituir os dois arquivos por imagens
**equiretangulares 2:1**. Sem eles, o app cai numa Terra "neon" (grade
verde-limão) desenhada em tempo de execução — o céu estrelado é sempre
procedural, nunca depende de arquivo.

### Alinhamento do modelo (se você trocar o `earth.usdz`)

Cada malha alinha a textura de um jeito, e errar isso joga os pins longe do
lugar (Lisboa chegou a aparecer no Himalaia). Dois valores controlam isso:

- `GlobeMath.Alignment.sphere` (−90°) — para a esfera do próprio RealityKit.
- `GlobeScene.modelLongitudeOffset` (+90°) — para o `earth.usdz` atual.

Para descobrir o valor de outra malha sem tentativa e erro, exporte para `.usda`
(`usdcat modelo.usdc -o modelo.usda`) e compare as coordenadas `primvars:st`
com as posições dos vértices no equador: a diferença entre a longitude da
textura e a do modelo é constante e é exatamente o deslocamento.

> **Eixo V invertido:** glTF conta o V de cima para baixo e o USD de baixo para
> cima. Se o globo aparecer com a Antártida no topo, inverta a textura
> verticalmente (`sips -f vertical`) e reempacote — foi o que fizemos com este
> modelo. O sintoma é traiçoeiro porque a longitude parece errada quando na
> verdade o problema é a latitude.

### Iluminação

A Terra usa `UnlitMaterial`, não PBR: o `RealityView` aplica uma iluminação de
ambiente própria que não dá para desligar (só existe `.default` e `.skybox`) e
que estoura a exposição de um material PBR — o globo virava uma bola branca. As
luzes das cidades entram como uma casca translúcida logo acima da superfície.

## Lugares da família

Marque a casa, o trabalho ou a casa da vó em **Ajustes → Lugares da família**.
O lugar nasce onde você está, com um raio ajustável (50 m a 1 km), e vale para
a **família inteira** — quem cria, cria para todos.

A partir daí, sempre que alguém entra no círculo o app troca o endereço pelo
nome do lugar: a pílula do mapa passa a dizer "🏠 Casa" em vez de "Avenida
Paulista", e o mesmo vale para a lista, o detalhe e a tela de bloqueio. O mapa
desenha o círculo de cada lugar, com a etiqueta logo abaixo.

> Raios abaixo de ~100 m fazem a pessoa "sair" do lugar sozinha, porque o GPS
> oscila alguns metros mesmo com o aparelho parado. O padrão de 150 m é um bom
> ponto de partida para uma casa.

### Chegadas e saídas

Em **Ajustes → Chegadas e saídas** você escolhe o que quer receber: chegadas e
saídas, só chegadas, só saídas, ou nada. O aviso sai como *"👧 Ana chegou —
Chegou em 🏫 Escola"*.

A escolha tem dois níveis, para não virar uma lista interminável de opções:

1. **Um padrão por pessoa** — vale para todos os lugares.
2. **Exceções por lugar** — cada lugar pode ter regra própria ou herdar o
   padrão. É o que permite "me avise quando a Ana chegar na escola, mas não
   quando ela chegar em casa".

A linha de cada pessoa mostra o padrão e quantas exceções ela tem.

Essas escolhas são de quem **recebe** e ficam só no aparelho (`UserDefaults`),
não no banco — ninguém da família descobre quem você acompanha. Como
consequência, elas não seguem você ao trocar de celular.

A detecção roda **no aparelho de cada pessoa**, comparando o lugar atual com o
da última atualização recebida pelo realtime — não existe trigger no banco nem
push. Três decisões que evitam barulho:

- A primeira leitura depois de abrir o app só registra o estado. Sem isso, abrir
  o app avisaria "chegou" para todo mundo que já estava em casa.
- Você nunca é notificado sobre si mesmo.
- O identificador da notificação combina pessoa + lugar + sentido, então alguém
  oscilando na borda do raio substitui o aviso anterior em vez de empilhar.

Como qualquer notificação local deste app, ela depende de o app estar vivo em
segundo plano (o que a localização garante). Se o usuário encerrar o app à
força, os avisos param até ele abrir de novo.

## Alarme de pânico (SOS)

Segurar o botão vermelho por 1,2 s grava um alerta na tabela `alerts`. Quem
está na família recebe, **em tempo real**:

1. **Tela cheia vermelha** com o nome, o lugar e botões "Ver no mapa" / "Estou
   indo" — impossível de ignorar com o app aberto.
2. **Notificação com som e vibração** quando o app está em segundo plano.

O alerta é uma notificação **local**, não push. Funciona porque o app já roda em
segundo plano pelo `UIBackgroundModes: location`, então a assinatura realtime
continua viva e dispara a notificação quando o alerta chega. A consequência: se
a pessoa **encerrar o app à força** (arrastar para cima no seletor de apps), o
alerta não chega até ela abrir o app de novo. Para cobrir esse caso é preciso
push (APNs), que exige conta paga de desenvolvedor Apple + uma Edge Function no
Supabase enviando o push quando uma linha entra em `alerts`.

Para o alerta furar o Modo Foco, adicione o entitlement
`com.apple.developer.usernotifications.time-sensitive` ao target (Xcode →
Signing & Capabilities → Time Sensitive Notifications). Sem ele o sistema trata
como notificação comum.

## Tela de bloqueio é opt-in

Ninguém aparece na tela de bloqueio ou na Dynamic Island por padrão. Abra o
perfil de alguém e marque **"Acompanhar na tela de bloqueio"** — só essa pessoa
aparece, e desmarcar encerra a Live Activity na hora.

## Pausar é visível

Pausar o compartilhamento não faz a pessoa sumir: a pausa vai para o banco
(`locations.sharing_paused` / `paused_at`, migração 0006) e a família vê
"Pausado há 20 min", com o pin cinza e sem o lugar de antes da pausa — mostrar
"🏠 Casa" ali seria dizer onde a pessoa está justamente quando ela pediu para
não dizer. Quem pausa lê isso no próprio botão, antes de pausar.

O `updated_at` **não** é tocado ao pausar, então a última posição continua
datada de quando foi de fato registrada.

## No carro

Acima de 25 km/h ninguém está a pé nem correndo, então a pessoa ganha um crachá
`🚗 68 km/h` embaixo do pin, um ícone de carro na lista e a velocidade no lugar
do "Parou há X". Não é alerta, não notifica e não tem limite para configurar: é
informação passiva, do mesmo tipo que a bateria.

Existiu antes uma versão com notificação de excesso de velocidade — foi removida
por soar como vigilância. O que interessa é ver que a pessoa está dirigindo, não
julgar a que velocidade.

## Quem está junto

Duas pessoas a menos de 120 m estão, para o app, no mesmo lugar. Isso vira:

- **Um pin só no mapa**, com os avatares sobrepostos e "3 juntos". Toque abre o
  grupo em pins separados e aproxima a câmera; o botão "Família toda" fecha de
  novo. Sem isso, a família reunida na casa da vó vira uma pilha ilegível.
- **"com 👦 Duda e 👵 Vovó"** na linha da pessoa e um cartão no perfil dela.

Quem está pausado ou com posição velha fica **fora** dos grupos: dizer "está com
a Ana" a partir de um ponto de uma hora atrás seria inventar.

## Por que não existe previsão de chegada

O app já teve um "chega ~17:13" calculado por `MKDirections` na saída, e um aviso
quando o relógio passava disso. Foi **removido inteiro**.

O motivo é que a previsão era um palpite vestido de compromisso: uma rota **de
carro** calculada uma única vez, que não sabe do trânsito que apareceu depois, do
desvio, da parada no posto, nem de quem na verdade foi a pé ou de ônibus. Só que
a família não lê "estimativa" — lê "ela devia ter chegado". Errar isso não custa
uma notificação inútil, custa um susto.

Ficou o que é fato: para onde a pessoa vai, desde quando saiu, e o aviso quando
chega. Continua existindo um aviso se quem viaja fica **25 min sem se mover**,
com texto que já oferece a explicação provável ("pode ser trânsito ou uma
parada") e sem tratar como emergência. Só o alarme de pânico é urgente.

A coluna `trips.eta` continua no banco, sem uso — nada escreve nem lê.

## Gênero nos textos

O app não sabe o gênero de ninguém e não pergunta, então os status usam verbo em
vez de adjetivo: **"Parou há 12 min"**, não "Parado há 12 min" — que sairia
errado para metade da família ("Ana está parado").

## Silenciar avisos

Uma soneca (1 h, 8 h, até amanhã de manhã) que cala **tudo menos o alarme de
pânico**. Ela cobre chegadas, saídas, bateria, viagens, pausas, velocidade e
toques; o SOS nunca consulta a soneca, que é justamente o ponto.

## "Cheguei bem"

O contrário do botão de pânico, no topo da lista da família. Se havia uma viagem
em andamento, chegar bem também encerra a viagem — um botão só. O aviso usa a
tabela `alerts` com `kind = 'checkin'` e é encerrado pelo próprio remetente, para
os aparelhos não disputarem o mesmo `update`.

## Widget da tela de início

O widget (tamanhos pequeno e médio) mostra a família sem abrir o app: quem está
em emergência aparece primeiro, depois os demais em ordem alfabética, com o
lugar marcado ou o endereço aproximado e a bateria em vermelho abaixo de 20%.

Ele **não** fala com o Supabase — extensões rodam em outro processo e não teriam
a sessão. Em vez disso o app grava um retrato em JSON no App Group
`group.com.matheus.familia` (`ActivityShared/FamilySnapshot.swift`) sempre que a
lista de membros muda, e chama `WidgetCenter.reloadTimelines`. O widget só lê
esse arquivo. Sem o App Group nos dois alvos, `containerURL(...)` devolve `nil` e
o widget mostra apenas o exemplo da galeria — as entitlements estão declaradas no
`project.yml` para `Familia` **e** `FamiliaWidgets`, e precisam continuar iguais.

## Recursos

- Mapa em tela cheia com pins de avatar (pulso quando em movimento, badge de bateria)
- Status "Em movimento / Parado **há X min**" por membro
- **Live Activity + Dynamic Island** na tela de bloqueio, opt-in por pessoa
- **Widget da tela de início** nos tamanhos pequeno e médio
- Lugares da família (casa, trabalho, casa da vó) com aviso de chegada e saída
- Alarme de pânico (SOS) com alerta em tela cheia, pin vermelho e Live Activity
- **"Cheguei bem"** num toque, e **soneca** que cala tudo menos o pânico
- **Pausa visível** para a família, e crachá **🚗 velocidade** de quem está no carro
- **Quem está junto** vira um pin só no mapa, que abre ao toque
- Viagens ("estou a caminho"), aviso de bateria baixa, "cutucar" alguém e linha do tempo do dia
- Trilha percorrida, distância até cada membro, rota até o membro
- Globo 3D quando alguém está do outro lado do mundo
- App de Apple Watch com a lista da família
- Família por código de convite, RLS garantindo que só a família vê sua localização
