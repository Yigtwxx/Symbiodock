# Oynatıcı sesi (2026-11-16)

## İstek

Sahibi: "Müziklerin veya izlediğim videonun da sesi ayarlanabiliyorsa onu da ekle en sağ tarafa
dikey bir şekilde". Tarayıcı videosu için yalnızca Mac'in genel sesi ayarlanabildiğini ve bunun
müziği de etkileyeceğini öğrenince: "sadece apple music ve spotify için ses ayarlanabilsin
diğeri için o ses barı olmasın".

## Sınır

macOS uygulama başına ses için hazır bir API vermez. Apple Music ve Spotify kendi seslerini
Apple Events ile okutur ve ayarlatır (`sound volume`, 0–100). Tarayıcı sekmesinin kendi sesi
ancak sayfaya JavaScript göndererek (tarayıcıda elle ayar ister) ya da ses yakalayarak
(izin ister, ağır) ayarlanır; ikisi de yapılmadı.

## Davranış

- Açık adada `Media` sekmesinde, kaynağı Apple Music ya da Spotify olan satırın en sağında ince
  dikey bir çubuk ve altında hoparlör simgesi: üst tam ses, alt sessiz. Sütunun herhangi bir
  yerine basıp sürükleyince seviye değişir.
- Başka kaynakta (tarayıcı, diğer uygulamalar) çubuk yoktur. İki kaynak alt alta iken çubuğu
  olmayan satır aynı genişlikte boşluk bırakır; tuşlar hizalı kalır.
- Ses, sekme her göründüğünde ve gösterilen oynatıcılar değiştiğinde oynatıcıya sorulur.
  Oynatıcı çalışmıyorsa ya da cevap vermiyorsa (Automation izni yok) çubuk çıkmaz.
- Sürüklerken oynatıcıya en çok 60 ms'de bir, bırakınca bir kez daha yazılır.
- Çubuğa basmak adayı sürüklemez; sürüklerken imleç adanın dışına taşarsa ada açık kalır.
- Oynatıcı hiçbir zaman bizim tarafımızdan başlatılmaz.
- Spotify'a ilk soruda macOS Automation izni ister.

## Yapı

- Çekirdek (`NowPlaying/PlayerVolume.swift`): `VolumeTarget` (bundle kimliğinden),
  `VolumeRequest`, `VolumeLevel` (yüzde, kesir, imleçten seviye); `IslandState.volumes`,
  `setVolume(_:for:)`.
- Uygulama: `PlayerVolumeScript` (AppleScript), `VolumeSlider`, `ExpandedContent`;
  `IslandGeometry.noDragRects` ve `OverlayController`'da `pressAllowsDrag`.
- Deneme: `SYMBIODOCK_DEMO_MEDIA=1|2` (Music sesi %60); ekran dışı görüntüler
  `expanded-media-volume.png`, `expanded-media-two.png`.
