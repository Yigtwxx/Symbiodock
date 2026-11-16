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
| Yan kenarda dikey ada | Sağ/sol kenarda kapalı ada 36 × 170 pt dikey şerit: üstte platform simgesi, ortada 90° döndürülmüş parça adı, altta seviye çubukları; hover'da kenardan içeri 540 × 170 açılır. Köşeler ve üst/alt kenar yatay kalır (2026-11-14) | Sahibi: "sağa veya sola yapışırsa dikey yapışsın"; açık ada şeritten kısa olursa hover titrer (spec: `2026-11-14-side-docking-design.md`) |
| Platform simgesi | Yalnızca dikey şeritte. Music/Spotify: uygulama simgesi. Tarayıcı: Safari ve Chrome'a AppleScript ile sekmeler sorulur, YouTube/Kick/Twitch logosu gösterilir (Simple Icons, CC0); izin yoksa tarayıcı simgesi (2026-11-14) | Sahibi: "yt ise yt"; sistem yalnızca tarayıcıyı söylüyor, site için Automation izni şart ve sahibi onayladı |
| Sekmeler | Açık adada sekme şeridi: `Agents` ve `Media`. Sıra sağ tık menüsünde `First tab` ile seçilir ve saklanır; varsayılan `Agents` birinci. Hover'da birinci sekme açılır; bir agent ilgi bekliyorsa `Agents` açılır (2026-11-14) | Sahibi: "sekmeler halinde olsun... kullanıcı seçebilsin hangisini 1 hangisini 2" |
| AI agent oturumları | Yalnızca dosya ve süreç listesi okunur; hook yok, hiçbir aracın dizinine yazılmaz. Claude Code ve Codex tam durumla; Gemini CLI, Cursor Agent, OpenCode, Aider, Copilot CLI süreç düzeyinde (`Running`). Satıra tıklayınca oturumun uygulaması öne gelir; adadan cevap verilmez (2026-11-14) | Sahibi: "hook veya herhangi bir hata olmasın"; "hepsi olsun, geri dönüş yaparlar biz düzeltiriz" (spec: `2026-11-14-agents-tab-design.md`) |
| Agent ilgi belirteci | Soru ya da izin bekleyen oturum adayı kendiliğinden açmaz. Kapalı adada durum işareti (amber `#FFD60A` halka, "kapıyı çalan" nokta; 2026-11-15'e kadar kırmızı `#FF4D4F`) ve kenar ışığı; biten oturum için nane yeşili onay işareti, `Agents` sekmesi açılınca silinir (2026-11-14) | Sahibi: "direkt açılmasın, belirtici bir ibare olsun"; düz kırmızı/yeşil noktayı "çok basic" buldu; renk mercandan kırmızıya çekildi, çünkü pet'ler araç renginde ve Claude turuncusuyla karışmasın ("soru bekliyor kısmını başka bir renk yaparız"); 2026-11-15 ambere: "soru rengi kırmızı olmasın ya sanki fail olmuş gibi duruyor" |
| Agents listesi | Açık adada aynı anda en fazla 2 oturum alt alta görünür, fazlası aşağı kaydırılır (2026-11-14) | Sahibi: "alt alta gözüksün max 2 tane gözüksün aşağıya kaydırılabilsin" |
| Araç pet'leri | Her araç, tanındığı figürle ve kendi renginde gösterilir (Claude Code: yuvarlak yıldız biçimli tombul yaratık, iki küçük dik göz, iki küçük ayak; Codex: maviden mora geçen tombul bulut, üstünde beyaz parlayan `>_`, bacak yok; Gemini: yıldız, Cursor: küp, OpenCode: terminal penceresi, Aider: A, Copilot: gözlüklü kafa). Pet, 21 ince dikey çizgiden oluşan bir karedir; figür, çizgilerin renginin çizgi boyunca açılıp koyulaşmasıyla görünür. Tonlar bir resimden değil, sol üstten aydınlatılan küçük bir kabartma modelinden hesaplanır. Çalışırken çizgiler yalnızca çok az uzayıp kısalır. Logo dosyası paketlenmez (2026-11-14/15) | Sahibinin tarifi: ElevenLabs reklamı, "ekran tamamen çizgilerden oluşuyor... çubukların rengi değişerek yüz silüeti olduğu anlaşılıyordu ve burunları yanakları filan derinlik vardı". Önceki denemelere tepkileri: 7 kalın çubuk "çok basit", üç düz tonlu derinlik "iyi gibi", ilk kabartma "renkler çok soluk... o hissiyatı bi tık azalt ama çok azıcık". Hareket: "minik minik uzayıp küçülsün... gözü yormasın". Codex ve Claude figürü için sahibi bir Instagram videosunu (@canwebuildthis) fikir olarak gösterdi: "bacakları olmasın ama gövdesi bu şekilde olsun (tıpa tıp benzetme, sadece fikir olsun)"; Codex için "çok iyi oldu" dedi |
| Pet renkleri | Her pet tek renk değil; rengi sol üstten sağ alta geçişlidir (Claude: şeftali→turuncu→kiremit, Codex: mavi→mor, Gemini: mavi→mor→pembe...) (2026-11-15) | Sahibi: "her pet tek renk olmak zorunda değil, renk geçişleri olabilir, hem daha gerçekçi hem daha estetik durur" |
| Çentiği saran ışık | Kanatları görünen ada gerçek çentikten 2 pt uzundur (`IslandLayout.notchLip`), böylece kenar ışığı çentiğin altından kesintisiz geçer. Kaba durursa 0 yapılır ve ışık ortada kesilir (2026-11-15) | Sahibi: "gerçek çentiğin kalınlığı 10px ise 11px yapalım, o kırmızı ışık kesintisiz geçsin... kaba durursa eskisi gibi yaparız" |
| Animasyon maliyeti | Hiçbir görünüm istirahatte kare kare çizilmez: dönen yay, vuruşlar ve halkalar, ışığın nefesi ve geçen parlaklık, evcil hayvanın dalgası ve ses çubukları Core Animation'da çalışır; anahtar kareler çekirdekteki testli formüllerden örneklenir (2026-11-15) | Ölçüm: 0,35 sn'den sık yeniden çizim tam ekran panelin güncelleme döngüsünü açık tutuyor, ~%5 çekirdek. Ara sürümde elle yazılmış zamanlayıcı aynı anı tekrar verip ana iş parçacığını kilitledi; sahibi "üstüne gelince büyümüyor" diye bildirdi |
| Pet hareketi | Çalışan pet soldan sağa derinlikte bir Meksika dalgası yapar: tepe geçen çizgi %10 büyür ve tam renkte görünür, bekleyenler %82'de durur; beyaz eklenmez, hiçbir şey yukarı aşağı oynamaz. Soru bekleyen pet durur; zıplama yoktur. Dalga Core Animation'da çalışır (2026-11-15; önceki "minik kıpırtı" ve zıplama kaldırıldı) | Sahibi: "soldan sağa Meksika dalgası gibi dalgalansın, çalıştığı anlaşılır"; "yukarıya aşağıya değil de derinlik açısından yapsak"; zıplama için "kötü bir düşünce"; beyaz parlama için "beyaz bi şey geçiyor ya o olmasın" |
| Açık ada boyutu | 600 × 150 pt; yan kenarda 600 × 170, şeritten kısa olamaz (2026-11-15; önce 540 × 134, ondan önce 480 genişlik) | Sahibi: "biraz daha uzun gözüksün, 540 yap"; sonra "adanın boyunu da uzatalım biraz kısa geldi gözüme" deyip 600 × 150 seçti |
| Alt ajan dalları | Bir oturumun alt ajanları satırının altında çatal gibi dallanır: `├─`/`└─`, ad ve süre; en fazla 3 satır, fazlası `+N more`. Biten alt ajan, ebeveynin turu bitene kadar (ebeveyn boştayken bitip onu uyandıran arka plan alt ajanı da o turda görünür) soluk ve nane yeşili `Done ✓` ile kalır; çalışan önce gelir. Ada sabit boyda kalır, dallı oturum listeyi doldurursa kaydırılır. Claude Code: `subagents/agent-*.meta.json` (`finished`), durdurulan için ebeveyn transcript'indeki bildirim; Codex: `thread_spawn` rollout'ları. Kapalı adada gösterge yok (2026-11-15) | Sahibi: "subagent filan çalışıyorsa fork gibi gözüksün alt kısmında" (spec: `2026-11-15-subagent-branches-design.md`) |
| Anında temizleme | `~/.claude/sessions` FSEvents ile izlenir; dosya değişince tarama hemen başlar (iki tarama arası en az 0,25 sn). Ölçüm: dosya yazılınca 0,22 sn, silinince 0,015 sn (2026-11-15) | Sahibi: "soruya cevap verdikten 1 2 sn sonra soru efekti gidiyor"; Claude Code durumu 0,1 sn'de yazıyordu, ada 3 sn'de bir bakıyordu |
| Çentikteki ışık efektleri | Kenar ışığına, çentiğin altından geçen çizgiye ve sağdaki noktanın efektine dokunulmaz (2026-11-15) | Sahibi: "çentikteki ışık efektlerine karışma şimdilik"; ne istediğini sonra ayrıntılı anlatacak |
| Pet parlaklığı | Gölgelendirme tabanı yükseltildi (en soluk ton %36), renkler biraz daha parlak (2026-11-15) | Sahibi: "renkleri bi tık daha parlatalım ama çok abartmadan" |
| Bitiş efekti | Biten oturumun pet'i kapalı adada iPhone Face ID onayı gibi mühürlenir (köşe parantezleri kapanır, daireye döner, pet söner, nane yeşili ✓; 1,7 sn), sonra ada bırakır: kanatlar kapanır, kenar ışığı biter; listede `Done ✓` sekme açılana kadar kalır. Biten oturum, çalışan başka bir oturum olsa da efekt süresince yüzü alır. Müzik yüzünde sağdaki ✓ aynı süre görünür (2026-11-15) | Sahibi: "agentın işi bittiği zaman sol tarafta gözüken petin orada iphone face id onaylama efekti olsun ve öyle kapansın"; liste için B seçeneği ("öneriyi yap") (spec: `2026-11-15-finish-seal-and-compacting-design.md`) |
| Compact göstergesi | Claude Code `/compact` yaparken adanın kenarında mor (`#BF5AF2`) kesikli çizgi saat yönünde döner, sağdaki işaret mor kesikli halka olur ve döner, pet'in dalgası yukarıdan aşağı akar; compact bitince hepsi gider, bitiş sayılmaz. Hook yok: transcript'in sonundaki başlangıç izi (mesajı henüz yazılmamış `file-history-snapshot`; eski sürümlerde düz `/compact` kaydı) ve oturum dosyasındaki `busy` okunur. Otomatik compact ve Codex algılanmaz (2026-11-15) | Sahibi: "mor bir şekilde kesikli çizgilerle loop şeklinde compact bitene kadar dönsün", "hem adanın etrafında gezsin kesikli çizgi hem sağdaki halka yerine gelsin compact bitince de gitsin"; aynı Mac'teki Vibe Island bunu `PreCompact` hook'uyla yapıyor, bu proje hook kullanmıyor |
| İki kaynak aynı anda | Sistem kaynağının yanında Apple Music de çalıyorsa kapalı adada ikinci kapak ana kapağın arkasından sola taşar; açık adada `Media` sekmesinde iki kaynak alt alta, her biri kendi tuşlarıyla. Kapaklar yuvarlatılmış kare kalır (daire denendi, küçük durdu). Duraklatılan ikinci kaynak 10 sn sonra gizlenir. İkinci kaynak yalnızca Apple Music olabilir: sistem tek kaynak bildiriyor (2026-11-16) | Sahibi: "kickin arkasında apple music de gözüksün", "adanın üstüne gelince alt alta ikisi de gözüksün"; daire için: "önceki gibi gözüksün daha büyük duruyordu" (spec: `2026-11-16-two-sources-design.md`) |
| Yan baloncuk | Ada çentikte ve kapalıyken iki sekmenin de yüzü varsa (agent çalışıyor + müzik çalıyor) ilk sekme adada kalır, ikincisi adanın solunda 28 pt'lik siyah yuvarlak baloncuğa geçer (6 pt boşluk). Müzik baloncuğunda kapak dairedir; ikinci kaynak arkasında daha küçük bir daire olarak soldan taşar. Baloncuğun üstünde bekleyince ada o sekmeyle açılır. Kenara yanaşık adada baloncuk yok (2026-11-16) | Sahibi: "iphonelarda adada bir şey varsa 2. bir şey gelince yuvarlak olarak sağa veya sola geçiyor. Bizde de öyle olsun... arka arkaya efekti bozulmasın ama bu sefer yuvarlak olsun"; simetrik, kendi sekmesini açsın, şimdilik yalnızca çentikte, solda kalsın dedi (spec: `2026-11-16-side-bubble-design.md`) |
| Oynatıcı sesi | Açık adada `Media` sekmesinde yalnızca Apple Music ve Spotify satırının en sağında dikey ses çubuğu; oynatıcının kendi sesini AppleScript ile ayarlar. Tarayıcı ve diğer kaynaklarda çubuk yok (2026-11-16) | Sahibi: "en sağ tarafa dikey bir şekilde"; tarayıcı için yalnızca Mac'in genel sesi ayarlanabildiğinden ve o müziği de yükselteceğinden: "sadece apple music ve spotify için ses ayarlanabilsin diğeri için o ses barı olmasın" (spec: `2026-11-16-player-volume-design.md`) |
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
| Geri bildirim | Kopma, liflerin bir yüzeye tutunması ve bırakma (tutunmuş ya da değil) anında trackpad titreşimi, hepsi `.levelChange`; ses yok (2026-11-15: tutunma `.alignment`'tan güçlendirildi, tutunmuşken bırakmaya titreşim eklendi; AppKit'te şiddet ayarı yok) | Sahibinin tercihi; 2026-11-15: "yapışırkenki titreşim efekti de yok gibi... varsa hissiyatını arttır biraz" |
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
- **Faz 7 (sekmeler ve Agents sekmesi): kod tamam ve `main`'de (2026-11-15).** 310 çekirdek
  testi geçiyor. Sahibi çalışan uygulamada hover'ı ve çentiği saran 2 pt'lik taşmayı onayladı
  ("her şey düzgün çalışıyor şu an, kaba da gözükmedi"); pet'leri, renkleri ve dalgayı
  görüntüler üzerinden yönlendirdi. Tam elle kontrol listesi
  `docs/superpowers/plans/2026-11-14-agents-tab-app.md` sonunda (19 madde).
- Faz 7'de canlı doğrulananlar: bu Mac'teki Claude Code oturumu bulunuyor
  (`sessions: 1 [claudeCode]`), sahte bir `opencode` süreci süreç düzeyinde bulunuyor; dalga,
  halkanın vuruşları, ışığın üstünden geçen parlaklık ve seviye çubukları ardışık ekran
  görüntülerinde hareket ederken görüldü.
- Faz 7'de denenmeyenler: Codex yolu (denemeler sırasında Codex çalışmıyordu), satıra
  tıklayınca uygulamanın öne gelmesi, listenin kaydırılması, Reduce Motion, izin penceresinde
  `waiting` durumu, uyku sonrası davranış.
- CPU (2026-11-15, Debug derleme, `top` + `sample`): hareketsiz, bir agent çalışırken, soru
  beklerken ve müzik çalarken hepsinde %0; ana iş parçacığı örneklerin tamamında boşta. Önce:
  soru beklerken ~%8-9, müzik çalarken ~%7-8. Adadaki bütün hareketler (dönen yay, vuruşlar ve
  halkalar, ışığın nefesi ve geçen parlaklık, pet dalgası, seviye çubukları) Core Animation'da.
  Ölçmek için: `SYMBIODOCK_DEMO_AGENTS=finished|working|1|quiet` ve `SYMBIODOCK_DEMO_MEDIA=1`
  (yalnızca Debug).
- Bilinen, bırakılanlar: kanatlar belirirken imleç çentiğin hemen yanındaysa ada kendiliğinden
  açılabilir (medya yolunda da böyle); seviye çubukları Reduce Motion'ı dikkate almıyor
  (v1'den beri).
- **Faz 8 (alt ajan dalları, 600 × 150 ada, amber soru, anında temizleme, güçlü titreşim): kod
  tamam ve `main`'de (2026-11-15).** 342 çekirdek testi geçiyor. Canlı görülenler: oturum
  dosyası yazılınca ada 0,22 sn'de, silinince 0,015 sn'de fark ediyor; dallar ekran dışı
  görüntülerde doğru (`expanded-agents*.png`). Canlı denerken bulunan çökme düzeltildi
  (FSEvents geri çağrısı ana aktöre bağlı sayılıyordu). Sahibi 2026-11-15 akşamı canlı denedi:
  "böyle kalsın her şey düzgün çalışıyor"; iki gerçek arka plan alt ajanının dalları ve amber
  soru aynı anda adada göründü. Ana çizgi de dal tonlarında renkli (sahibinin isteği). Adadan
  soru cevaplama istenmedi ("şimdilik hayır"). Açıkça teyit edilmeyenler: titreşimin hissi,
  bitişte `Done ✓`, Codex alt ajanları. Elle kontrol listesi
  `docs/superpowers/plans/2026-11-15-subagent-branches.md` sonunda (18 madde).
- **Faz 9 (Face ID bitiş efekti, compact göstergesi): kod tamam ve `main`'de (2026-11-16).** 398
  çekirdek testi geçiyor. Son incelemeden sonra düzeltilenler: compact bitişi artık hiç "bitti"
  sayılmıyor (sınırdan sonraki 5 sn ve 1 MB'lık okuma; ölçüm: sınırdan sonra 312–441 KB kayıt),
  yanaşık adada yerleşmiş bitiş sakin görünüyor, sekmedeki nokta `Agents` açılana kadar kalıyor. Ekran dışı görüntülerde doğrulananlar: mor kesikli halka
  (`status-marks.png`), aşağı akan pet dalgası (`pets.png`), adanın etrafındaki kesikli çizgi
  ve üstte olmaması (`collapsed-faces.png`), bitiş efektinin aşamaları (`finish-seal.png`).
  CPU (Debug, `top`): compact demosunda %0; bitiş efekti oynarken ~%2, bittikten sonra %0.
  Canlı ekranda görülemedi: ekran görüntüleri tamamen siyah geldi (ekran kapalıydı ya da ekran
  kaydı izni yok); canlı görünüm sahibinin elle kontrolüne kaldı. Elle kontrol listesi
  `docs/superpowers/plans/2026-11-15-finish-seal-and-compacting.md` sonunda (12 madde).
- **İki kaynak aynı anda (2026-11-16): kod `main`'de, sahibi "bi yap bakalım ayarlarız" dedi.** 408
  çekirdek testi geçiyor. Ekran dışı görüntülerde doğrulandı (`expanded-media-two.png`,
  `collapsed-media-two.png`); canlıda gerçek Kick + Apple Music ile denenmedi, ölçüler sahibinin
  ayarına açık. Apple Music artık her açılışta ayrıca soruluyor: Automation izni ilk kez burada
  istenebilir. Deneme: `SYMBIODOCK_DEMO_MEDIA=2`.
- **Yan baloncuk (2026-11-16): kod `main`'de.** 415 çekirdek testi geçiyor. Ekran dışı görüntüde
  doğrulandı (`collapsed-bubble.png`: tek kaynak, iki kaynak, baloncukta pet). Demo ile canlıda
  CPU %0 (`SYMBIODOCK_DEMO_AGENTS=working` + `SYMBIODOCK_DEMO_MEDIA=2`). Canlı görünüm, geçiş
  animasyonu, baloncuk hover'ı ve menülerle çakışma görülemedi (ekran görüntüsü pencereleri
  göstermiyor); sahibinin elle kontrolüne kaldı. Liste:
  `docs/superpowers/plans/2026-11-16-side-bubble.md` sonunda (10 madde).
- **Oynatıcı sesi (2026-11-16): kod `main`'de.** 419 çekirdek testi geçiyor. Ekran dışı
  görüntülerde doğrulandı (`expanded-media-volume.png`, `expanded-media-two.png`). Canlıda
  denenmedi: gerçek Music/Spotify sesinin okunup ayarlanması, sürüklemenin hissi, çubuğa
  basınca adanın sürüklenmemesi, Spotify'ın Automation izni penceresi. Sahibi yan baloncuğu
  2026-11-16'da canlı denedi: "test ettim gayet güzel çalışıyor".
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

- [x] **Faz 7 — Sekmeler ve Agents sekmesi.** Kod tamam, elle kontrolün kalanı bekliyor. Spec:
      `docs/superpowers/specs/2026-11-14-agents-tab-design.md`. Planlar: önce
      `docs/superpowers/plans/2026-11-14-agents-tab-core.md` (çekirdek, 6 görev), sonra
      `docs/superpowers/plans/2026-11-14-agents-tab-app.md` (uygulama, 6 görev; elle kontrol
      listesi sonunda).
- [x] **Faz 8 — Alt ajan dalları, büyük ada, amber soru, anında temizleme.** Kod tamam, elle
      kontrol bekliyor. Spec: `docs/superpowers/specs/2026-11-15-subagent-branches-design.md`.
      Plan: `docs/superpowers/plans/2026-11-15-subagent-branches.md` (elle kontrol listesi sonunda).
- [x] **Faz 9 — Face ID bitiş efekti ve compact göstergesi.** Kod tamam, elle kontrol bekliyor.
      Spec: `docs/superpowers/specs/2026-11-15-finish-seal-and-compacting-design.md`.
      Plan: `docs/superpowers/plans/2026-11-15-finish-seal-and-compacting.md` (elle kontrol listesi sonunda).

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
- Beş araç için durum okuyucusu araştırıldı (2026-11-15, rapor `.superpowers/sdd/agents-tool-research.md`,
  git'e girmez): hiçbiri eklenmedi, hepsi süreç düzeyinde `Running` gösterir. OpenCode tur
  başlangıç ve bitişini açıkça yazıyor ama SQLite içinde (spec SQLite açmayı yasaklıyor);
  Copilot CLI `~/.copilot/session-state/<uuid>/events.jsonl` içinde tur ve izin olaylarını
  kısmen yazıyor; Gemini CLI ve Aider yalnızca mesajları yazıyor; Cursor Agent kapalı kaynak.
  Bu araçlardan biri kurulursa önce gerçek dosyalarına bakılır.
- Alt ajanlar (2026-11-15'te denendi, Claude Code 2.1.325): `subagents/agent-<id>.meta.json`
  çalışırken `finished` içermiyor, normal bitince `finished: true` ekleniyor; `TaskStop` ile
  durdurulana hiç yazılmıyor, ebeveyn transcript'ine `<task-id>…</task-id>` bildirimi düşüyor.
  İç içe alt ajanlar (spawn depth 2, `parentAgentId` ile) aynı `subagents/` klasörüne yazıyor ve
  bitiş bildirimleri oturumun ana transcript'inde (gerçek veride görüldü). Ön plan alt ajanının
  `tool_result` yolu gerçek veride hiç görülmedi (bu Mac'teki 147 alt ajanın hepsi arka planda);
  yedek: 10 dk sessizlik kuralı. Codex'te bir seviyeden derin alt ajanlar denenmedi.
- Claude Code oturum dosyasının canlılığı süreç listesinden karar verilir (süreç kullanıcının
  olmalı ve dosyanın son yazımından en geç 2 sn sonra başlamış olmalı). Çok uzun süre hiç
  durum değiştirmeyen canlı bir oturumun dosyası başka nedenle yeniden yazılmıyorsa bu kural
  onu düşürmez (dosya süreçten sonra yazılmıştır); tersi durum görülürse buraya yazılır.
- Compact algılama (2026-11-15'te denendi, Claude Code 2.1.325): elle `/compact` başında
  transcript'e mesajı henüz yazılmamış bir `file-history-snapshot` düşüyor, komut kaydı compact
  bitince yazılıyor; oturum dosyası compact boyunca `busy` (18 sn'lik canlı denemede). İki
  örnekte görüldü. 2.1.303–2.1.318'de başta düz `/compact` kaydı var (8 örnek). `/model`
  penceresi açıkken transcript'e bir şey yazılmıyor, durum `waiting`/`dialog open`. Claude Code
  güncellenip iz değişirse oturum compact sırasında "çalışıyor" görünür; okuyucu yeni ize
  göre güncellenir. Bitiş kuralı: elle `compact_boundary` + yanındaki kayıtlar (özet, caveat,
  komut, stdout, attachment) görülünce oturum `busy` kaldığı sürece en fazla 5 sn compact
  sayılır; böylece compact'ın bitişi hiçbir zaman bitiş (finish) sayılmaz.
- Claude Code `status: "shell"`: tur bitmiş, arka planda kabuk komutu sürüyor (bir oturumda iki
  kez görüldü). Boşta sayılıyor; başka anlamı çıkarsa buraya yazılır.

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
