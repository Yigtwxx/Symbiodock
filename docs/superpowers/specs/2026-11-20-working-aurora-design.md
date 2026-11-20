# Çalışma ışığı: kuzey ışığı, canlı pet, renkli yay, uydular (2026-11-20)

## İstek

Sahibi: "agent çalışırkenki animasyon çok sönük kaldı, basit yani. Oraya ne yapabiliriz,
creatif fikirler lazım."

Dört tur canlı taslak üzerinden seçti (taslaklar `.superpowers/brainstorm/` altında, git'e
girmez; son sayfa `eyes-v5.html`, seçilen kart "Yedek 2: Kuzey ışığı", renk düğmesi `Canlı`):

- İlk turda "Fikir 3"ü (alt ajan uyduları) işaretledi.
- İkinci turu "genel olarak yine beğenmedim... rengi çok soluk bu haliyle" diye geri çevirdi.
- Üçüncü turda: "kuzey ışıkları güzel".
- Son karar: "tamam ya karar verdim. Yedek 2 canlı. Bu olsun".

Seçtiği kartta ışığın yanında renkli yay ve renkli uydular da vardı. Bunların kapsamda
olması, yanaşık adada ışığın serbest uzun kenarda yanması ve baloncukta ışık olmaması benim
önerimdi; sahibi "önerileri yap" dedi. Aşağıdaki sayılar taslaktan alındı; taslakta olmayan
her ayrıntı benim önerim.

Gözler, kılık değiştiren pet ve goo damlaları seçilmedi; kapsam dışı.

## Davranış

### Kuzey ışığı

- **Ne zaman.** Ada kapalıyken (`phase == .collapsed`), yüzü agent'ı gösterirken
  (`face == .agents`), öndeki oturum çalışırken (`board.lead?.state == .working`) ve agent
  ışığı yokken (`board.attention == .none`). Soru bekleyen, biten (bitiş efekti dahil),
  compact yapan, yalnızca süreç düzeyinde görülen (`Running`) ya da boştaki oturumda yanmaz.
  Ada açıkken, sürüklenirken ve agent sol baloncuktayken (adanın yüzü müzik) yanmaz.
- **Nerede.** Adanın serbest uzun kenarının hemen dışında: çentikte alt kenar; üst ya da alt
  kenara yanaşık kapsülde ekrana değmeyen uzun kenar; yan kenardaki dikey şeritte içeri bakan
  uzun kenar; köşeye yanaşık kapsülde ekrana değmeyen uzun kenar. Işık adanın içine çizilmez.
- **Görünüm.** İki parça, aynı renk akışını paylaşır:
  - kenarın hemen dışında 1 pt'lik net çizgi; iki ucu 9 pt içeriden başlar ve uçlara doğru
    söner (köşe yuvarlaklığına girmez);
  - çizginin altında yumuşak bir hale: kenar boyunca uzanan, kenarda en güçlü olup kenardan
    dışarı 9 pt'de sıfıra inen bir parlaklık; uçları kenarın uçlarından 8 pt içeride biter ve
    14 pt boyunca söner.
- **Renk.** Öndeki oturumun aracının dört ışık rengi (aşağıda), sırayla ve kenar boyunca
  kesintisiz dönen bir geçiş olarak.
- **Hareket.** Renkler kenar boyunca akar: yatayda soldan sağa, dikey şeritte yukarıdan aşağı,
  3,2 sn'de bir tur, sabit hızla. Hale nefes alır: 2,4 sn'de bir, parlaklığı %60 ile %100,
  kenardan uzanışı 0,75 ile 1,3 kat arasında gidip gelir (yavaşlayarak). Net çizgi nefes
  almaz, yalnızca akar.
- **Belirme.** Koşul sağlanınca 0,35 sn'de belirir, bozulunca 0,35 sn'de söner. Işığın bandı
  hep kapalı adanın bandıdır: ışık yerinde belirir ve yerinde söner; ada açılırken ya da
  kapanırken onunla birlikte yol almaz.
