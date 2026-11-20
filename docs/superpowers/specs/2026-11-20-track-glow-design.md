# Parça ışığı (2026-11-20)

## İstek

Sahibi: "hani soru beklerken çentiğin etrafında bir çizgi dolanıyor ya. O tarz bir efekt
yapalım müzik ilk açıldığında değiştiğinde filan."

Seçtikleri: yalnızca parça değişince (ilk başlayış dahil); "ortadan sağa ve sola doğru olsun
bu sefer, ortadan başlasın"; çizgi ortadan çizilsin, bütün kenar kapağın renkleriyle bir an
yansın, sonra sönsün; "eğer sol tarafta yuvarlak formdaysa orada olsun, yuvarlak kısmın
üstünden olsun onda da". Baloncukta tepeden başlaması ve tablodaki öbür ayrıntılar benim
önerim; sahibi "önerileri yap, onaylıyorum" dedi.

## Davranış

- **Tetikleyici.** Gösterilen bir kaynağın (ada en fazla iki kaynak gösterir) çalan parçası
  değişince. Parçanın kimliği başlık + sanatçıdır. Kaynağın ilk kez çalarken görülmesi de
  değişimdir (uygulama açıldığında zaten çalan müzik dahil). Duraklatıp devam etmek, ileri
  sarmak, kaynakların yer değiştirmesi tetiklemez. Duraklatılmışken atlanan parça, çalmaya
  başlayınca tetikler.
- **Bekleme.** Değişimden sonra en az 0,4 sn beklenir (kanatlar yerleşsin, hızlı atlamalar
  birleşsin). Sonra yeni kapak geldiği anda (kapak var ve önceki parçanınkinden farklı) ışık
  yanar; gelmezse değişimden 1,0 sn sonra eldeki kapakla yanar. Bekleme sırasında parça yine
  değişirse bekleme baştan başlar: hızlı atlamada yalnızca son parça yanar.
- **Nerede.** Yandığı anda müziğin yüzü neredeyse orada:
  - baloncuk, müzik sol baloncuktaysa (`bubbleTab == .media`);
  - ada kenarı, kapalı adanın yüzü müzikse (`face == .media`) ve agent ışığı yoksa
    (`board.attention == .none`);
  - bunların dışında (ada açık, sürükleniyor, yüz agent'ta ve baloncuk yok) ışık yanmaz ve
    ertelenmez.
- **Kesilme.** Işık yanarken yüzeyi değişirse (ada açılır, agent soru sorar, müzik baloncuğa
  geçer) ışık kalkar; geri gelmez.
- **Hareket.** Çizgi kenarın ortasından iki uca doğru 0,6 sn'de çizilir (yavaşlayarak), 0,3 sn
  tam yanar, 0,6 sn'de söner. Toplam 1,5 sn.
- **Başlangıç noktası.** Çizgi, adanın ekrana değmeyen kenarlarından oluşan açık hattır ve
  hattın tam ortasından başlar: çentikte alt kenarın ortası, yan kenardaki dikey şeritte serbest
  uzun kenarın ortası, alt/üst kenardaki kapsülde serbest uzun kenarın ortası. Köşeye yanaşık
  adada hattın uzunlukça ortası. Baloncukta dairenin tepesi; iki kol altta birleşir.
- **Görünüm.** 1,5 pt çizgi, altında 3,5 pt (%30) ve 6 pt (%12) iki yumuşak hale; hepsi adanın
  ya da baloncuğun içinde kalır (dışına taşan kısım kırpılır).
- **Renk.** O parçanın kapağının `ArtworkTint`'i: yatayda soldan sağa, dikey şeritte aşağıdan
  yukarı (çubuklarla aynı yön). Tek renkse düz. Kapak yoksa ya da renksizse beyaz, %85. Işık
  yanarken kapak gelirse renk o an güncellenir.
- **İki kaynak.** Hangi kaynağın parçası değiştiyse onun kapağı. İkisi aynı anda değişirse öndeki.
- **Reduce Motion.** Yayılma yok: bütün hat 0,3 sn'de belirir, 0,6 sn durur, 0,6 sn'de söner.
- **Mevcut ışıklar.** `RimLight`, `CompactingRim` ve sağdaki işaret değişmez.
- **Maliyet.** Tek seferlik Core Animation; ışık bitince görünümü kaldırılır. İstirahatte hiçbir
  şey kare kare çizilmez.

## Yapı

- Çekirdek (`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/`):
  - `TrackChangeWatch`: kaynak başına son çalan parçayı tutar; `update(_ slots:)` parçası
    değişen kaynakları (ve önceki kapaklarını) döndürür.
  - `TrackGlowMotion`: süreler; `reach(at:)`, `opacity(at:)`, `stillOpacity(at:)`.
  - `TrackGlowOutline`: `island(in:radii:dockedEdges:)` ve `bubble(in:)`; ortası başlangıç
    noktası olan açık `CGPath`, sol üst köşe orijinli.
  - `IslandState`: `awaitedTrackGlow`, `trackGlow`; `trackGlowSettled(_:)`,
    `trackGlowWaitElapsed(_:)`, `trackGlowEnded(_:)`. Zamanı çekirdek tutmaz; bitiş mührü gibi
    görünüm bekler ve haber verir.
- Uygulama (`Symbiodock/Island/`):
  - `TrackGlowLine`: canlıda Core Animation (`strokeStart`/`strokeEnd` + opaklık, anahtar
    kareler `TrackGlowMotion`'dan örneklenir), `frozenAt` ile SwiftUI'de durağan çizim.
  - `IslandView`: adanın ve baloncuğun üstüne bindirme; iki `.task(id:)` (bekleme, bitiş).
- Deneme: `SYMBIODOCK_DEMO_MEDIA=1|2` ile açılışta bir kez yanar;
  `SYMBIODOCK_DEMO_AGENTS=working` eklenince baloncukta. Ekran dışı görüntü: `track-glow.png`.

## Kapsam dışı

Duraklat/devam ve kaynak değişimi için ışık; açık adada ışık; sağdaki dosya baloncuğunda ışık;
ışığın ses seviyesine ya da ritme tepki vermesi; ayar menüsünden kapatma.
