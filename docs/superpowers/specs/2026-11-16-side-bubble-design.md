# Yan baloncuk (2026-11-16)

## İstek

Sahibi: "iphonelarda adada bir şey varsa 2. bir şey gelince yuvarlak olarak sağa veya sola
geçiyor. Bizde de öyle olsun mesela first page agent olsun agent çalışırken müzik kısımları
sola yuvarlak olarak geçsin yine arka arkaya efekti bozulmasın ama bu sefer yuvarlak olsun."

Seçtikleri: simetrik (ilk sekme adada, ikincisi baloncukta); baloncuğun üstüne gelince kendi
sekmesi açılır; şimdilik yalnızca çentikte; baloncuk solda.

## Davranış

- Baloncuk, ada çentikte ve kapalıyken, iki sekmenin de yüzü varsa çıkar: `mediaWings` (çalıyor
  ya da 10 sn'den kısa süredir duraklatılmış) ve `board.hasFace` (çalışan, soran, compact yapan
  ya da mührü oynayan oturum).
- İlk sekmenin yüzü bugünkü gibi adada kalır; ikinci sekme baloncuğa geçer.
- Ada açıkken, sürüklenirken, yerleşirken ya da çentik dışında dururken baloncuk yoktur.
- Biçim: siyah daire, çap 28 pt (çentik 32 pt'den kısaysa çentik boyu − 4), adanın sol kenarından
  6 pt boşlukla, çentik bandında dikey ortalı.
- Müzik baloncuğu: daire içinde 22 pt daire kapak. İkinci kaynak varsa arkasında ikinci bir
  siyah daire: %84 boyda, kapağı %70 opaklıkta, solundan çapın %36'sı kadar taşar.
- Agent baloncuğu: `board.lead`'in pet'i 18 pt. Mührü oynayan bitişte `FinishSeal` aynı yerde
  oynar; oturum yerleşince `hasFace` düşer ve baloncuk gider.
- Adanın sağ kanadı, kenar ışığı ve compact çizgisi değişmez. Agent baloncuktayken compact
  çizgisi çizilmez (bugünkü kural: yalnızca agents yüzünde); pet'in dalgası yine aşağı akar.
- Geçiş: baloncuk adanın sol kenarının arkasından kayıp büyüyerek çıkar, aynı yoldan döner
  (adanın yayıyla). Reduce Motion'da yalnızca solar.
- Hover: imleç baloncuğun üstünde beklerse ada açılır ve baloncuğun sekmesi seçilir; ilgi
  bekleyen agent bu seçimi ezmez. Adanın üstünde beklerse bugünkü kural geçerli. Baloncuk
  sürüklenmez; üstünde basılan düğme sürükleme başlatmaz.
- Sağ tık menüsü baloncukta da açılır (panelin tamamı aynı görünüm).

## Risk

Baloncuk çentiğin solunda yaklaşık 70 pt (iki kaynakta 80 pt) kaplar. Menüsü çok olan
uygulamalarda son menünün üstüne binebilir ve imleç oradayken o menü tıklanamaz. Menülerin
nerede bittiğini veren bir API yok; rahatsız ederse baloncuk sağa alınır.

## Yapı

- Çekirdek:
  - `TabSelection.bubble(order:mediaHasFace:agentsHasFace:) -> IslandTab?`: ikisinin de yüzü
    varsa sırada ikinci olan sekme.
  - `IslandState.bubbleTab`: yukarıdaki, yalnızca `anchor == .notch && phase == .collapsed` iken.
  - `IslandState.setHovering(_:opening:)`: verilen sekmeyle açar.
  - `IslandLayout.bubbleDiameter(notch:)`, `bubbleFrame(notch:screenSize:hasBehind:)`,
    `bubbleHitRect(...)`; sabitler `bubbleGap`, `bubblePeek`.
- Uygulama:
  - `SideBubble` (`Symbiodock/Island/SideBubble.swift`): daire, içerik, arkadaki daire.
  - `ArtworkView`'e daire seçeneği.
  - `AgentFacePet` paylaşılır ve boyut alır.
  - `IslandView`: baloncuk adanın altında, aynı panelde.
  - `OverlayController`: isabet alanı ada ∪ baloncuk; hover tetiklenince imleç baloncuktaysa
    onun sekmesi açılır.
- Deneme: `SYMBIODOCK_DEMO_AGENTS=working` ile `SYMBIODOCK_DEMO_MEDIA=1|2` birlikte; ekran dışı
  görüntü `collapsed-bubble.png`.

## Kapsam dışı

Kenara yanaşık adada baloncuk; adadan damla gibi kopan metaball geçişi; baloncuğun çevresinde
ışık; ikiden fazla sekme.