- **Diğer ışıklar.** `RimLight` (amber, nane), `CompactingRim` (mor) ve parça ışığı adanın
  içinde çizilir ve değişmez. Kuzey ışığı onlarla aynı anda görünmez: koşulu hepsini dışlar
  (parça ışığı yalnızca yüz müzikken yanar).
- **Reduce Motion.** Akış ve nefes yok: ışık %80 parlaklıkta, tek kat uzanışla sabit durur.
- **Fare.** Işık tıklama ve hover almaz; altındaki uygulamaya geçer. Adanın hover alanı
  değişmez.

### Işık renkleri

Her aracın dört rengi; pet'inin tonları ve komşu tonlar. Sıra, geçişteki sıradır.

| Araç | Renkler |
|---|---|
| Claude Code | `#FFB347` `#FF4D6D` `#FF7A3D` `#FFD166` |
| Codex | `#39C8FF` `#A259FF` `#5B7CFF` `#E05CFF` |
| Gemini CLI | `#3C87FF` `#FF78A5` `#9669FF` `#5CD0FF` |
| Cursor Agent | `#FAFAFC` `#B9C6FF` `#BEBECC` `#E6D9FF` |
| OpenCode | `#FFE8AA` `#FF9F5A` `#F0AF4B` `#FFD98A` |
| Aider | `#D2FA46` `#39D353` `#64DC28` `#F2FF7A` |
| Copilot CLI | `#A078FF` `#FF69BE` `#C86BFF` `#FF9AD5` |

Bugün yalnızca Claude Code ve Codex `working` durumuna girer; diğer beşi süreç düzeyinde
(`Running`) görüldüğü için ışıkları yanmaz. Renkleri, durum okuyucuları eklenince hazır olsun
diye tanımlanır. Hiçbiri soru amberi (`#FFD60A`), bitiş nanesi (`#63E6A9`) ya da compact
moru (`#BF5AF2`) değildir.

### Canlı pet rengi

Bütün pet'ler, her yerde (kapalı ada, baloncuk, açık adadaki liste) parlar. Taslaktaki
`Canlı` seviyesinin karşılığı:

| Ne | Önce | Sonra |
|---|---|---|
| Claude Code renkleri | `#F5965F` `#EB7046` `#CD4E30` | `#FFAA64` `#FF7A3D` `#F04E28` |
| Codex renkleri | `#4096FF` `#8C52FF` | `#3CAFFF` `#6973FF` `#A550FF` |
| OpenCode'un ikinci rengi | `#F0AF4B` | `#FFBA50` |
| Aider renkleri | `#D2FA46` `#64DC28` | `#D6FF47` `#74FF2E` |
| Gölge tonları | kabartmanın verdiği ton | her ton tam renge %38 yaklaşır (yeni `shadeLift` = 0,62); en soluk ton %36'dan %60'a çıkar |
| Figürün dışındaki çizgiler (`groundStrength`) | 0,085 | 0,12 |
| Dalgada bekleyen çizgi (`waveRest`) | %82 | %92 |
| Çizgi kalınlığı (`barShare`) | 0,60 | 0,68 |

Gemini, Cursor ve Copilot renkleri zaten en parlak değerinde; değişmez.

Bu sayılar başlangıçtır: taslağın çizimi uygulamanınkiyle birebir aynı değil. Değişiklikten
sonra `pets.png` yeniden üretilir, önceki hâliyle yan yana sahibine gösterilir; kabartma hissi
fazla düzleşirse `shadeLift` 0,62 ile 1 (hiç açma) arasında geri çekilir. `faintestShade`
(kabartmanın taban sınırı, %36) değişmez; açma ondan sonra uygulanır. Sahibi daha önce (2026-11-15)
"renkleri bi tık daha parlatalım ama çok abartmadan" demişti; bu kez taslakta `Canlı`yı seçti.

### Renkli yay

