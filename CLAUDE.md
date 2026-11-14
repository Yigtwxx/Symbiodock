# Symbiodock

MacBook çentiğini yaşayan bir adaya çeviren macOS uygulaması. İsim "symbiote" + "dock"
birleşimi; yazımı her yerde `Symbiodock`.

Tam tasarım: `docs/superpowers/specs/2026-11-14-symbiodock-v1-design.md`. Kod yazmadan
önce onu oku; bu dosya yalnızca özet ve karar kaydıdır.

## Ürün

- Fare üzerine gelince ada büyür, ayrılınca küçülür.
- Çalan müzik gösterilir: kapalıyken çentiğin solunda kapak, sağında seviye çubukları;
  açıkken kapak, parça, sanatçı, ilerleme ve önceki / oynat-duraklat / sonraki.
- Ada fareyle tutulup çentikten koparılabilir. Çekilirken Venom benzeri yapışkan lifler
  uzar, incelir ve bir eşikte kopar. Bırakılınca en yakın kenara ya da köşeye yerleşir.
- Proje v1'den sonra büyüyecek (yeni widget'lar). Her birim küçük bir arayüzün arkasında
  durmalı.

## Stack

- Swift 6, SwiftUI (görünümler) + AppKit (pencere)
- En düşük macOS: 14.0
- Agent uygulama (`LSUIElement = true`), sandbox kapalı, App Store dışı dağıtım
- Geliştirme makinesi: macOS 27.0.1, Swift 6.4.2
- Lisans: GPL-3.0
- Arayüz dili: yalnızca İngilizce (dil desteği çok sonra)

## Karar kaydı (2026-11-14)

