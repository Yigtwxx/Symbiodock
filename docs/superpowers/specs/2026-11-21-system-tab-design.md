# System sekmesi (2026-11-21)

## İstek

Sahibi: "bir sekme daha ekleyelim. CPU GPU RAM kullanımı, bunların sıcaklıkları ağ kullanımı ağa
bağlı kaç kişi olduğu ve onların adını filan göstersin".

Sorulara cevapları:

- Ağ taraması için macOS izni: "izinleri tara seçeneği seçmek istiyorum" (pencere bir kez çıkar).
- RAM sıcaklığı okunamadığı için RAM satırında: "Yalnızca kullanım".
- Kapalı adada gösterge: yok, "Yalnızca açık ada".
- Canlı taslaktan (`.superpowers/brainstorm/7804-1795251702/content/system-tab-layouts.html`):
  "A, çip ve her ölçü kendi renginde".

Önerip sahibinin planla birlikte onayladıkları: sekmenin adı ve sırası, hover'da kendiliğinden
açılmaması, ortalama sıcaklık, sayıma bu Mac'in ve modemin girmesi, Intel'de sıcaklığın `—` olması.

## Sınırlar

Bu Mac'te (M4 Pro, macOS 27.0.1) `sudo` olmadan 2026-11-21'de denendi:

| Veri | Sonuç | Kaynak |
|---|---|---|
| GPU kullanımı | %29 okundu | `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %` |
| CPU / GPU sıcaklığı | CPU 40-72 °C, GPU 36-45 °C | `AppleSMC` (`Tp**`, `Te**`, `Tg**`) |
| Çip sıcaklığı | 35-39 °C | özel `IOHIDEventSystemClient`, `PMU tdie*` |
| RAM sıcaklığı | sensör bulunamadı | — |
| Ağdaki cihazlar | modem + 3 cihaz | ARP tablosu (`arp -an`) |

- ARP tablosu yalnızca Mac'in konuştuğu cihazları tutar. Hepsini bulmak için alt ağdaki her
  adrese bir paket yollanır; macOS 15'ten beri bu "Local Network" iznini ister.
