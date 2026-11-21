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
| Çentik dışı konum | Ekranın çerçevesine sıfır mesafe, çentik gibi: kenara değen köşeler köşeli, serbest köşeler yuvarlak. Üstte menü çubuğunun içinden çerçeveye yapışır (menü çubuğunu kapatır). Dock'un olduğu kenarda yalnızca Dock'un kapladığı yerde Dock'un üstüne yapışır; Dock'un sağında ve solunda çerçeveye iner. Dock'un ucuna denk gelen ada 8 pt açıkta durur, yanında yer yoksa Dock'a çıkar; Dock'un üstündeki ada Dock'un ucundan taşmaz. Çerçevedeki ada açılınca Dock'un ucunu örtebilir. Dock'un yeri izin gerektirmeyen özel `CoreDockGetRect` çağrısından okunur; çağrı yoksa Dock bütün kenarı kaplıyor sayılır. Üst kenarda çentiğe denk gelen ada çentiğin yanına kayar (8 pt boşluk), açık ada yanına sığmıyorsa çentiğin altına iner (2026-11-21; önce `visibleFrame` kenarı, menü çubuğunun altı; ondan önce 8 pt içeride yüzen kapsül) | Sahibi: "tamamen 0 olsun, kenara direkt çentik gibi dursun"; 2026-11-21: "sekmelere filan yapışıyo ya ondansa bütün çerçeveye yapışsın daha mantıklı. Dock kısmında da dockun üstüne yapışsın"; ekran görüntüsüyle: "docka yapışıyor onda sıkıntı yok ama sağ ve sol kısımlarında pencerelere yapışıyor", "o kısımda da çerçeveye yapışsın"; çentiğin ve Dock'un yanına kayma kuralları öneriydi |
| Yan kenarda dikey ada | Sağ/sol kenarda kapalı ada 36 × 170 pt dikey şerit: üstte platform simgesi, ortada 90° döndürülmüş parça adı, altta seviye çubukları; hover'da kenardan içeri 600 × 170 açılır. Köşeler ve üst/alt kenar yatay kalır (2026-11-14) | Sahibi: "sağa veya sola yapışırsa dikey yapışsın"; açık ada şeritten kısa olursa hover titrer (spec: `2026-11-14-side-docking-design.md`) |
| Platform simgesi | Yalnızca dikey şeritte. Music/Spotify: uygulama simgesi. Tarayıcı: Safari ve Chrome'a AppleScript ile sekmeler sorulur, YouTube/Kick/Twitch logosu gösterilir (Simple Icons, CC0); izin yoksa tarayıcı simgesi (2026-11-14) | Sahibi: "yt ise yt"; sistem yalnızca tarayıcıyı söylüyor, site için Automation izni şart ve sahibi onayladı |
| Sekmeler | Açık adada sekme şeridi: `Agents` ve `Media`. Sıra sağ tık menüsünde `First tab` ile seçilir ve saklanır; varsayılan `Agents` birinci. Hover'da birinci sekme açılır; bir agent ilgi bekliyorsa `Agents` açılır (2026-11-14) | Sahibi: "sekmeler halinde olsun... kullanıcı seçebilsin hangisini 1 hangisini 2" |
| Açılan sekme | Hover'da önce ilgi bekleyen agent (`Agents`), sonra sırada ilk **aktif** sekme (kapalı adanın yüzüyle aynı ölçü: agent çalışıyor / müzik çalıyor ya da duraklatılalı 10 sn olmamış), sonra içeriği olan ilk sekme açılır. Boştaki agent listede dursa da müzik çalıyorsa `Media` açılır; agent yeniden çalışınca `Agents`'a döner. Bitiş efekti oynarken `Agents`, efekt bitince `Media`. Ada kendiliğinden açılmaz (2026-11-20) | Sahibi: "agent çalışmasını bitirdi ve boşta, o sırada müzik çalıyorsa otomatik olarak orayı açsın ama tekrar agent çalıştırırsan default olan agent kısmına geri dönsün"; üç öneriyi de onayladı |
| AI agent oturumları | Yalnızca dosya ve süreç listesi okunur; hook yok, hiçbir aracın dizinine yazılmaz. Claude Code ve Codex tam durumla; Gemini CLI, Cursor Agent, OpenCode, Aider, Copilot CLI süreç düzeyinde (`Running`). Satıra tıklayınca oturumun uygulaması öne gelir; adadan cevap verilmez (2026-11-14) | Sahibi: "hook veya herhangi bir hata olmasın"; "hepsi olsun, geri dönüş yaparlar biz düzeltiriz" (spec: `2026-11-14-agents-tab-design.md`) |
| Agent ilgi belirteci | Soru ya da izin bekleyen oturum adayı kendiliğinden açmaz. Kapalı adada durum işareti (amber `#FFD60A` halka, "kapıyı çalan" nokta; 2026-11-15'e kadar kırmızı `#FF4D4F`) ve kenar ışığı; biten oturum için nane yeşili onay işareti, `Agents` sekmesi açılınca silinir (2026-11-14) | Sahibi: "direkt açılmasın, belirtici bir ibare olsun"; düz kırmızı/yeşil noktayı "çok basic" buldu; renk mercandan kırmızıya çekildi, çünkü pet'ler araç renginde ve Claude turuncusuyla karışmasın ("soru bekliyor kısmını başka bir renk yaparız"); 2026-11-15 ambere: "soru rengi kırmızı olmasın ya sanki fail olmuş gibi duruyor" |
| Agents listesi | Açık adada aynı anda en fazla 2 oturum alt alta görünür, fazlası aşağı kaydırılır (2026-11-14) | Sahibi: "alt alta gözüksün max 2 tane gözüksün aşağıya kaydırılabilsin" |
| Araç pet'leri | Her araç, tanındığı figürle ve kendi renginde gösterilir (Claude Code: yuvarlak yıldız biçimli tombul yaratık, iki küçük dik göz, iki küçük ayak; Codex: maviden mora geçen tombul bulut, üstünde beyaz parlayan `>_`, bacak yok; Gemini: yıldız, Cursor: küp, OpenCode: terminal penceresi, Aider: A, Copilot: gözlüklü kafa). Pet, 21 ince dikey çizgiden oluşan bir karedir; figür, çizgilerin renginin çizgi boyunca açılıp koyulaşmasıyla görünür. Tonlar bir resimden değil, sol üstten aydınlatılan küçük bir kabartma modelinden hesaplanır. Çalışırken çizgiler yalnızca çok az uzayıp kısalır. Logo dosyası paketlenmez (2026-11-14/15) | Sahibinin tarifi: ElevenLabs reklamı, "ekran tamamen çizgilerden oluşuyor... çubukların rengi değişerek yüz silüeti olduğu anlaşılıyordu ve burunları yanakları filan derinlik vardı". Önceki denemelere tepkileri: 7 kalın çubuk "çok basit", üç düz tonlu derinlik "iyi gibi", ilk kabartma "renkler çok soluk... o hissiyatı bi tık azalt ama çok azıcık". Hareket: "minik minik uzayıp küçülsün... gözü yormasın". Codex ve Claude figürü için sahibi bir Instagram videosunu (@canwebuildthis) fikir olarak gösterdi: "bacakları olmasın ama gövdesi bu şekilde olsun (tıpa tıp benzetme, sadece fikir olsun)"; Codex için "çok iyi oldu" dedi |
| Pet renkleri | Her pet tek renk değil; rengi sol üstten sağ alta geçişlidir (Claude: şeftali→turuncu→kiremit, Codex: mavi→mor, Gemini: mavi→mor→pembe...) (2026-11-15) | Sahibi: "her pet tek renk olmak zorunda değil, renk geçişleri olabilir, hem daha gerçekçi hem daha estetik durur" |
| Çentiği saran ışık | Kanatları görünen ada gerçek çentikten 2 pt uzundur (`IslandLayout.notchLip`), böylece kenar ışığı çentiğin altından kesintisiz geçer. Kaba durursa 0 yapılır ve ışık ortada kesilir (2026-11-15) | Sahibi: "gerçek çentiğin kalınlığı 10px ise 11px yapalım, o kırmızı ışık kesintisiz geçsin... kaba durursa eskisi gibi yaparız" |
| Animasyon maliyeti | Hiçbir görünüm istirahatte kare kare çizilmez: dönen yay, vuruşlar ve halkalar, ışığın nefesi ve geçen parlaklık, evcil hayvanın dalgası ve ses çubukları Core Animation'da çalışır; anahtar kareler çekirdekteki testli formüllerden örneklenir (2026-11-15) | Ölçüm: 0,35 sn'den sık yeniden çizim tam ekran panelin güncelleme döngüsünü açık tutuyor, ~%5 çekirdek. Ara sürümde elle yazılmış zamanlayıcı aynı anı tekrar verip ana iş parçacığını kilitledi; sahibi "üstüne gelince büyümüyor" diye bildirdi |
| Pet hareketi | Çalışan pet soldan sağa derinlikte bir Meksika dalgası yapar: tepe geçen çizgi %10 büyür ve tam renkte görünür, bekleyenler %92'de durur (2026-11-20'ye kadar %82); beyaz eklenmez, hiçbir şey yukarı aşağı oynamaz. Soru bekleyen pet durur; zıplama yoktur. Dalga Core Animation'da çalışır (2026-11-15; önceki "minik kıpırtı" ve zıplama kaldırıldı) | Sahibi: "soldan sağa Meksika dalgası gibi dalgalansın, çalıştığı anlaşılır"; "yukarıya aşağıya değil de derinlik açısından yapsak"; zıplama için "kötü bir düşünce"; beyaz parlama için "beyaz bi şey geçiyor ya o olmasın" |
| Açık ada boyutu | 600 × 170 pt, yan kenarda da (2026-11-16; önce 600 × 150, 540 × 134, 480 genişlik) | Sahibi: "biraz daha uzun gözüksün, 540 yap"; sonra "adanın boyunu da uzatalım biraz kısa geldi gözüme" deyip 600 × 150 seçti; 2026-11-16: "kalınlığını da biraz arttır" |
| Alt ajan dalları | Bir oturumun alt ajanları satırının altında çatal gibi dallanır: `├─`/`└─`, ad ve süre; en fazla 3 satır, fazlası `+N more`. Biten alt ajan, ebeveynin turu bitene kadar (ebeveyn boştayken bitip onu uyandıran arka plan alt ajanı da o turda görünür) soluk ve nane yeşili `Done ✓` ile kalır; çalışan önce gelir. Ada sabit boyda kalır, dallı oturum listeyi doldurursa kaydırılır. Claude Code: `subagents/agent-*.meta.json` (`finished`), durdurulan için ebeveyn transcript'indeki bildirim; Codex: `thread_spawn` rollout'ları. Kapalı adada 2026-11-20'den beri uydular var (bkz. "Renkli yay ve uydular") (2026-11-15) | Sahibi: "subagent filan çalışıyorsa fork gibi gözüksün alt kısmında" (spec: `2026-11-15-subagent-branches-design.md`) |
| Anında temizleme | `~/.claude/sessions` FSEvents ile izlenir; dosya değişince tarama hemen başlar (iki tarama arası en az 0,25 sn). Ölçüm: dosya yazılınca 0,22 sn, silinince 0,015 sn (2026-11-15) | Sahibi: "soruya cevap verdikten 1 2 sn sonra soru efekti gidiyor"; Claude Code durumu 0,1 sn'de yazıyordu, ada 3 sn'de bir bakıyordu |
| Çentikteki ışık efektleri | Kenar ışığına, çentiğin altından geçen çizgiye ve sağdaki noktanın efektine dokunulmaz (2026-11-15) | Sahibi: "çentikteki ışık efektlerine karışma şimdilik"; ne istediğini sonra ayrıntılı anlatacak |
| Pet parlaklığı | Gölgelendirme tabanı yükseltildi (en soluk ton %36), renkler biraz daha parlak (2026-11-15) | Sahibi: "renkleri bi tık daha parlatalım ama çok abartmadan" |
| Bitiş efekti | Biten oturumun pet'i kapalı adada iPhone Face ID onayı gibi mühürlenir (köşe parantezleri kapanır, daireye döner, pet söner, nane yeşili ✓; 1,7 sn), sonra ada bırakır: kanatlar kapanır, kenar ışığı biter; listede `Done ✓` sekme açılana kadar kalır. Biten oturum, çalışan başka bir oturum olsa da efekt süresince yüzü alır. Müzik yüzünde sağdaki ✓ aynı süre görünür (2026-11-15) | Sahibi: "agentın işi bittiği zaman sol tarafta gözüken petin orada iphone face id onaylama efekti olsun ve öyle kapansın"; liste için B seçeneği ("öneriyi yap") (spec: `2026-11-15-finish-seal-and-compacting-design.md`) |
| Compact göstergesi | Claude Code `/compact` yaparken adanın kenarında mor (`#BF5AF2`) kesikli çizgi saat yönünde döner, sağdaki işaret mor kesikli halka olur ve döner, pet'in dalgası yukarıdan aşağı akar; compact bitince hepsi gider, bitiş sayılmaz. Hook yok: transcript'in sonundaki başlangıç izi (mesajı henüz yazılmamış `file-history-snapshot`; eski sürümlerde düz `/compact` kaydı) ve oturum dosyasındaki `busy` okunur. Otomatik compact ve Codex algılanmaz (2026-11-15) | Sahibi: "mor bir şekilde kesikli çizgilerle loop şeklinde compact bitene kadar dönsün", "hem adanın etrafında gezsin kesikli çizgi hem sağdaki halka yerine gelsin compact bitince de gitsin"; aynı Mac'teki Vibe Island bunu `PreCompact` hook'uyla yapıyor, bu proje hook kullanmıyor |
| İki kaynak aynı anda | Sistem kaynağının yanında Apple Music de çalıyorsa kapalı adada ikinci kapak ana kapağın arkasından sola taşar; açık adada `Media` sekmesinde iki kaynak alt alta, her biri kendi tuşlarıyla. Kapaklar yuvarlatılmış kare kalır (daire denendi, küçük durdu). Duraklatılan ikinci kaynak 10 sn sonra gizlenir. İkinci kaynak yalnızca Apple Music olabilir: sistem tek kaynak bildiriyor (2026-11-16) | Sahibi: "kickin arkasında apple music de gözüksün", "adanın üstüne gelince alt alta ikisi de gözüksün"; daire için: "önceki gibi gözüksün daha büyük duruyordu" (spec: `2026-11-16-two-sources-design.md`) |
| Yan baloncuk | Ada çentikte ve kapalıyken iki sekmenin de yüzü varsa (agent çalışıyor + müzik çalıyor) ilk sekme adada kalır, ikincisi adanın solunda 28 pt'lik siyah yuvarlak baloncuğa geçer (6 pt boşluk). Müzik baloncuğunda kapak dairedir; ikinci kaynak arkasında daha küçük bir daire olarak soldan taşar. Baloncuğun üstünde bekleyince ada o sekmeyle açılır. Kenara yanaşık adada baloncuk yok (2026-11-16) | Sahibi: "iphonelarda adada bir şey varsa 2. bir şey gelince yuvarlak olarak sağa veya sola geçiyor. Bizde de öyle olsun... arka arkaya efekti bozulmasın ama bu sefer yuvarlak olsun"; simetrik, kendi sekmesini açsın, şimdilik yalnızca çentikte, solda kalsın dedi (spec: `2026-11-16-side-bubble-design.md`) |
| Oynatıcı sesi | Açık adada `Media` sekmesinde yalnızca Apple Music ve Spotify satırının en sağında dikey ses çubuğu; oynatıcının kendi sesini AppleScript ile ayarlar. Tarayıcı ve diğer kaynaklarda çubuk yok (2026-11-16). Çubuk simgesiyle birlikte en fazla 72 pt, satırların ortasında; `Media` sekmesinin alt boşluğu 16 pt (2026-11-20; önce çubuk tam boy, boşluk 8 pt) | Sahibi: "en sağ tarafa dikey bir şekilde"; tarayıcı için yalnızca Mac'in genel sesi ayarlanabildiğinden ve o müziği de yükselteceğinden: "sadece apple music ve spotify için ses ayarlanabilsin diğeri için o ses barı olmasın"; 2026-11-20: "alt kenara çok yakın duruyorlar... ses çubuğu da bu kadar uzun olmak zorunda değil birazcık orantıla" (spec: `2026-11-16-player-volume-design.md`) |
| Kapak renkli çubuklar | İlerleme çubuğu, ses çubuğu ve seviye çubukları (kapalı adada da) çalan şeyin kapağının rengini alır. Kapak geçişliyse (kırmızı→pembe→mor) çubuk da en fazla üç renkli aynı geçişi taşır; geçiş dolu kısmın başından sonuna yayılır. Renkler 32 × 32'lik kopyadan, kapak çözülürken bir kez hesaplanır (`ArtworkPalette`, çekirdek); koyu renk siyahta okunacak kadar aydınlatılır. Kapak yoksa ya da renksizse çubuklar beyaz kalır. Platform rengi kullanılmaz (2026-11-20) | Sahibi: "bir şey çalarken o şeyin renginde olsa bar güzel olur"; "bir kapak kırmızı pembe mor geçişliyse o şekilde yap barı da"; kapaktan, üç çubuk birden ve kapalı adada da önerilerini onayladı |
| Parça ışığı | Gösterilen bir kaynağın çalan parçası değişince (ilk başlayış dahil; duraklat/devam ve ileri sarma değil) kapalı adanın kenarında kapağın renklerinde bir çizgi ortadan iki uca çizilir (0,6 sn), bütün kenar bir an yanar (0,3 sn) ve söner (0,6 sn). Çentikte alt kenarın ortasından, yanaşık adada serbest uzun kenarın ortasından başlar. Müzik sol baloncuktaysa ışık baloncuğun tepesinden başlar, iki yandan iner ve altta birleşir. Değişimden en az 0,4 sn sonra, yeni kapak gelince, en geç 1,0 sn'de yanar; hızlı atlamada yalnızca son parça. Ada açıkken ya da aynı yüzeyde agent ışığı (amber, nane) varken yanmaz ve ertelenmez. Reduce Motion'da yayılma yok, bütün hat belirip söner. `RimLight` ve `CompactingRim` değişmedi (2026-11-20) | Sahibi: "soru beklerken çentiğin etrafında bir çizgi dolanıyor ya, o tarz bir efekt yapalım müzik ilk açıldığında değiştiğinde"; "ortadan sağa ve sola doğru olsun bu sefer"; "sol tarafta yuvarlak formdaysa orada olsun, yuvarlak kısmın üstünden olsun onda da"; bekleme süreleri ve baloncukta tepeden başlaması öneriydi, "önerileri yap, onaylıyorum" dedi ; aynı albümde kapak değişmediği için ışığın ~1 sn gecikmesi ve uygulama açıldığında zaten çalan müzik için de bir kez yanması soruldu, ikisini de onayladı ("son 2 öneriyi yap") (spec: `2026-11-20-track-glow-design.md`) |
| Çalışma ışığı | Agent çalışırken (kapalı ada, yüz agent, öndeki oturum `working`, dikkat yok) adanın serbest uzun kenarının hemen dışında aracın dört renginde akan bir ışık: 1 pt net çizgi ve kenardan 9 pt dışarı sönen, nefes alan hale. Renkler 3,2 sn'de bir tur akar (yatayda sağa, dikey şeritte aşağı), hale 2,4 sn'de nefes alır. Adanın arkasında ayrı katman, hep kapalı adanın kenarında: yerinde belirip söner (0,35 sn), ada açılırken onunla yürümez. Soru ve compact ışığı varken, agent baloncuktayken yanmaz. Oturum bitince hemen sönmez: Face ID bitiş efekti boyunca kalır, efektin çerçevesi yeşile döndüğü anda (0,75. sn) 0,2 sn'de nane tonlarına döner, efekt bitince söner; başka oturum çalışıyorsa onun renklerine döner. Reduce Motion'da sabit (2026-11-20) | Sahibi: "agent çalışırkenki animasyon çok sönük kaldı, basit yani"; dört tur canlı taslaktan "kuzey ışıkları güzel", sonra "Yedek 2 canlı. Bu olsun" dedi; kenar ve baloncuk kuralları öneriydi, "önerileri yap"; bitişte yeşil için: "sönerken de yeşil olsun face id ile senkron bir şekilde. Güzel durur sanki" (spec: `2026-11-20-working-aurora-design.md`) |
| Renkli yay ve uydular | Çalışan oturumun dönen yayı aracın ışık renklerinde (ilk renkten ikinciye; renk durur, yay döner), kapalı yüzlerde ve listede. Kapalı adanın yüzlerinde çalışan her alt ajan yayın etrafında dönen 3 pt'lik nokta: en fazla 5, her biri kendi hızında (2,3-4,3 sn) ve kimliğinden gelen açıda, biten nane yeşili parlayıp gider. Listede uydu yok. "Kapalı adada alt ajan göstergesi yok" kararı (2026-11-15) bununla değişti (2026-11-20) | Sahibi ilk turda "Fikir 3"ü (uydular) işaretledi; seçtiği kartta ikisi de vardı; sonra ayrıca hatırlattı: "dönme kısmı da renkliydi ve subagentları gösterenler de vardı onu unutma" |
| Canlı pet | Pet tonları parladı: gölgeler tam renge %38 yaklaştırıldı (`shadeLift` 0,62; en soluk ton %60), zemin çizgileri 0,12, dalgada bekleyen çizgi %92, çizgi payı 0,68; Claude Code, Codex, OpenCode ve Aider renkleri en parlak değerine çekildi (2026-11-20; önce en soluk ton %36, dalga %82). Sahibi canlıda görünce karar verecek; kabartma düzleşmişse `shadeLift` 1'e doğru geri çekilir | Sahibi: "biraz daha canlı yapsana rengi çok soluk bu haliyle"; taslaktaki üç seviyeden `Canlı`yı seçti; önce/sonra görüntüleri için: "açık değil şu an görünce söylerim" |
| Files sekmesi | Üçüncü sekme, hep sonda: dosya rafı. Bırakılan dosya/klasör/fotoğraf kart olur, başka Space'e ya da tam ekran uygulamaya sürüklenip alınır; birlikte bırakılanlar çekmece (yığın) olur, öndeki tam, arkadakilerin üstü görünür, imleçle kalkar; ⌘-tıklamayla çoklu seçim. Kartlar tür renginde cam; sekme simgeleri kodla çizilir (`>_`, seviye çubukları, iki kâğıt) (2026-11-16) | Sahibi: "pencereli ekrandan bir dosyayı oraya sürükleyip bırakayım sonra ... tam ekran bir pencereye oradan sürükleyip alabileyim"; "arka arkaya dosya çekmeceleri gibi gözüksün"; ilk görünüm ve SF simgeleri için "çok ai gibi duruyor" (spec: `2026-11-16-files-tab-design.md`) |
| Dosya çevirme | Yalnızca yerleşik macOS araçları (sips, textutil, afconvert, ditto, PDFKit, AVFoundation, Markdown ayrıştırıcısı); çıktı orijinalin yanına, orijinal kalır. Toplu çevirmede desteklenmeyen (PPTX/XLSX) atlanır ve söylenir; toplu ZIP tek `Archive.zip` (2026-11-16) | Sahibi: "ekstra bir şey kurmak zorunda kalmayalım"; "2 docx 1 pptx pdfe çevirilecek hepsini çevirsin" |
| Venom sarma | Çevrilen kart (ya da çekmece) çentikteki goo diliyle sarılır, siyah koza olur, yeni formatla açılır; istirahatte kare kare çizim yok (2026-11-16) | Sahibi: "venom gibi o dosyayı çevresinden sarmalasın tamamen kapatsın siyah olsun ve açılsın" |
| Dosya baloncuğu | Raf doluyken kapalı adanın sağında yuvarlak baloncuk: türün simgesi kendi renginde, adet köşede rozet; diğer türler arkadan taşar (2026-11-16) | Sahibi: "fotoğrafsa fotoğraf iconu olsun ve onun kendi rengi olsun" |
| System sekmesi | Dördüncü sekme, sıra `Agents, Media, System, Files`: CPU / GPU / RAM kullanımı, CPU ve GPU sıcaklığı, ağ hızı, ağdaki cihazların sayısı ve adları. Yerleşim A (satırlar): solda üç ölçü çubuklarıyla, ortada `Network`, sağda `Devices` listesi. Her ölçü kendi renginde (CPU mavi, GPU mor-pembe, RAM yeşil); simge çip. RAM'de sıcaklık yok, yalnızca kullanım. Yalnızca açık adada: yüzü ve baloncuğu yok, hover'da kendiliğinden açılmaz, `First tab` menüsüne girmez. Yalnızca sekme görünürken, 2 sn'de bir ölçülür (sıcaklık 6 sn'de bir; ortalama değil ortanca, çünkü çoğu SMC anahtarı 40 °C'nin altını göstermiyor). Kendiliğinden ağa hiçbir paket gönderilmez: sekme açılınca yalnızca Mac'in zaten bildiği komşular sayılır; tarama ve ad çözme yalnızca `Devices` panelindeki `Scan` düğmesiyle yapılır ve macOS "Local Network" iznini ilk basışta bir kez ister; adı çözülemeyen cihaz IP ile görünür. `Scan` düğmesi yalnızca alt ağ en çok /22 ise ve modem komşu tablosunda donanım adresiyle duruyorsa çıkar (VPN tüneline tarama gitmesin); adlar yalnızca cihazın kendi verdiğinden (mDNS) gelir ve IP + donanım adresiyle, bellekte saklanır; başka cihazdan gelen ad güvenilmez sayılıp temizlenir. Hook, `sudo` ve yeni bağımlılık yok (2026-11-21) | Sahibi: "bir sekme daha ekleyelim. CPU GPU RAM kullanımı, bunların sıcaklıkları ağ kullanımı ağa bağlı kaç kişi olduğu ve onların adını filan göstersin"; izin için "izinleri tara seçeneği seçmek istiyorum"; RAM sensörü bulunamayınca "Yalnızca kullanım"; canlı taslaktan "A, çip ve her ölçü kendi renginde". Otomatik taramanın ofis ya da kafe ağında şüpheli görüneceği söylenince: "tarama düğmeyle olsun o zaman. Kaç kişi bağlı olduğunu paket göndermeden görebiliyorsak o kalsın". Adların da yalnızca `Scan`'le çözülmesi öneriydi (ad sormak da ağa sorgu gönderir): "öneriyi yap". Ad, sıra, kendiliğinden açılmama, ortalama sıcaklık ve sayıma bu Mac ile modemin girmesi öneriydi, planla birlikte onayladı (spec: `2026-11-21-system-tab-design.md`) |
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
- **Faz 10 (Files sekmesi) ve yan düzeltmeler (2026-11-16): kod `main`'de (666 çekirdek testi), incelemelerin bir kısmı ve son bütün-dal incelemesi sahibinin isteğiyle ertelendi.** Ekran dışı görüntülerde doğrulananlar: raf, çekmeceler, çoklu seçim, venom sarma aşamaları, dosya baloncuğu, sekme simgeleri. Çeviriciler gerçek dosyalarla denendi. Canlı denenmeyenler: gerçek sürükle-bırak, efektin hareketi, baloncuk hover'ı. Aynı günün yan işleri: ikinci çalan uygulama artık sistemin bütün istemci listesinden (Kick + Apple Music), compact çizgisi aralığı 10 pt, Codex'in açılışta geri yüklediği oturumlar listelenmiyor. Elle kontrol listesi plan dosyasının sonunda.
- **Takılı kalan Now Playing düzeltildi (2026-11-20, 672 çekirdek testi).** Sahibi: "bir şey çalmamasına rağmen çalıyormuş gibi gözüküyor... dakika ve saniyeyi tutturamıyor, durdurma da işe yaramıyor". Neden: iki yardımcı sürecin çıktısı `FileHandle.bytes` ile okunuyordu; o, süreçteki bütün okumaları tek sıralı kuyrukta bloklayan `read` ile yapıyor, sessiz kalan `stream-clients` diğerinin satırlarını tutuyordu (canlı `sample`: yardımcı `fprintf`'te, uygulama `AsyncBytesIOActorQueue`'da bekliyordu; sistem `null` derken ada eski "çalıyor" satırında kalmıştı). Artık `PipeLines` (çekirdek, `readabilityHandler`); yardımcı çıktısı için `FileHandle.bytes` kullanılmaz. Gerçek çalma ile canlı denenmedi.
- **Açılan sekme etkinliğe göre (2026-11-20, 676 çekirdek testi).** `TabSelection.tabToOpen` artık kapalı adanın yüzünü seçen ölçüyü kullanıyor. Yalnızca süreç düzeyinde görülen araçlar (`Running`) aktif sayılmıyor. Canlı denenmedi.
- **`Media` sekmesi boşlukları (2026-11-20).** Alt boşluk 16 pt, ses çubuğu en fazla 72 pt ve ortalı. Ekran dışı görüntülerde doğrulandı (`expanded-media-volume.png`, `expanded-media-two.png`); önizleme artık gerçek ada boyunu (600 × 170) ve konumu olan bir parçayı kullanıyor. Canlı denenmedi.
- **Kapak renkli çubuklar (2026-11-20, 686 çekirdek testi).** Ekran dışı görüntülerde doğrulandı (`expanded-media-volume.png`, `expanded-media-two.png`, `collapsed-media-two.png`; demo kapakları kodla üretilen geçişler). Gerçek kapaklarla ve canlıda denenmedi: çamurlu ya da cırtlak çıkan kapak olursa `ArtworkPalette` eşikleri ayarlanır.
- **Parça ışığı (2026-11-20, 718 çekirdek testi): kod `main`'de.** Ekran dışı görüntüde doğrulandı (`track-glow.png`: çentikte alt ortadan, baloncukta tepeden, alt kapsülde üst kenarın ortasından, sağ şeritte iç kenarın ortasından; kapak renkleri soldan sağa). Demo ile canlıda çökmeden çalıştı (adada ve baloncukta, art arda parça değişimleri); ışık bittikten sonra CPU %0 (`SYMBIODOCK_DEMO_AGENTS=quiet` ile; gerçek agent taraması açıkken ortalama ~%0,8, o tarama bu işten önce de vardı). Canlı görünüm görülemedi (ekran görüntüsü pencereleri göstermiyor): çizginin hareketi, gerçek kapaklar ve gerçek parça değişimleri sahibinin elle kontrolüne kaldı. Deneme: `SYMBIODOCK_DEMO_MEDIA=1|2` ile birlikte `SYMBIODOCK_DEMO_TRACKS=1` her 4 sn'de parça değiştirir. Liste: `docs/superpowers/plans/2026-11-20-track-glow.md` sonunda (14 madde). Sahibi aynı gün çalışan uygulamada baktı: "bu haliyle güzel bence"; hız, kalınlık ve parlaklık böyle kalır. Listenin maddeleri tek tek teyit edilmedi.
- **Çalışma ışığı, renkli yay, uydular, canlı pet (2026-11-20, 748 çekirdek testi): kod `main`'de.** Ekran dışı görüntülerde doğrulandı (`working-aurora.png`: çentikte iki araç, nefesin iki ucu, alt kenarda kapsül, iki yan kenarda şerit, her birinde sabit çizimle canlı katmanların duruşu yan yana; `status-marks.png`: renkli yay ve uydular, "claude at 0" ile "claude live" aynı yerde; `pets.png`). Demo ile canlıda çökmeden çalıştı. CPU (Debug, `top` + `sample`, işaretçi dururken): ışık, yay ve uydular oynarken %0,0. İşaretçi hareket ederken %2-30 sıçramalar görüldü; `sample` bunların pencere sunucusundan gelen işaretçi olayları olduğunu gösterdi (ana iş parçacığında uygulamanın kendi kodu ~20/33.000 örnek, hepsi `MouseTracker`; çizim yok), yani ışıktan değil. Son inceleme bulup düzeltilenler: ışık hover çıkışında adanın altından kayarak geliyordu (artık kapalı adanın kenarında yerinde beliriyor), uydular için verilen kimlik bitiş halkasını bozuyordu. Canlı görünüm görülemedi (ekran görüntüsü pencereleri göstermiyor): akışın hızı, halenin gücü, yayın dönerken renk değiştirmesi, uyduların dönüşü ve bitişi, hover geçişi ve pet'in yeni parlaklığı sahibinin elle kontrolüne kaldı. Gözlemler: dalga artık daha zayıf okunabilir (%92), Codex ışığındaki mor compact moruna yakın. Bitişte yeşile dönme sonradan eklendi; ekran dışı görüntüde yeşil ışık doğru, zamanlaması canlıda görülmedi. Ekran sunucusu (WindowServer, `top`, fare dururken ortanca, 3 × 25 sn dönüşümlü): agent yokken %39,1, çalışırken %46,1; bu işten önceki sürümde çalışırken %46,6, yeni sürümde %48,0. Yani çalışma hâli ekran sunucusuna ~7 puan yük bindiriyor ve bu Faz 7'den beri var; ışık, yay ve uydular buna ~1 puan ekliyor (gürültü sınırında). Pilden çekilen güç de ölçüldü (batarya akımı × gerilim): bloklar arası 9-19 W oynadı, fark seçilemedi. Bu yükün nedeni araştırılacak (sahibi istedi). Deneme: `SYMBIODOCK_DEMO_AGENTS=working` (Codex, iki çalışan alt ajan), `finished` (bitiş ve yeşil ışık). Liste: `docs/superpowers/plans/2026-11-20-working-aurora.md` sonunda (19 madde).
- **Çerçeveye yapışma (2026-11-21, 766 çekirdek testi): kod `main`'de.** Ada bütün ekrana yanaşıyor (`ScreenMetrics.localDockFrame`); Dock ayrı bir engel (`DockGeometry`, `DockObstacle`): kalınlığı `visibleFrame`'den, kenar boyunca kapladığı yer `CoreDockGetRect`'ten (`DockProbe`; bu Mac'te x 311-1417, izin sormadı). Dock'un yeri ekran değişince, uygulama açılıp kapanınca (0,5 / 1,5 / 3,5 sn sonra) ve sürükleme başlarken yeniden okunur. Sahibi ilk sürümü canlı denedi: Dock'un üstünde duruş iyi, Dock'un sağında ve solunda ada Dock hizasında havada kalıyordu; bu düzeltildi. Canlı denenmedi: düzeltilmiş hâl, menü çubuğunun içindeki görünüm, çentiğin ve Dock'un ucunun yanına kayma, liflerin Dock'a ve çerçeveye tutunması, Dock büyüyünce adanın izlemesi, yanda duran Dock. Bilinen: küçültülen pencere Dock'u büyütürse ada bunu bir sonraki sürüklemede ya da uygulama açılıp kapanınca fark eder.
- **Faz 12, Bölüm A (System sekmesi: CPU / GPU / RAM, sıcaklık, ağ hızı; 2026-11-21, 800 çekirdek testi): kod `main`'de, sahibinin elle kontrolünü bekliyor.** Ekran dışı görüntülerde doğrulandı (`tab-glyphs.png`: dört simge, çip sekiz bacaklı; `expanded-system.png`, `expanded-system-hot.png`, `expanded-system-empty.png`: A yerleşimi, her ölçü kendi renginde, 96° kırmızı ve 83° sarı, ölçüm yokken çizgiler). Gerçek değerler pencere açmadan okundu (`SYMBIODOCK_PRINT_SYSTEM=1`) ve karşılaştırıldı: 8 `yes` süreciyle CPU %66 (`top` %66,8), RAM 21,05 GB (`vm_stat` 20,9-21,1), GPU `ioreg` ile aynı, CPU sıcaklığı boşta 40-44°, yükte 54-55°; bir okuma 6-11 ms (bir kez 15,3 ms, o sırada başka araçlar da çalışıyordu). Döngü pencere açmadan denendi (`SYMBIODOCK_PRINT_SYSTEM=loop`): ada kapalıyken ve başka sekmede 0 ölçüm, `System` görünürken 7 sn'de 4, kapanınca yine 0. Ada kapalıyken CPU %0,0 ve logda ölçüm satırı yok; izin penceresi çıkmadı. Canlı denenmedi: gerçek pencerede sekme (hover, tıklama, çubukların kayması, VoiceOver), sekme açıkken uygulamanın CPU maliyeti, uyku sonrası, Wi-Fi kapalıyken `Offline`, Release ve Intel derlemesi, M4 Pro dışında çip. `Devices` paneli Bölüm B'ye kadar boş (`—`). Bütün değişikliğin son incelemesinde kritik ya da önemli bulgu çıkmadı. Dağıtımdan önce: çipe göre SMC anahtar tablosu (M3'te `Tf**` olabilir; denenmedi), yedek sıcaklık istemcisini saklamak ve anahtar seçimini yeniden denemek, yalnızca IPv6'lı ağda `Offline` görünmesi (denenmedi), ekran uyurken açık kalan adada ölçümün sürmesi (denenmedi; `Agents` taramasında da aynı köşe var). Deneme: `SYMBIODOCK_DEMO_SYSTEM=1|hot` (sekme kendiliğinden açılmaz, çip simgesine tıklanır). Liste: `docs/superpowers/plans/2026-11-21-system-tab-a.md` sonunda (18 madde).
- **Faz 12, Bölüm B (ağdaki cihazlar; 2026-11-21, 836 çekirdek testi): kod `main`'de, sahibinin elle kontrolünü bekliyor.** Sahibi Bölüm A'yı canlı gördü (ekran görüntüsü yolladı, "değerler doğru mu" diye sordu, sonra "Bölüm B'ye geç" dedi; A'nın listesindeki maddeler tek tek teyit edilmedi). O soru üzerine CPU sıcaklığı düzeltildi: çip serinken ortanca 40'ta takılıyordu, artık tabansız anahtarların ortalaması gösteriliyor. `System` sekmesi görünürken Mac'in zaten bildiği cihazlar okunur (paket yok, izin yok); `Scan` basışıyla alt ağ taranır ve cihazlara adları sorulur. Doğrulananlar: ekran dışı görüntüler (`expanded-system.png`: liste, sayı rozeti, `Scan`, başlıkta `7 devices`; `-scanning`, `-denied`, `-empty`); `open --stdout` ile başlatılan başsız denemede ada kapalıyken ve başka sekmede 0 liste, `System` görünürken 6 cihaz ve `can scan true`, her satırda `scan idle`. Tarama, tablo okuma ve ad sorgusu yalnızca bir kerelik denemede (sahibi `Allow`'a bastı) çalışırken görüldü; o deneme dosyası silindi. **Bugünkü kodun taramasını henüz kimse çalıştırmadı**: `Scan`'e yalnızca sahibi basar; arayüze bağlama (`IP_BOUND_IF`) ve arayüzlü ad sorgusu yalnızca derlenerek doğrulandı. Son inceleme (bütün değişiklik): kritik yok; "basış olmadan paket çıkmaz, bir basış tek tarama, log ve diskte ad ya da adres yok" koddan izlenerek doğrulandı; üç önemli bulgu düzeltildi (adlar IP + donanım adresiyle saklanıyor; "izin yok" kararı adresi bilinen bir cihazın reddine dayanıyor, çünkü çekirdek cevapsız adresleri art arda taramalarda kendisi de reddediyor; modem tabloda donanım adresiyle durmuyorsa `Scan` düğmesi yok ve paketler birincil arayüze bağlı, yani VPN tüneline tarama gitmez). Denenmeyenler: gerçek pencerede `Scan`, açıkça `Don't Allow` denen durum, liste kaydırma ve düğmeye basmanın adayı sürüklememesi, art arda 6 tarama, VPN, /22 ağ, başka bir ağ, Release derlemesi. Dağıtımdan önce: /22'de 1021 paketi 1-2 sn'ye yaymak (ofis anahtarlarında ARP hız sınırı), `ENOBUFS`/`EAGAIN` sayımı, bozuk tablo için regresyon testleri, adlarda birleşen işaret sınırı, ekran uyurken açık kalan ada. Deneme: `SYMBIODOCK_DEMO_SYSTEM=1|hot|scanning|denied`; `SYMBIODOCK_PRINT_SYSTEM=loop` (`open --stdout` ile). Liste: `docs/superpowers/plans/2026-11-21-system-tab-b.md` sonunda (15 madde).
- **Faz 12 onaylandı (2026-11-21).** Sahibi Bölüm B'nin 15 maddelik listesi verildikten sonra: "okey bunlar bir sıkıntı yok". Hangi maddeleri denediğini söylemedi; art arda 6 tarama, VPN, `Don't Allow` ve `tcpdump` maddelerinin denendiği bilinmiyor. Sonraki widget ya da iş için sahibi yön verecek.
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
- [x] **Faz 10 — Files sekmesi: dosya rafı, format çevirme, venom sarma, dosya baloncuğu.**
      Spec: `docs/superpowers/specs/2026-11-16-files-tab-design.md`.
      Plan: `docs/superpowers/plans/2026-11-16-files-tab.md` (8 görev; elle kontrol listesi sonunda).