| Konu | Karar | Gerekçe |
|---|---|---|
| Teknoloji | Swift/SwiftUI, native | Çentik penceresi, pencere seviyesi ve medya erişimi native API istiyor |
| İsim | Symbiodock | GitHub'da ve web'de bu isimde repo/ürün bulunmadı |
| Ada sayısı | Tek ada taşınır, çentik boş kalır | Tek pencere, tek durum; çoklu ada sonraya |
| v1 kapsamı | Müzik + hover büyüme + sürükleme/venom efekti | Riskli parçalar önce kanıtlanmalı |
| Müzik kaynağı | İkisi de tek `NowPlayingProvider` arayüzü arkasında: `MediaRemoteProvider` ve `AppleMusicProvider` | Uygulama genel olacak; Apple sistem geneli veriyi macOS 15.4'ten beri kısıtlıyor, tek kaynağa bağlanmak riskli |
| Sahibin kullandığı müzik uygulaması | Apple Music | İlk doğrulanacak kaynak bu |
| Efekt tekniği | SwiftUI `Canvas`: incelen şerit lifler, altta metaball katmanı (blur + alpha threshold), üstte net çizim; yetmezse Metal shader | Araştırma ve prototip: daire zinciri boncuk gibi duruyor, ince lifler filtrede kayboluyor (spec 5.6) |
| Kenara tutunma | Kopmuş ada bir kenara (~70 pt) ya da çentiğe yaklaşınca lifler uzanıp tutunur; lifler tutunmuşken bırakılırsa o yüzeye yapışır, açıkta bırakılırsa en yakın kenara gider (2026-11-14) | Sahibinin isteği: "ortada durmasın, yapışkanmış gibi; yaklaşınca yine venom efekti, bırakınca o kenara yapışsın" (spec 5.5, 5.6) |
| Çentik dışı konum | `visibleFrame` kenarına sıfır mesafe, çentik gibi: kenara değen köşeler köşeli, serbest köşeler yuvarlak (2026-11-14; önceki: 8 pt içeride yüzen kapsül) | Sahibi: "tamamen 0 olsun, kenara direkt çentik gibi dursun"; menü çubuğunu ve Dock'u yine kapatmaz |
| Yan kenarda dikey ada | Sağ/sol kenarda kapalı ada 36 × 170 pt dikey şerit: üstte platform simgesi, ortada 90° döndürülmüş parça adı, altta seviye çubukları; hover'da kenardan içeri 480 × 170 açılır. Köşeler ve üst/alt kenar yatay kalır (2026-11-14) | Sahibi: "sağa veya sola yapışırsa dikey yapışsın"; açık ada şeritten kısa olursa hover titrer (spec: `2026-11-14-side-docking-design.md`) |
| Platform simgesi | Yalnızca dikey şeritte. Music/Spotify: uygulama simgesi. Tarayıcı: Safari ve Chrome'a AppleScript ile sekmeler sorulur, YouTube/Kick/Twitch logosu gösterilir (Simple Icons, CC0); izin yoksa tarayıcı simgesi (2026-11-14) | Sahibi: "yt ise yt"; sistem yalnızca tarayıcıyı söylüyor, site için Automation izni şart ve sahibi onayladı |
| Sekmeler | Açık adada sekme şeridi: `Agents` ve `Media`. Sıra sağ tık menüsünde `First tab` ile seçilir ve saklanır; varsayılan `Agents` birinci. Hover'da birinci sekme açılır; bir agent ilgi bekliyorsa `Agents` açılır (2026-11-14) | Sahibi: "sekmeler halinde olsun... kullanıcı seçebilsin hangisini 1 hangisini 2" |
| AI agent oturumları | Yalnızca dosya ve süreç listesi okunur; hook yok, hiçbir aracın dizinine yazılmaz. Claude Code ve Codex tam durumla; Gemini CLI, Cursor Agent, OpenCode, Aider, Copilot CLI süreç düzeyinde (`Running`). Satıra tıklayınca oturumun uygulaması öne gelir; adadan cevap verilmez (2026-11-14) | Sahibi: "hook veya herhangi bir hata olmasın"; "hepsi olsun, geri dönüş yaparlar biz düzeltiriz" (spec: `2026-11-14-agents-tab-design.md`) |
| Agent ilgi belirteci | Soru ya da izin bekleyen oturum adayı kendiliğinden açmaz. Kapalı adada durum işareti (kırmızı `#FF4D4F` halka, "kapıyı çalan" nokta) ve kenar ışığı; biten oturum için nane yeşili onay işareti, `Agents` sekmesi açılınca silinir (2026-11-14) | Sahibi: "direkt açılmasın, belirtici bir ibare olsun"; düz kırmızı/yeşil noktayı "çok basic" buldu; renk mercandan kırmızıya çekildi, çünkü pet'ler araç renginde ve Claude turuncusuyla karışmasın ("soru bekliyor kısmını başka bir renk yaparız") |
| Agents listesi | Açık adada aynı anda en fazla 2 oturum alt alta görünür, fazlası aşağı kaydırılır (2026-11-14) | Sahibi: "alt alta gözüksün max 2 tane gözüksün aşağıya kaydırılabilsin" |
| Araç pet'leri | Her araç, tanındığı figürle gösterilir (Claude Code: köşeli yaratık, Codex: bulut...). Figür 17×17 ızgarada çizilir, her sütun yuvarlak uçlu ince bir çizgidir (çizgi = boşluk), parçalar üç derinlikte durur (öndeki tam renk, arkadaki soluk) ve aracın kendi rengindedir. Çalışırken çizgiler yalnızca çok az kıpırdar. Logo dosyası paketlenmez (2026-11-14) | Sahibi: "o ai ile özdeşleşmiş şeyin petini çiz... ElevenLabs'in I ı gibi çizgilerle yaptığı tasarım ile yap. Çok düzgün ve güzel yapmanı istiyorum"; "her araç kendi renginde"; 7 kalın çubuklu ilk hâl için: "çok basit olmuş, çizgileri daha ince yap ve daha detaylı olsunlar", "çubuklara derinlik kat, bazıları arkada duruyormuş gibi"; hareket için: "minik minik uzayıp küçülsün... gözü yormasın, büyük hareketler olmasın" |
| Mimari | Spec bölüm 4-5 | Sahibi onayladı |
| Proje üretimi | XcodeGen (`project.yml`), `.xcodeproj` commit edilmez | Komut satırından üretilebilir ve diff'i okunur |
| Kod yerleşimi | Saf mantık `Packages/SymbiodockCore` paketinde, AppKit/SwiftUI app hedefinde | Mantık uygulama açılmadan `swift test` ile test edilir |
| Telif satırı | `Yigtwxx` | Sahibinin tercihi |
| Lisans | GPL-3.0 (MIT'ten değiştirildi) | Kaynak açık + ücretli hazır sürüm modeli; kapalı kaynak kopyaları engeller |
| Dağıtım | Ücretsiz: GitHub'dan clone edip derleme. Ücretli: web sitesinden hazır sürüm indirme, lisans anahtarı yok | Sahibinin iş modeli; kaynak açıkken anahtar kontrolü anlamsız |
| İmzalama, site, ödeme | Uygulama bitince ele alınacak; o zamana kadar ad-hoc imza | Sahibi: "site kısmı en son" |
| Görünüm | v1'de düz siyah; kişiselleştirme sonra | Sahibinin tercihi |
| Tam ekran | Ada tam ekran uygulamaların üstünde de görünür kalır | Sahibinin tercihi |
| Girişte başlatma | v1'de var, ada menüsünde aç/kapa (milestone 5) | Sahibinin tercihi |
| Duraklatılmış parça | Kapalı adadaki kanatlar duraklatmadan 10 sn sonra gizlenir; açık ada parçayı göstermeye devam eder (2026-11-14) | Sahibinin seçimi; duraklatılmış bir sekme çentiği gün boyu kaplamasın |
| Menü | Menü çubuğunda öğe yok; menü adaya sağ tıkla açılır (2026-11-14) | Sahibi menü çubuğunda ikon istemedi; ileride başka özellikler için oraya öğe gelebilir |
| Geri bildirim | Kopma, liflerin bir yüzeye tutunması ve (tutunmadan) bırakma anında trackpad titreşimi, ses yok | Sahibinin tercihi |
| Arayüz dili | Tamamen İngilizce; çeviri altyapısı kurulmaz | Dil desteği çok sonra gelecek |
| v1 sonrası widget'lar | İlki: sekmeler ve `Agents` sekmesi (2026-11-14). Sonrakiler kararlaştırılmadı | Sahibi sonra söyleyecek; sorma, o açana kadar bekle |
| Depo | `Yigtwxx/Symbiodock`, public | Sahibinin isteği |

## Git

- Bu projede sahibi açıkça izin verdi: iş parça parça commit edilir ve PR açmadan
  doğrudan `main`'e push edilir (2026-11-14). Force-push için yine sor.
- Conventional Commits; başlık en fazla 72 karakter, emir kipi, gövdede "neden".
- Secret, `.env`, anahtar dosyaları asla commit edilmez.

## Durum

- Faz 0-2 tamam ve sahibi elle doğruladı: çekirdek paket, agent uygulama, çentik adası,
  hover, tıklama geçişi.
- **Faz 3, 4, 5, 6 ve yan kenar: sahibi 2026-11-14 gecesi elle kontrol listelerinin hepsini
  denedi ve "her şey düzgün çalışıyor, doğrulandı" dedi.** v1 doğrulanmış sayılır. Listeler
  kendi plan dosyalarının sonunda duruyor.
- Menü çubuğunda öğe yok; menü adaya sağ tıkla açılır (Return to notch, Launch at login,
  Quit; gerekince Music access needed).
- Dağıtım öncesi sağlamlaştırma listesi `.superpowers/sdd/progress.md` içinde (git'e girmez);
  özeti: yardımcı sürecin zorla öldürülmesi, komut sıralaması, Release ve Intel derlemesinin
  perl altında denenmesi.
- Faz 7 (sekmeler ve Agents sekmesi, 2026-11-14): spec onaylandı, iki plan yazıldı
  (`2026-11-14-agents-tab-core.md`, `2026-11-14-agents-tab-app.md`), uygulama sürüyor.
  Sahibi "başla ve bitir" dedi.
- Xcode 27.2 ve XcodeGen 2.45.4 kurulu, `xcode-select` ile seçili.

## "Yapılacakları yap" denince

Sahibi "yapılacakları yap", "devam et", "başla" gibi bir şey derse ne yapılacağını sorma;
bu bölümü uygula.

1. Yol haritasındaki tüm fazları görev listesine ekle. İşaretlenmemiş ilk fazdan başla.
2. Her oturumun başında Faz 0'ı yeniden kontrol et; işaretli olsa bile.
3. Fazın planı varsa görev görev uygula: `superpowers:subagent-driven-development`.
   Subagent kullanılamıyorsa `superpowers:executing-plans`.
4. Fazın planı yoksa: tasarım onaylı olduğu için brainstorming yapma. Spec'ten
   `superpowers:writing-plans` ile `docs/superpowers/plans/` altına o fazın planını yaz,
   commit + push et, onay beklemeden uygulamaya geç.
5. Her görev sonunda: testler ve build temiz → commit → `main`'e push.
6. Her faz sonunda: yol haritasında kutuyu işaretle, bu dosyadaki `Durum`u güncelle,
   commit + push. Sonra dur ve sahibine o fazın elle kontrol listesini ver. Görsel
   davranış (hover, sürükleme, efekt) testle doğrulanamaz; sahibi onaylamadan sonraki
   faza geçme. Kendin doğrulayabildiğini (`scripts/list-windows.swift`, ekran görüntüsü)
   önce kendin doğrula.

Durup sorulacak durumlar:

- `sudo` isteyen her komut. Sahibi kendisi çalıştırır.
- macOS izin penceresi (Automation, Accessibility, Input Monitoring).
- Spec'te yazmayan bir ürün kararı.
- Spec'te adı geçmeyen yeni bir üçüncü taraf bağımlılık.
- Force-push, repo ayarı değişikliği, PR.

Durmadan devam edilecek durumlar:

- Bir deneme başarısız olur ve spec'te yedeği yazıyorsa: yedeğe geç, sonucu bu dosyadaki
  "Doğrulanmamış varsayımlar" bölümüne yaz, faz raporunda belirt.
- Build ya da test hatası: `superpowers:systematic-debugging` ile çöz. Üç denemede
  çözülmezse dur ve kanıtıyla raporla.
- Plandaki kod derlenmezse (planlar derlenmeden yazıldı): davranışı ve arayüzleri koruyarak
  düzelt, planı da aynı commit'te güncelle.

## Yol haritası

- [x] **Faz 0 — Ön koşullar.** `xcodebuild -version` ve `xcodegen --version` çalışıyor.
      Plan: milestone 0-1 planı, Görev 0.
- [x] **Faz 1 — Milestone 0: iskelet.** Çekirdek paket (geometri, durum, yerleşim) testleriyle;
      agent uygulama açılıyor; menüsünden çıkılabiliyor.
      Plan: `docs/superpowers/plans/2026-11-14-m0-m1-notch-island.md`, Görev 1-3.
- [x] **Faz 2 — Milestone 1: çentik adası.** Şeffaf panel çentikte; hover ile büyüyor ve
      küçülüyor; ada dışındaki tıklamalar alttaki uygulamaya geçiyor.
      Plan: aynı dosya, Görev 4-5.
- [x] **Faz 3 — Milestone 2: Now Playing.** Plan yok, yazılacak (spec 5.7, 5.8). İlk görev
      `mediaremote-adapter` denemesi ve lisansının GPL-3.0 uyum kontrolü. Bitince: en az
      Apple Music'ten gerçek parça bilgisi ve çalışan önceki / oynat-duraklat / sonraki;
      kapalı adada solda kapak, sağda seviye çubukları.
- [x] **Faz 4 — Milestone 3: sürükleme ve yapışma.** Kod tamam, elle kontrol bekliyor.
      Çekirdek planı: `docs/superpowers/plans/2026-11-14-m3-core-drag-and-snap.md`. Pencere ve
      sürükleme: `docs/superpowers/plans/2026-11-14-m3-m4-window-drag-and-effect.md` (elle
      kontrol listesi ve bilinen eksikler orada).
- [x] **Faz 5 — Milestone 4: symbiote efekti.** Kod tamam, elle kontrol bekliyor. Simülasyon
      testli; görünüm ve sürüklemenin her aşaması ekran dışı görüntülerle doğrulandı, canlı
      denenmedi. Aynı plan dosyası.
- [x] **Faz 6 — Milestone 5: girişte başlatma.** Kod tamam, elle kontrol bekliyor.
      Plan: `docs/superpowers/plans/2026-11-14-m5-launch-at-login.md`. Ada
      menüsünde "Launch at login" aç/kapa.

v1 bunlarla biter.

- [ ] **Faz 7 — Sekmeler ve Agents sekmesi.** Spec:
      `docs/superpowers/specs/2026-11-14-agents-tab-design.md`. Planlar: önce
      `docs/superpowers/plans/2026-11-14-agents-tab-core.md` (çekirdek, 6 görev), sonra
      `docs/superpowers/plans/2026-11-14-agents-tab-app.md` (uygulama, 6 görev; elle kontrol
      listesi sonunda).

Sonrası (başka widget'lar, kişiselleştirme, dil desteği, imzalama, site) için sahibi ayrıca
yön verecek; kendiliğinden başlama.

## Doğrulanmamış varsayımlar

Bunlar denenmedi; ilgili milestone'da ilk iş olarak doğrulanacak. Her birinin yedeği
spec'te yazılı.

- `mediaremote-adapter` v0.7.7 macOS 27.0.1'de çalışıyor (2026-11-14'te denendi): `get` ve
  `stream` Safari'den gerçek veri ve kapak döndürdü, `test` çıkış kodu 0. Lisansı
  BSD-3-Clause, GPL-3.0 ile uyumlu. `send` (oynatma komutları) henüz denenmedi. CMake
  gerekmiyor; kaynakları doğrudan derlenebiliyor. Canlı yayında `duration` anlamsız büyük
  geliyor (9.2e12); ilerleme çubuğu bunu yok saymalı.
- `com.apple.Music.playerInfo` bildirimi macOS 27'de geliyor mu.
- Claude Code oturum dosyası (`~/.claude/sessions/<pid>.json`, sürüm 2.1.325) bir soru
  açıkken `status: "waiting"`, `waitingFor: "input needed"` yazıyor (2026-11-14'te canlı
  görüldü). İzin penceresinde de aynısını yazdığı ve `/clear` sonrası `sessionId`'nin
  güncellendiği denenmedi. Codex rollout'larında onay/soru bekleme olayı bulunmadı.
  Yedekleri: Agents spec bölüm 11.
- Fare izleme: `NSEvent` monitörleri macOS 27'de izin istemeden çalışıyor (sahibi 2026-11-14'te
  elle doğruladı; Dock boyutu değişimi maddesi denenmedi).

## Doğrulama

```bash
swift test --package-path Packages/SymbiodockCore
```

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```

```bash
open build/Build/Products/Debug/Symbiodock.app
```

```bash
swift scripts/list-windows.swift
```

```bash
pkill -x Symbiodock
```

`Symbiodock.xcodeproj` commit edilmez; `project.yml` değişince `xcodegen generate` yeniden çalıştırılır.
