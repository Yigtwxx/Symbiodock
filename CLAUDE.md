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
- Lisans: MIT

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
| Lisans | MIT | Public, kişisel araç |
| Depo | `Yigtwxx/Symbiodock`, public | Sahibinin isteği |

## Git

- Bu projede sahibi açıkça izin verdi: iş parça parça commit edilir ve push edilir.
  PR açma, merge ve force-push için yine sor.
- Conventional Commits; başlık en fazla 72 karakter, emir kipi, gövdede "neden".
- Secret, `.env`, anahtar dosyaları asla commit edilmez.

## Durum

- Depo açıldı; `main` üzerinde yalnızca README ve .gitignore var.
- `docs/v1-design` branch'inde: tasarım dokümanı, bu dosya, LICENSE, README güncellemesi.
- Uygulama kodu yok. Xcode projesi yok.

## Sıradaki adımlar

1. Sahibi tasarım dokümanını gözden geçirir.
2. Xcode kurulur (şu an yalnızca Command Line Tools var; `xcodebuild` çalışmıyor).
3. Milestone 0 ve 1 için uygulama planı yazılır (`superpowers:writing-plans`), sonra
   uygulanır. Planlar milestone başına yazılır, çünkü milestone 2 bir denemenin
   sonucuna bağlı.

Milestone'lar: 0 proje iskeleti → 1 çentik adası ve hover → 2 Now Playing →
3 sürükleme ve yapışma → 4 symbiote efekti.

## Doğrulanmamış varsayımlar

Bunlar denenmedi; ilgili milestone'da ilk iş olarak doğrulanacak. Her birinin yedeği
spec'te yazılı.

- `mediaremote-adapter` macOS 27'de çalışıyor mu (milestone 2 başında deneme). Lisansı da
  paketlemeden önce kontrol edilecek.
- `com.apple.Music.playerInfo` bildirimi macOS 27'de geliyor mu.
- Global fare izleme izin istiyor mu; istiyorsa `NSEvent.mouseLocation` yoklamasına geçilir.

## Doğrulama

Xcode projesi kurulunca build ve test komutları buraya eklenecek. O zamana kadar
çalıştırılabilir bir şey yok.