- Ad yalnızca adını ağa duyuran ya da modemin DNS'ine kayıtlı cihazlarda bulunur. Telefonlar
  rastgele MAC kullandığı için üretici adı da çıkarılamaz (buradaki 3 cihazın 2'si öyle).
- Sayı kişi değil cihaz sayısıdır.

## Davranış

### Sekme

- Dördüncü sekme, adı `System`. Sıra: `Agents`, `Media`, `System`, `Files`; `Files` yine sonda.
- `First tab` menüsüne girmez, yüzü ve baloncuğu yoktur, hover'da kendiliğinden açılmaz. Ada
  açıkken sekme şeridinden tıklanır. `TabSelection.tabToOpen` değişmez.
- Simge kodla çizilir (14 pt ızgara, 1,5 pt çizgi): köşesi 1,25 yuvarlak 5,5 pt'lik kare
  (4,25-9,75) ve her kenarda 2 pt uzunluğunda iki bacak (5,75 ve 8,25 hizasında).
- Başlığın sağındaki özet: `7 devices`. Liste boşsa özet yok.

### Yerleşim (A: satırlar)

Başlığın altındaki alan: üstten 2, yanlardan 16, alttan 14 pt boşluk. Üç sütun, aralarında 10 pt:
ölçü satırları (kalan genişlik), `Network` paneli (128 pt), `Devices` paneli (164 pt). Paneller
beyaz 0,05 dolgu, köşe 14.

**Ölçü satırları** (CPU, GPU, RAM alt alta, eşit aralıklı):

- Üstte ad (11 semibold, beyaz 0,62), sağda sıcaklık (10 medium, beyaz 0,55) ve yüzde
  (13 semibold). Altında 6 pt çubuk: zemin beyaz 0,14, dolgu ölçünün renk geçişi, en az 6 pt.
- RAM satırında sıcaklık ve yüzde yerine `18.5 / 48 GB`; çubuk kullanılan / toplam.
- Sıcaklık yazısı 80 °C'de `#FFD60A`, 95 °C'de `#FF6B5E` olur. Okunamayan değer `—`.
- Rakamlar eş genişlikte (`monospacedDigit`), satır oynamaz.

**Renkler** (her ölçü kendi renginde, soldan sağa):

| Ölçü | Renk |
|---|---|
| CPU | `#2F7BFF` → `#5EE7FF` |
| GPU | `#A45CFF` → `#FF7EDB` |
| RAM | `#34D17A` → `#C6F56B` |
| İndirme | `#7CF5C8` (alan `#2BD4A4`'e söner) |
| Yükleme | `#FFB86B` |

**Network paneli:** küçük başlık `NETWORK` (8 semibold, aralık 0,8, beyaz 0,35); `↓ 1.7 MB/s` ve
`↑ 156 KB/s` (13 semibold, oklar 9 pt ve kendi renginde); altta 108 × 34 pt grafik: son 30
örnek (bir dakika), indirme dolgulu çizgi, yükleme ince çizgi, ikisi ortak ölçekte. Ağ yoksa
hızların yerinde `Offline`.

**Devices paneli:** küçük başlık `DEVICES` ve sağında sayı rozeti. Satır 20 pt: 5 pt nokta, ad
(11 medium), sağda IP'nin son parçası (`.104`, 10 pt, beyaz 0,38). Liste kaydırılır, alt kenarı
söner.

- Sıra: `Router`, `This Mac`, adı olanlar alfabetik, adı olmayanlar IP sırasıyla.
- Modemin noktası `#7CF5C8` halka, bu Mac'inki beyaz, diğerleri beyaz 0,35.
- Adı çözülemeyen cihaz tam IP'siyle yazılır (beyaz 0,55, son parça tekrarlanmaz).
- Sayı listedeki bütün satırlardır: bu Mac ve modem dahil.
- `.local` ve modemin eklediği alan adı (`.lan`, `.home`...) addan atılır; tireler boşluk olur.

### Ölçüm

- Yalnızca `System` sekmesi görünürken ölçülür. Sekme gizlenince ya da ada kapanınca durur; ada
  kapalıyken hiçbir şey çalışmaz. Son değerler saklanır, sekme yeniden açılınca hemen görünür.
- Kullanım ve ağ hızı 2 sn'de bir, sıcaklık 6 sn'de bir (her üçüncü örnekte). CPU ve ağ hızı iki
  örnek ister; ilk iki örnek 0,5 sn arayla alınır.
- İki örnek arası 10 sn'yi geçerse (uyku, ya da sekme o kadar gizli kaldıysa) o tur hız ve CPU
  değeri verilmez ve grafik sıfırlanır. Sayaç geri giderse (arayüz yeniden kalktı) yalnızca o
  örnek atlanır, grafik kalır. Ağ yoksa grafik boşalır.
- Çubuklar ve grafik yalnızca yeni örnekle değişir; çubuk geçişi Core Animation'da (0,6 sn).
  Kare kare çizim yok.
- CPU: çekirdeklerin toplam meşguliyeti (user + system + nice). RAM: uygulama + wired +
  sıkıştırılmış bellek (Activity Monitor'ün "Memory Used"ı). GPU: `Device Utilization %`.
- Sıcaklık: CPU için `Tp**` ve `Te**`, GPU için `Tg**` anahtarlarının **ortancası**; 10-120 °C
  dışındaki okumalar atılır. Ortalama değil, çünkü çoğu anahtar 40 °C'nin altını göstermiyor ve
  bazıları tepe değerini tutuyor. Bir anahtarı okumak ~170 µs sürdüğü için ilk okumada geçerli
  çıkanlardan eşit aralıklı en fazla 24 CPU ve 8 GPU anahtarı seçilir. Intel Mac'te bu fazda `—`.
  Anahtarların dörtte birinden fazlası tam 40,0'da duruyorsa çip 40 °C'den serindir ve ortanca
  40'ta takılır; o zaman 40'ın altını okuyan (tabansız) anahtarların ortalaması, yoksa 40
  gösterilir. Ölçüm (2026-11-21): boşta çip sensörleri (`tdie`) 35,5, tabansız anahtarlar 36,2,
  ortanca 40,0; yükte 42,1 / 50,6 / 56,6. Hangisinin "CPU sıcaklığı" olduğu için elde referans
  araç yok; yükte ortanca, serinken tabansız anahtarlar gösteriliyor.
- Ağ hızı: birincil arayüzün (varsayılan rota) bayt sayaçları.

### Ağdaki cihazlar

- **Kendiliğinden hiçbir paket gönderilmez** (2026-11-21, sahibi: "tarama düğmeyle olsun o zaman.
  Kaç kişi bağlı olduğunu paket göndermeden görebiliyorsak o kalsın"). Gerekçe: Mac hangi
  ağdaysa orası taranırdı; ofis, okul ya da kafe ağında bu şüpheli bir tarama gibi görünebilir ve
  uygulamayı indiren herkes için de böyle olurdu.
- Sekme görünür olunca yalnızca Mac'in zaten bildiği komşular okunur (komşu tablosu; izin
  gerektirmediği denendi) ve sayılır: bu, Mac'in konuştuğu cihazlardır, ağdaki herkes
  olmayabilir (denemede 6 cihazın 5'i). Yalnızca donanım adresi olan kayıtlar cihazdır. Bu Mac
  de tablodadır; kendi adresinden tanınır.
- Tarama yalnızca `Devices` panelindeki `Scan` düğmesine basınca yapılır: alt ağdaki her adrese
  bir UDP paketi; tablo 1 ve 3 sn sonra yeniden okunur. Aynı anda tek tarama; süresince düğme
  `Scanning…` olur ve basılamaz. Alt ağ /22'den genişse (1022 adresten çok) düğme çıkmaz.
- Adlar da yalnızca taramayla çözülür (onlar da ağa sorgu gönderir): önce modemin ters DNS'i,
  bulunamazsa mDNS ters sorgusu; cihaz başına 2 sn. Çözülen ad
  (ve bulunamadığı) IP + MAC ile uygulama kapanana kadar saklanır.
- 3 dk boyunca ARP'de görülmeyen cihaz listeden düşer.
- Yalnızca IPv4. Yayın ve multicast adresleri sayılmaz.

### İzin

- İzin penceresini ilk `Scan` basışı tetikler; uygulama açılışı ya da sekmenin açılması değil.
- Metin (`NSLocalNetworkUsageDescription`): "Symbiodock looks for the devices on your network to
  count them and show their names in the System tab."
- İzin verilmezse liste ARP'de zaten duranlarla kalır, panelin altında tek satır
  `Allow Local Network to find all devices` çıkar ve sağ tık menüsünün başına
  `Local Network access needed` gelir (`Music access needed` kalıbı). Madde
  `x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork` açar.
- Uygulama izin durumunu saklamaz; her taramada yeniden anlar.

## Gizlilik

- Hiçbir şey Mac'ten dışarı gönderilmez; tarama paketleri boş ve yalnızca yerel alt ağa gider.
- Cihaz adı, IP ve MAC diske yazılmaz ve hiçbir seviyede loglanmaz. Log yalnızca sayıları ve hata
  kodlarını taşır (`system` kategorisi).
- Yeni üçüncü taraf bağımlılık yok.

## Yapı

**Çekirdek** (`Packages/SymbiodockCore/Sources/SymbiodockCore/System/`, saf ve testli):

- `SystemSnapshot`: `cpu`, `gpu`, `memory`, `temperatures`, `network`; `Sendable`, `Equatable`.
- `CPUUsage`: tick farkından kullanım. `MemoryUsage`: sayfa sayılarından kullanılan bayt.
- `NetworkRate`: sayaç farkından bayt/sn, sıfırlama kuralıyla.
- `TemperatureKeys`: anahtar adını CPU / GPU diye sınıflar, aralık dışını atar, ortancayı alır,
  eşit aralıklı alt küme seçer.
- `SystemLabels`: `31%`, `45°`, `1.7 MB/s`, `18.5`; sıcaklık kademesi (80 ve 95 °C).
- `SystemMeter`: ham okumalardan `SystemSnapshot` üretir (uyku ve sayaç sıfırlama kuralı) ve
  `NetworkHistory`'yi (son 30 örnek, ortak ölçek) tutar.
- `IslandTab.system`; `IslandState`: `system`, `networkHistory`, `setSystem(_:history:)`
  ("yalnızca değişince ata").
- Bölüm B'de: cihaz listesi (birleştirme, eleme, ad temizleme, sıralama, sayım, 3 dk kuralı),
  `SubnetSweep` (taranacak adresler, /22 sınırı), `lanDevices`, `localNetworkDenied`.

**Uygulama** (`Symbiodock/System/`):

- `HostSampler` (`host_statistics`, `host_statistics64`), `GPUProbe` (IOKit),
  `SMCReader` (`AppleSMC`; anahtarlar bir kez sayılır), `ThermalFallback`
  (`IOHIDEventSystemClient`, `DockProbe` gibi `dlsym` ile), `NetworkCounterReader`
  (`NET_RT_IFLIST2`, birincil arayüz `SCDynamicStore`'dan).
- `SystemReader` (actor): bunları tek okumada toplar. `SystemCoordinator` (`@MainActor`):
  `IslandState`'i gözler (`withObservationTracking`), sekme görünürken döngüyü çalıştırır.
- Bölüm B'de: `LANScanner` (komşu tablosu, tarama, ad çözme).
- `DemoSystem`: `SYMBIODOCK_DEMO_SYSTEM=1|hot` (Bölüm B'de `denied`); `SYMBIODOCK_PRINT_SYSTEM=1`
  pencere açmadan dört okuma yazdırır (ikisi de yalnızca Debug).
- Görünüm: `Symbiodock/Island/System/SystemContent.swift`; çubuk için Core Animation katmanı.
- Bağlantılar: `TabStrip`, `TabGlyph`, `ExpandedIsland`, `IslandView`, `AppDelegate`,
  `IslandMenu`, `DebugRender`, `project.yml`, `Info.plist`.

## Sıra

- **Bölüm A (izin gerektirmez):** sekme, simge, CPU / GPU / RAM, sıcaklıklar, ağ hızı ve grafiği;
  `Devices` paneli başlığıyla durur, içinde `—`. Sonunda sahibi dener.
  Plan: `docs/superpowers/plans/2026-11-21-system-tab-a.md`.
- **Bölüm B (izinli):** cihaz listesi, tarama, adlar, izin reddi durumu, menü maddesi. Planı,
  aşağıdaki varsayımlar sahibinin izin penceresine basmasıyla denendikten sonra yazılır.

## Doğrulama

- Çekirdek testleri; ekran dışı görüntüler `expanded-system.png`, `expanded-system-hot.png`,
  `expanded-system-empty.png`, `tab-glyphs.png` (Bölüm B'de `expanded-system-denied.png`).
- Canlı karşılaştırma: CPU ve RAM Activity Monitor ile, GPU `ioreg` ile, sıcaklık bağımsız bir SMC
  okumasıyla, cihazlar `arp -an` ile.
- CPU maliyeti (`top` + `sample`): sekme kapalıyken %0; açıkken ortalama %1'in altı hedef.

## Doğrulanmamış varsayımlar

Her biri ilgili görevin ilk işi olarak denenir; sonucu `CLAUDE.md`'ye yazılır.

- **SMC anahtarları (2026-11-21'de yük altında denendi).** 14 `yes` süreciyle 14 sn: `Tp**`
  anahtarlarının 90'ı 6 °C'den çok yükseldi; boşta tam 40,0 okuyan `Tp0*` anahtarları 50-58'e
  çıktı (40 taban değeri, yer tutucu değil), `Tp1i` gibi tabansız olanlar 34'ten 46'ya. Swift'ten
  okuma: 3462 anahtarın sayımı 24 ms, 134 anahtarın okunması 23 ms; ortanca CPU 44,0 °C, GPU
  36,6 °C (ortalama 47,2 / 38,7; en yüksek 75,0 / 44,7). Adlar çipe göre değişiyor, başka çipte
  denenmedi; GPU yükü altında denenmedi. Yedek: `tdie` sensörlerinin ortalaması, CPU ve GPU'da
  aynı değer. Son incelemenin notu (aranarak bulundu, denenmedi): M3'te performans çekirdeği ve
  GPU anahtarları `Tf**` olabilir; o zaman CPU yalnızca `Te**` (E çekirdekleri) ortancasını, GPU
  çip sıcaklığını gösterir. Dağıtımdan önce çipe göre anahtar tablosu gerekir.
- **Komşu tablosu (2026-11-21, uygulamanın içinden denendi: okunuyor).** `open` ile başlatılan
  uygulama, izin verilmeden ve tek paket göndermeden tabloyu okudu (`NET_RT_FLAGS` +
  `RTF_LLINFO`, `AF_INET`): 860 bayt, donanım adresi olan 5 kayıt (modem, 3 cihaz ve bu Mac'in
  kendisi). Daha önce 0 bayt alan, Terminal'den çalıştırılan süreçti; yani çekirdek tabloyu
  sürecin ait olduğu uygulamaya göre veriyor. İzin açıkça reddedilince okunup okunmadığı
  denenmedi; okunamazsa liste boş kalır.
- **Tarama (denendi: çalışıyor).** Alt ağın 254 adresine boş UDP paketi (port 9): izin
  verilmeden önce 252'si `EHOSTUNREACH` (65) ile reddedildi ve izin penceresi çıktı; sahibi
  `Allow`'a basınca 254'ü de gönderildi. Tablo 254 kayda çıktı, ama yalnızca cevap verenlerin
  donanım adresi var: 6 cihaz (taramadan önce 5). Cihaz, donanım adresi olan kayıttır.
- **Adlar (denendi: kısmen).** Modemin ters DNS'i hiçbir cihaz için ad vermedi (0,02 sn'de
  cevapsız). mDNS ters sorgusu 6 cihazın 2'sinin adını verdi (bir iPhone ve bu Mac; 0,2 sn
  içinde), diğer dördü 2 sn'de cevap vermedi. Sorgular sırayla 8 sn sürdü; uygulamada aynı anda
  yapılır. Rastgele MAC'li iki cihaz ve üretici MAC'li iki cihaz (modem dahil) IP ile kalır.
- **İzin bekleme/red (kısmen denendi).** İzin verilmemişken gönderimlerin neredeyse hepsi 65
  hatası veriyor; "izin yok" bundan anlaşılır. Açıkça `Don't Allow` denen durum denenmedi.
- **Ad-hoc imza.** Debug sürümünde yeniden derlemeden sonra iznin tekrar sorulup sorulmadığı
  henüz görülmedi.
- **`/usr/sbin/arp`.** Uygulamanın içinden çalıştırılınca 0 satır verdi (izinden sonra da);
  yedek olarak kullanılamaz, gerek de kalmadı.

## Kapsam dışı

Kapalı adada gösterge ve sıcaklık uyarısı, RAM sıcaklığı, üretici adı (OUI), Wi-Fi adı, IPv6
cihazları, cihaz başına trafik, süreç listesi, pil ve disk, Intel'de sıcaklık.
