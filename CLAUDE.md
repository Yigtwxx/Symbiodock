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
| Efekt tekniği | SwiftUI `Canvas` metaball (blur + alpha threshold); yetmezse Metal shader | Efekt yalnızca sürüklerken çalışır |
| Çentik dışı konum | `visibleFrame` içinde 8 pt içeride yüzen siyah kapsül | Menü çubuğunu ve sistem Dock'unu kapatmamalı |
| Mimari | Spec bölüm 4-5 | Sahibi onayladı |
| Proje üretimi | XcodeGen (`project.yml`), `.xcodeproj` commit edilmez | Komut satırından üretilebilir ve diff'i okunur |
| Kod yerleşimi | Saf mantık `Packages/SymbiodockCore` paketinde, AppKit/SwiftUI app hedefinde | Mantık uygulama açılmadan `swift test` ile test edilir |
| Telif satırı | `Yigtwxx` | Sahibinin tercihi |
| Lisans | GPL-3.0 (MIT'ten değiştirildi) | Kaynak açık + ücretli hazır sürüm modeli; kapalı kaynak kopyaları engeller |
| Dağıtım | Ücretsiz: GitHub'dan clone edip derleme. Ücretli: web sitesinden hazır sürüm indirme, lisans anahtarı yok | Sahibinin iş modeli; kaynak açıkken anahtar kontrolü anlamsız |
| İmzalama, site, ödeme | Uygulama bitince ele alınacak; o zamana kadar ad-hoc imza | Sahibi: "site kısmı en son" |
| Görünüm | v1'de düz siyah; kişiselleştirme sonra | Sahibinin tercihi |
| Tam ekran | Ada tam ekran uygulamaların üstünde de görünür kalır | Sahibinin tercihi |
| Girişte başlatma | v1'de var, menüde aç/kapa (milestone 5) | Sahibinin tercihi |
| Geri bildirim | Kopma ve yapışma anında trackpad titreşimi, ses yok | Sahibinin tercihi |
| Arayüz dili | Tamamen İngilizce; çeviri altyapısı kurulmaz | Dil desteği çok sonra gelecek |
| v1 sonrası widget'lar | Henüz kararlaştırılmadı | Sahibi sonra söyleyecek; sorma, o açana kadar bekle |
| Depo | `Yigtwxx/Symbiodock`, public | Sahibinin isteği |

## Git

- Bu projede sahibi açıkça izin verdi: iş parça parça commit edilir ve PR açmadan
  doğrudan `main`'e push edilir (2026-11-14). Force-push için yine sor.
- Conventional Commits; başlık en fazla 72 karakter, emir kipi, gövdede "neden".
- Secret, `.env`, anahtar dosyaları asla commit edilmez.

## Durum

- Depo açıldı; tasarım dokümanı, bu dosya, LICENSE ve README `main` üzerinde.
- Tasarım dokümanı sahibi tarafından onaylandı (2026-11-14).
- Milestone 0-1 uygulama planı yazıldı; henüz uygulanmadı.
- Uygulama kodu yok. Xcode projesi yok.
- Sahibi Xcode'u indiriyor (2026-11-14); kurulduğu `xcodebuild -version` ile doğrulanmalı.

## Sıradaki adımlar

1. Xcode kurulumu biter. Kontrol: `xcodebuild -version`. Kurulu ama seçili değilse sahibi
   `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` çalıştırır.
2. `docs/superpowers/plans/2026-11-14-m0-m1-notch-island.md` planı uygulanır
   (`superpowers:subagent-driven-development` ya da `superpowers:executing-plans`).
3. Milestone 2 için ayrı plan yazılır; planlar milestone başına yazılır, çünkü milestone 2
   bir denemenin sonucuna bağlı.

Milestone'lar: 0 proje iskeleti → 1 çentik adası ve hover → 2 Now Playing →
3 sürükleme ve yapışma → 4 symbiote efekti → 5 girişte başlatma.

## Doğrulanmamış varsayımlar

Bunlar denenmedi; ilgili milestone'da ilk iş olarak doğrulanacak. Her birinin yedeği
spec'te yazılı.

- `mediaremote-adapter` macOS 27'de çalışıyor mu (milestone 2 başında deneme). Lisansı
  paketlemeden önce kontrol edilecek; GPL-3.0 ile uyumlu olmak zorunda.
- `com.apple.Music.playerInfo` bildirimi macOS 27'de geliyor mu.
- Global fare izleme izin istiyor mu; istiyorsa `NSEvent.mouseLocation` yoklamasına geçilir.

## Doğrulama

Plan uygulanınca build ve test komutları buraya eklenecek. Yalnızca Command Line Tools
ile `swift test` de çalışmıyor (2026-11-14'te denendi); Xcode şart.