Çalışan oturumun dönen yayı beyaz yerine aracının ışık renklerinden bir geçiştir (ilk renkten
ikinci renge, sol üstten sağ alta). Geçiş yerinde durur, yay üstünde döner: yay dönerken rengi
değişir. İşaretin aracı bildiği her yerde geçerlidir: kapalı adanın yüzleri ve açık adadaki
liste satırları. Araç verilmeyen yerde yay beyaz kalır. Diğer durumların işaretleri (soru,
bitiş, compact, `Running`, boşta) değişmez.

### Alt ajan uyduları

- **Ne.** Kapalı adanın yüzlerinde (çentik, kenara yanaşık kapsül, dikey şerit), öndeki oturum
  çalışırken, çalışan her alt ajan dönen yayın etrafında dolanan 3 pt'lik bir nokta olur.
  Açık adadaki listede uydu yoktur; orada dallar zaten yazıyla görünür. Baloncukta işaret
  olmadığı için uydu da yoktur.
- **Kaç tane.** Çalışan alt ajanlar, en eskisi önce, en fazla 5. Fazlası gösterilmez.
- **Yörünge.** Noktanın merkezi işaretin merkezinden 11 pt uzakta (14 pt'lik işaret için).
  Her nokta saat yönünde, kendi hızında döner: tur süresi 2,3 ile 4,3 sn arasında, başlangıç
  açısıyla birlikte alt ajanın kimliğinden hesaplanır (aynı alt ajan her çizimde aynı yerde
  ve hızda). Bir yüzde yörünge adanın kenarına taşıyorsa o yüzde işaretin kenar boşluğu
  yörünge sığacak kadar açılır.
- **Renk.** Aracın dört ışık renginden biri: uydu, kimliğinin verdiği renkte olur; ondan önce
  gösterilen biri zaten o renkteyse sıradaki boş renk verilir. Önceki biten olursa sonraki
  kendi rengine geri döner, yani renk değişimi tamamen yok değildir.
- **Gelme, gitme.** Yeni alt ajanın noktası 0,4 sn'de büyüyerek belirir. Biten alt ajanın
  noktası olduğu yerde durur, nane yeşiline döner, 2,3 katına büyüyüp 0,9 sn'de kaybolur.
  Öndeki oturum çalışmayı bırakınca (soru, bitiş, compact) bütün uydular işaretle birlikte
  gider.
- **Reduce Motion.** Noktalar dönmez: çemberin üstünde eşit aralıkla durur; belirme ve
  kaybolma yalnızca opaklıkla olur.

Bu, "kapalı adada alt ajan göstergesi yok" kararını (2026-11-15) değiştirir.

### Maliyet

Hiçbir parça kare kare çizilmez: renk akışı, nefes, yayın dönüşü ve uyduların dönüşü Core
Animation'da çalışır; anahtar kareler çekirdekteki testli formüllerden örneklenir. Agent
çalışmıyorken ışığın ve uyduların görünümü yoktur. Hedef: `SYMBIODOCK_DEMO_AGENTS=working`
ile ışık yanarken `top`'ta %0 (bugünkü ölçümle aynı).

## Yapı

Çekirdek (`Packages/SymbiodockCore`, `swift test` ile test edilir):

- `IslandState.showsWorkingAurora`: yukarıdaki koşul. `showsCompactingRim`'in yanında.
- `WorkingAurora`: süreler ve ölçüler (akış 3,2 sn, nefes 2,4 sn, uzanış 9 pt, çizgi 1 pt,
  uç boşlukları), ışığın hangi kenarda yandığı (`edge(dockedEdges:isVertical:)`), o kenar için
  halenin ve çizginin dikdörtgenleri, nefesin bir andaki parlaklığı ve uzanışı (hem anahtar
  kareler hem ekran dışı görüntüler bunları kullanır).
- `AgentSatellites`: bir oturumun hangi alt ajanlarının uydu olduğu (çalışanlar, en eski önce,
  en fazla 5), her birinin kimliğinden tur süresi ve başlangıç açısı, renk sırası.
  `AgentRow` bunu taşır (`orbiters`); dallarla aynı yerde hesaplanır.
- `AgentPetFigure` ve `AgentPetMotion` sabitleri: tablodaki yeni değerler; gölge tonuna
  `shadeLift` uygulanır (`ton = 1 - (1 - ton) × 0,62`, parlayan kısımlar hariç).

Uygulama:

- `AgentPalette`: yeni pet renkleri; `aurora(for:)` dört ışık rengini verir.
- `WorkingAuroraLight` (`Symbiodock/Island/`): canlıyken Core Animation katmanları (kenarın iki
  katı uzunlukta, iki tur renk taşıyan bir geçiş katmanı bir tur kaydırılır; maskesi kenardan
  dışarı sönen hale ile ince çizgidir; halenin opaklığı ve ölçeği nefes alır). `frozenAt` ile
  SwiftUI bir anı çizer. `SharedClock` kullanır: görünüm pencereye dönünce hareket kaldığı
  yerden sürer.
- `IslandView`: ışık, `resting` adanın altında ayrı bir katmandır (ada içeriğini kırptığı için
  kırpmanın dışında olmalı); kapalı adanın çerçevesinden hesaplanan yere konur. Kanatlar ya da
  yer değişince adanın yayıyla taşınır; ada açılıp kapanırken taşınmaz, yerinde söner ve belirir.
  Kanatlar ışıkla aynı anda beliriyorsa belirme de o yayla olur. `RimLight`, `CompactingRim`,
  `TrackGlowLine` çağrıları değişmez.
- `AgentStatusMark`: isteğe bağlı `tool` (renkli yay) ve `orbiters` (uydular). Renkli yay,
  dönen yay maskesinin altındaki sabit bir geçiş katmanıdır. Uydular ayrı bir görünümdür
  (`MarkSatellites`), her nokta kendi dönen katmanında.
- `AgentFaces`: kapalı yüzler işarete aracı ve uyduları verir; `AgentsContent`: liste satırları
  yalnızca aracı verir.
- `DebugRender`: yeni `working-aurora.png` (çentikte Claude Code ve Codex, alt kenarda kapsül,
  sağ kenarda dikey şerit, nefesin iki ucu, uydularla); `pets.png`, `status-marks.png` ve
  `collapsed-faces.png` yeni görünümle yeniden üretilir.
- Demo: `SYMBIODOCK_DEMO_AGENTS=working` öndeki oturuma iki çalışan alt ajan verir (yalnızca
  Debug), ışık ve uydular canlı görülebilsin.

Testler: `showsWorkingAurora` doğruluk tablosu (her aşama, yüz, öndeki durum, dikkat);
kenar seçimi (çentik, dört kenar, dört köşe, dikey şerit); hale ve çizgi dikdörtgenleri;
nefes formüllerinin sınırları ve periyodu; uydu seçimi (yalnızca çalışanlar, sıra, 5 sınırı),
tur süresi ve açının kimlikten kararlı hesaplanması ve aralıkları.

## Doğrulama

- `swift test --package-path Packages/SymbiodockCore` ve Debug derlemesi temiz.
- Ekran dışı görüntüler: `working-aurora.png`, `pets.png`, `status-marks.png`,
  `collapsed-faces.png`.
- Canlı: `SYMBIODOCK_DEMO_AGENTS=working` ile uygulama çökmeden çalışır, `top`'ta CPU ölçülür.
- Canlı görünüm (akışın hızı, halenin gücü, uyduların okunurluğu, pet'in yeni parlaklığı)
  ekran görüntüsüyle görülemez; sahibinin elle kontrolüne kalır. Liste planın sonunda.

## Kapsam dışı

- Gözler, kılık değiştiren pet, goo damlaları ve taslaktaki diğer fikirler.
- Agent sol baloncuktayken ışık ya da uydu.
- Beşten fazla alt ajan için sayı göstergesi.
- Işık renklerinin ya da gücünün kullanıcı tarafından ayarlanması.
- `RimLight`, `CompactingRim` ve parça ışığında herhangi bir değişiklik.
- Süreç düzeyindeki beş araç için durum okuyucusu.