- [x] **Faz 11 — Çalışma ışığı, renkli yay, uydular, canlı pet.** Kod tamam, elle kontrol bekliyor.
      Spec: `docs/superpowers/specs/2026-11-20-working-aurora-design.md`.
      Plan: `docs/superpowers/plans/2026-11-20-working-aurora.md` (8 görev; elle kontrol listesi sonunda).
- [x] **Faz 12 — System sekmesi: CPU / GPU / RAM, sıcaklıklar, ağ hızı, ağdaki cihazlar.**
      Spec: `docs/superpowers/specs/2026-11-21-system-tab-design.md`. İki bölüm, iki plan.
      Bölüm A (izin gerektirmez; sonunda sahibi dener):
      `docs/superpowers/plans/2026-11-21-system-tab-a.md` (6 görev; elle kontrol listesi sonunda).
      **Bölüm A'nın kodu tamam, elle kontrol bekliyor.**
      Bölüm B (ağdaki cihazlar, `Scan` düğmesi, Local Network izni):
      `docs/superpowers/plans/2026-11-21-system-tab-b.md` (5 görev; elle kontrol listesi sonunda).
      Sahibi 2026-11-21'de iki bölümün elle kontrol listesinden sonra onayladı: "okey bunlar bir
      sıkıntı yok". Maddeleri tek tek teyit etmedi.

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
- System sekmesi (2026-11-21, M4 Pro, `sudo` olmadan denenenler): GPU kullanımı `IOAccelerator`
  istatistiklerinden okunuyor (%29); `AppleSMC` kullanıcı istemcisi açılıyor ve sıcaklık
  anahtarlarını veriyor (CPU `Tp**`/`Te**` 40-72 °C, GPU `Tg**` 36-45 °C; çoğu `Tp0*` boşta tam
  40,0 okuyor, bu 40 taban değeri: yükte 50-58'e çıkıyorlar); özel `IOHIDEventSystemClient` `PMU tdie*` sensörlerini veriyor
  (35-39 °C); RAM sensörü bulunamadı; `arp -an` Terminal'den modem + 3 cihaz gösterdi. Yük altında
  (14 `yes`, 14 sn) `Tp**` anahtarlarının 90'ı yükseldi; `Tp0*` 40 °C'nin altını göstermiyor,
  bazı anahtarlar tepe değeri tutuyor: bu yüzden ortanca alınır (boşta CPU 44,0, GPU 36,6 °C).
  Bir SMC anahtarını okumak ~170 µs. **Komşu tablosu sıradan bir süreçten okunamıyor**: aynı
  `sysctl` çağrısı 0 bayt döndürüyor, `arp`'ın özel yetkisi yok; yani Bölüm A'da cihaz listesi
  yok (bu, Terminal'den çalışan süreç içindi). **Bölüm B denemesi (2026-11-21, uygulamanın içinden, sahibi `Allow`'a bastı):** `open` ile başlatılan uygulama komşu tablosunu izinsiz ve paket göndermeden okuyor (5 cihaz); 254 adrese boş UDP paketi izin verilmeden önce 65 (`EHOSTUNREACH`) hatası verip izin penceresini açıyor, izinden sonra hepsi gidiyor ve 6. cihaz bulunuyor; modemin ters DNS'i ad vermiyor, mDNS ters sorgusu 6 cihazın 2'sinin adını veriyor (iPhone ve bu Mac); `/usr/sbin/arp` uygulamanın içinden 0 satır veriyor. CPU sıcaklığı: serinken ortanca 40'ta takıldığı için tabansız anahtarların ortalaması gösteriliyor (boşta `tdie` 35,5, tabansız 36,2, ortanca 40,0; yükte 42,1 / 50,6 / 56,6); elde referans araç yok. Denenmeyenler ve yedekleri spec'in sonunda: başka çipler ve GPU yükü, izin verilince
  komşu tablosunun okunması, UDP taramasının izin penceresini açması, ters DNS / mDNS ile ad
  çözme, izin reddinin `sendto` hatasından anlaşılması, ad-hoc imzada iznin yeniden sorulması.
- Dosya sürükleme (2026-11-16, Faz 10 Görev 5): gerçek sürükleme elle yapılması gerektiği için
  üç varsayımın hiçbiri denenmedi. (1) Başka uygulamanın sürüklemesi sırasında global
  `.leftMouseDragged` geliyor; yedek kodda: global `leftMouseDown` ile başlayıp tuş bırakılınca
  duran 30 Hz yoklama (`MouseTracker`, istirahatte çalışmaz). (2) Sürükleme ortasında
  `ignoresMouseEvents = false` yapılan panel bırakma hedefi oluyor; yedek yazılmadı: yalnızca
  dosya sürüklemesi boyunca gösterilen, ada boyunda ayrı küçük bırakma paneli. (3)
  `beginDraggingSession` sırasında 30 Hz yoklama sürüyor; yedek kodda:
  `draggingSession(_:movedTo:)` içinden `refreshPointer()`. Başarısız olursa Console'da `drop` ve
  `file-drag` kategorilerine bakılır.

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
