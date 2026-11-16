# İki kaynak aynı anda (2026-11-16)

## İstek

Sahibi: "birden fazla bir şey çalarken sol tarafta arka tarafında o da gözüksün, tam arkasında
olmasın ama sol tarafından gözüksün birazcık... şu an kick var ama apple music de çalıyor,
kickin arkasında apple music de gözüksün". Sonra: "kare değil de yuvarlak düşündüm ben. adanın
üstüne gelince alt alta ikisi de gözüksün".

## Sınır

Sistem (MediaRemote) yalnızca tek kaynağı "now playing" olarak bildirir. İkinci kaynak ancak
doğrudan sorulabilen bir oynatıcı olabilir; şimdilik bu yalnızca Apple Music'tir
(`AppleMusicProvider`, Automation izni ister). İki tarayıcı sekmesi ya da Spotify + tarayıcı
ayırt edilemez.

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
- Duraklatılan ikinci kaynak `WingsTiming.pausedGrace` (10 sn) sonra gizlenir; yeniden çalınca
  ya da tek kaynak kalınca geri gelir.
- Tuşlar satırın kaynağına gider: `.system` → `NowPlayingService`, `.companion` → Apple Music.

## Yapı

- Çekirdek: `NowPlayingLineup` (sıralama, saf), `NowPlayingSlot`, `NowPlayingOrigin`;
  `IslandState.mediaSlots`, `setCompanionPlaying`. `nowPlaying` ilk slotun bilgisidir.
- Uygulama: `NowPlayingCoordinator` Apple Music'i sistem kaynağının yanında ayrıca dinler;
  `ArtworkStack`, `ExpandedContent` satırları.
- Deneme: `SYMBIODOCK_DEMO_MEDIA=2`; ekran dışı görüntüler `expanded-media-two.png`,
  `collapsed-media-two.png`.
