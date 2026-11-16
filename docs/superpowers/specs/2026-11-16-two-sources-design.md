# İki kaynak aynı anda (2026-11-16)

## İstek

Sahibi: "birden fazla bir şey çalarken sol tarafta arka tarafında o da gözüksün, tam arkasında
olmasın ama sol tarafından gözüksün birazcık... şu an kick var ama apple music de çalıyor,
kickin arkasında apple music de gözüksün". Sonra: "kare değil de yuvarlak düşündüm ben. adanın
üstüne gelince alt alta ikisi de gözüksün".

## Sınır

Sistem (MediaRemote) tek kaynağı "now playing" olarak seçer (elected); adaptörün `get` ve
`stream` komutları yalnızca onu bildirir. Ama sistemden çalan her istemci de istenebilir
(`MRMediaRemoteGetNowPlayingClients`; adaptöre Symbiodock yamasıyla eklenen `get-clients`,
`stream-clients`, `send-to`). Bu yüzden ikinci kaynak yalnızca Apple Music değildir: sistemin
seçmediği, çalan herhangi bir uygulama olabilir (Spotify + tarayıcı, Safari + Chrome). Apple
Music ayrıca doğrudan sorulmaya devam eder (`AppleMusicProvider`, Automation izni ister).
Aynı tarayıcıda çalan iki sekme denenmedi; tek istemci görünmesi beklenir.

İlk sürümde bu bilinmiyordu ve şu hata çıktı (2026-11-16): Safari'de Kick, Apple Music de
çalarken sistem Music'i seçince sistem kaynağı ile Apple Music aynı uygulama oldu, tek kaynak
sayıldı ve Safari, sahibi sayfada sesi kapatıp açana (Safari yeniden seçilene) kadar kayboldu.

## Davranış

- Kapaklar eskisi gibi yuvarlatılmış kare. Daire denendi; sahibi küçük buldu: "yuvarlak gibi
  düşündüm derken... mantığı anla diye öyle dedim, önceki gibi gözüksün daha büyük duruyordu".
- Kapalı ada (çentik ve yüzen kapsül): ana kapağın arkasında ikinci kaynağın kapağı, %84
  boyda, %70 opaklıkta, solundan boyun %36'sı kadar taşar. Yan kenar şeridi değişmez.
- Açık ada, `Media` sekmesi: iki kaynak varken her biri kendi satırında (34 pt kapak, başlık,
  sanatçı, ince ilerleme çizgisi, kendi önceki/oynat/sonraki tuşları, seviye çubukları). Tek
  kaynakta eski düzen. Ada boyu değişmez.
- Sıra: sistemin bildirdiği kaynak önde. Öndeki duraklatılmış, diğeri çalıyorsa çalan öne geçer.
- Sistem kaynağı zaten Apple Music ise tek kaynak sayılır (bundle kimliği, yoksa ad eşleşmesi).
- Kalan yer (en fazla iki slot) önce Apple Music'indir (`.companion`): komutları AppleScript'le
  gider ve bunun çalıştığı biliniyor. Apple Music sistemin kaynağıyla aynıysa ya da bir şey
  bildirmiyorsa yeri sistemin listesindeki ilk uygun uygulama alır (`.client(pid)`): çalan,
  sistemin seçmediği ve henüz gösterilmeyen (aynı bundle kimliği) ilk uygulama, listedeki sırayla.
  Duraklatılmış ya da seçilmiş liste girdileri yok sayılır; üç uygulama çalsa da iki slot olur.
- Sistem kaynağı yokken de listedeki çalan bir uygulama slot alabilir.
- Duraklatılan ikinci kaynak `WingsTiming.pausedGrace` (10 sn) sonra gizlenir; yeniden çalınca
  ya da tek kaynak kalınca geri gelir. Listeden gelen bir uygulama yalnızca çalarken alındığı
  için duraklayınca hemen düşer.
- Tuşlar satırın kaynağına gider: `.system` → `NowPlayingService`, `.companion` → Apple Music,
  `.client(pid)` → adaptörün `send-to` komutu (o pid'deki istemciye `MRNowPlayingRequest` ile).
  Sistemin seçmediği bir istemciye komutun ulaştığı canlı denenmedi.
- Listedeki ilk uygun tarayıcıya da site çözülür (YouTube/Kick/Twitch, sistem kaynağıyla aynı
  yolla); ikinci bir tarayıcı kendi simgesiyle kalır. Ses çubuğu, simgeler ve görünümler
  `.client` slotunu `.system` gibi gösterir.
- Liste komutu çalışmazsa (yardımcı süreç vazgeçerse ya da sistem bu çağrıları vermezse) liste
  boş sayılır ve ada eskisi gibi davranır. `SYMBIODOCK_PROVIDER=applemusic` ile liste de açılmaz.

## Yapı

- Çekirdek: `NowPlayingLineup.slots(system:companion:others:)` (sıralama, saf), `NowPlayingSlot`,
  `NowPlayingOrigin` (`.client(pid:)` dahil), `NowPlayingClient`, `NowPlayingClientsParser`
  (`stream-clients` satırı; girdi alanlarını `MediaRemotePayloadParser` ile çözer);
  `IslandState.mediaSlots`, `setCompanionPlaying`, `setOtherPlaying`. `nowPlaying` ilk slotun
  bilgisidir.
- Uygulama: `NowPlayingCoordinator` Apple Music'i sistem kaynağının yanında ayrıca dinler ve
  `MediaRemoteProvider.clientUpdates` ile çalan uygulamaların listesini alır (ikinci yardımcı
  süreç, `stream` ile aynı yaşam döngüsü ve yeniden başlatma kuralı); `ClientSiteResolver`,
  `MediaRemoteProvider.send(_:toClient:)`; `ArtworkStack`, `ExpandedContent` satırları.
- Adaptör: `Vendor/mediaremote-adapter/VENDORED.md`, 2. yerel yama.
- Deneme: `SYMBIODOCK_DEMO_MEDIA=2`; ekran dışı görüntüler `expanded-media-two.png`,
  `collapsed-media-two.png`. Bildirilen hata için `SYMBIODOCK_DEMO_MEDIA=3` (sistem ve Apple
  Music aynı, Safari listeden ikinci); görüntüler `expanded-media-client.png`,
  `collapsed-media-client.png`.
