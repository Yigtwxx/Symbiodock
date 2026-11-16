# Files sekmesi: dosya rafı, format çevirme, venom sarma (2026-11-16)

## İstek

Sahibi: "3. bir sekme ekleyelim adada dosya tutma. Mesela pencereli ekrandan bir dosyayı oraya
sürükleyip bırakayım sonra 3 parmak yana kaydırıp tam ekran bir pencereye oradan sürükleyip
alabileyim... Fotoğraf klasör dosya her şeyi koyabileyim. Bir de Dosya sekmesine koyduğum
dosyaları isteğe göre formunu değiştirebileyim. Mesela docx olarak oraya koyuyorum sonra orada
pdfe çevir gibi bir seçenek çıkıyor sağda ona basınca pdf oluyor bunu her format olacak şekilde
istiyorum. Bir de bu efektli olsun venom gibi o dosyayı çevresinden sarmalasın tamamen kapatsın
siyah olsun ve açılsın açıldığında format değişmiş olsun (venom efekti çentikteki gibi olsun
yine)."

Sonra: "dosya sekmesi hep gözüksün ama 3. sekme olarak"; "eğer oraya dosya koyduysak o da müzik
şeyi gibi yuvarlak olup sağ tarafta gözüksün ve kaç adet dosya olduğu gözüksün ve fotoğraf mı
pdf mi olduğu renklerle belirtilsin (arka arkaya efekti uygulu bunu yaparken oynatıcılarda
yaptığımız gibi)".

Aynı gün, raf sayfası çıkınca: "dosya dönüştürme işlemi için birden fazla seçebilelim. Mesela 2
docx 1 pptx pdfe çevirilecek hepsini çevirsin. Ayrıca bunları aynı yere koyunca da arka arkaya
dosya çekmeceleri gibi gözüksün... öndeki tamamen gözüksün, arkadakinin üst kısmı gözüksün ama
mouse ile üzerine gelince hafif yukarı kalksın." Sorulara cevapları: yığın hem birlikte
bırakınca hem karoyu karoya sürükleyince oluşsun; dikey çekmece görünümü; PPTX için "olmuyorsa
sıkıntı yok... ekstra bir şey kurmak zorunda kalmayalım, başka kullanıcılar indirdiğinde bir
sürü bir şeyle uğraşmasınlar"; yığın gövdesinden tutulunca hepsi birlikte sürüklensin, "en
öndekinin de üst kısmından tutarsa sadece en öndekini alsın".

Seçtikleri: çevirme yalnızca yerleşik macOS araçlarıyla; çıktı orijinalin yanına yazılır ve
orijinal kalır; dışarı bırakılan karo raftan çıkar; raf yeniden açılışta geri gelir.

## Sınır

- "Her format" tek araçla olmaz. Yerleşik araçların yapabildiği kadarı var: karmaşık DOCX düzeni
  PDF'te birebir olmayabilir (TextEdit'in çıktısı kadar); XLSX/PPTX, MP3 yazma, MKV/WebM yok.
  PPTX ve XLSX için Keynote/Numbers ya da LibreOffice gerekir; sahibi ek kurulum istemedi. Bu
  dosyalar rafta durur, yalnızca ZIP yapılır; toplu çevirmede atlanır ve bu söylenir.
- Panel bütün ekranı kaplıyor ve yalnızca imleç adadayken tıklama alıyor. Dosya sürüklemesi de
  aynı kurala bağlı: imleç adaya girince panel bırakma hedefi olur (aşağıda "Doğrulanmamış").
- Sistem, sürüklenen dosyanın bırakıldığı uygulamada kopyalanıp kopyalanmadığını ancak bırakma
  anında söyler; rafın kendi klasöründeki dosyalar bu yüzden o anda silinmez, sonraki açılışta
  temizlenir.

## Davranış

### Sekme

- `Files` şeritte her zaman görünür ve hep sondadır (`Agents`, `Media`, `Files`). `First tab`
  menüsü yalnızca `Agents` ile `Media`'yı sıralar. Simge `tray.full`.
- Hover'da açılacak sekme kuralı aynı: ilgi bekleyen agent, sonra sırada içeriği olan ilk sekme.
  Yalnızca rafta bir şey varsa ada `Files` ile açılır.
- Solda yatay kaydırılan karo şeridi, sağda 168 pt'lik işlem sütunu, arada ince çizgi.
- Karo 64 × 96 pt: 48 pt önizleme (Quick Look; yoksa dosya simgesi), altında ad (10 pt, tek
  satır, ortadan kısalır) ve tür renginde uzantı rozeti. En yeni solda. Seçili karonun zemini
  beyaz %10. Yeni eklenen karo seçilir.
- İşlem sütunu (seçili karo): ad, yanında `Show in Finder` ve `Remove` simgeleri; boyut ve tür;
  `Convert to` başlığı altında 4 sütunlu çipler. Çevirirken çiplerin yerinde `Converting to PDF…`
  ve `Cancel`. Hata olursa bir satır kısa hata metni.
- Boş raf: `tray.and.arrow.down` simgesi ve `Drop files here`. Başlığın sağında `3 items`.
- Sağ tık menüsünde, raf doluyken `Clear Files`.

### Görünüm (yeniden tasarım, 2026-11-16)

Sahibi ilk raf sayfasını görünce: "dosya sekmesinin genel ui'ı çok hoşuma gitmedi, bi tık daha
güzel bir şeyler yap." İlk sürümün kusurları: siyah üstünde beyaz Finder belge simgeleri, gri
hap çipler, ortadan kısalan adlar (`Holi….heic`), düz çizgiyle ayrılmış sütun; adanın diğer
sekmelerindeki özen yoktu. Yeni görünüm aşağıdakidir ve "Sekme" bölümündeki karo ile sütun
ölçülerinin yerine geçer (64 × 96 kutu, 168 pt sütun ve davranışlar aynı kalır).

- **Kart, tür renginde cam.** Her dosya 12 pt köşeli bir karttır: zemini tür renginin yukarıdan
  aşağı %24 → %8 geçişi, kenarı aynı rengin %35'i (0,5 pt). Sistem belge simgesi hiçbir yerde
  kullanılmaz.
- **Üst bölüm (önizleme).** Görsel, video ve PDF'te gerçek önizleme kartın üstünü doldurur
  (aspect fill, üst köşeler kartla aynı). Belgede Quick Look sayfası küçük bir kâğıt gibi,
  hafif gölgeyle ortada durur. Önizlemesi olmayanlarda (ses, arşiv, klasör, diğer, bulunamayan
  dosya) tür renginde büyük bir SF Symbols simgesi: `waveform`, `doc.zipper`, `folder.fill`,
  `doc.fill`, `photo`, `film`, `doc.richtext.fill`, `doc.text.fill`.
- **Alt bölüm.** Uzantısız ad (10 pt medium, beyaz %90, tek satır, sondan kısalır) ve altında
  tür renginde uzantı (8 pt heavy, harf aralıklı, hap zemini yok).
- **Seçili kart:** tür renginde 1,5 pt halka ve daha güçlü zemin (%34 → %14). Gri plaka yok.
- **Yığın:** arkadaki kartlar kendi tür renklerinde aynı cam yüzeylerdir; çekmece, renkli
  sekmeli dosyalar gibi okunur. Görünen şerit birkaç pt olduğundan arka kartın rengi daha
  güçlüdür (%46 → %16, kenar %50; bütün yığın seçiliyken %60, kenar %75); %32'de kehribar
  kahverengi, kırmızı bordo okunuyordu. Gri (diğer) sekme %60 gücünde: tam güçte koyulaşan
  renklerin yanında yığının en parlak sekmesi oluyordu. Arka kartlar öndeki kartın üstünden
  iki köşe yarıçapı aşağıda biter, öndeki kart kalkınca altından görünmez.
- **İşlem sütunu bir panel:** çizgi yerine beyaz %5 zeminli panel; köşesi adanınkiyle eş
  merkezli (16 pt: adanın 24 pt'lik köşesi, 8 pt'lik kenar boşluğu). Ad 12 pt
  semibold; ayrıntı satırının başında tür renginde nokta; simge düğmeleri 20 pt daire (beyaz
  %8). `CONVERT TO` küçük, harf aralıklı başlık.
- **Çipler hedef türünün renginde:** `PDF` kırmızı, `PNG`/`JPEG` mavi, `ZIP` amber…: yazı o
  renkte, zemin %16, kenar %30, 7 pt köşe, 20 pt yükseklik; `CONVERT TO`'nun üstünde 4 pt. İki sıra çiple
  panel, çentikteki 150 pt'lik adanın bıraktığı 110 pt'yi tam doldurur ve alt kenarı
  kartlarınkiyle aynı hizada kalır (5 pt'de 1 pt taşıyordu); basılıyken %55.
- **Boş raf:** her zaman görünen kesikli bırakma alanı (beyaz %14), ortasında simge, `Drop files
  here` ve altında `They stay while you switch spaces` (10 pt, beyaz %35). Dosya sürüklenirken
  alan parlar (beyaz %45) ve `Drop to hold` yazar.

### Yığınlar (dosya çekmecesi)

- Rafın her yeri bir yığındır; tek dosya, tek kartlı yığındır ve bugünkü karo gibi görünür.
- Yığın oluşur: (1) tek seferde birden fazla dosya bırakılınca (hepsi tek yığın, ilk dosya
  önde; Fotoğraflar'dan ya da Mail'den gelen söz verilmiş dosyalar tek tek gelse de: bırakma
  anında bu bırakmaya bir yığın ayrılır, ilk gelen onu kurar, sonrakiler geliş sırasıyla
  arkasına katılır); (2) dışarıdan sürüklenen dosya bir karonun ya da yığının üstüne bırakılınca (öne
  eklenir); (3) raftaki bir karo ya da yığın başka birinin üstüne sürüklenince. Boş alana
  bırakılan tek dosya ayrı karo olur.
- Görünüm, dikey çekmece: öndeki kart tam görünür; arkadakilerin yalnızca üst şeridi, her biri
  bir öncekinin üstünden 7 pt taşarak ve iki yandan 3 pt daralarak görünür. Dosya çoğaldıkça
  şerit incelir (en az 3 pt, toplam taşma 21 pt'yi geçmez); en fazla 7 arka kart çizilir,
  fazlası sayılır ama çizilmez. Yığının kutusu tek karodan 8 pt yüksektir (64 × 104) ve alta
  hizalanır; öndeki kartın önizlemesi kalan yere göre küçülür. Adet, öndeki kartın üst
  kenarına sağda iğnelenmiş bir haptır (yarısı saydığı sekmelerin, yarısı kartın üstünde;
  siyah %80): kartın içinde sayfanın ya da görselin köşesine biniyordu.
- İmleç bir arka kartın şeridine gelince o kart 6 pt yukarı kalkar (yay animasyonu) ve yığının
  ad satırı o dosyanın adını gösterir. Öndeki kartın üst 12 pt'lik şeridi de aynı şekilde
  davranır (yalnızca öndeki dosya). Kalkan kartın arkasındakiler, hemen arkadaki şerit en az
  3 pt görünecek kadar birlikte kalkar (7 pt'lik şeritte 2 pt): yoksa 6 pt kalkan kart onu
  1 pt'lik bir çizgiye indiriyordu. Gövdede beklerken yığının tamamı 3 pt kalkar. Reduce
  Motion'da hiçbir şey kalkmaz; şeritte o kartın, gövdede öndeki kartın kenarı parlar.
- Tıklama: şeride tıklamak o dosyayı tek başına seçer ve öne getirir; gövdeye tıklamak yığının
  tamamını seçer. Neyin seçileceğine basılan yer karar verir, bırakılan yer değil (şerit 3–7 pt,
  sürükleme eşiği 6 pt: kayan bir tıklama komşu dosyayı seçerdi); aynı karar sürüklemede neyin
  gideceğini de belirler. Tıklama yığını yeniden sıraladıysa imleç kıpırdayana kadar altındaki
  kart kalkmaz. Kutunun kartsız köşeleri boş alandır: oradan basıp çekmek adayı koparır.
- Yığından çıkarma: bir dosyayı şeridinden tutup karo şeridinin boş yerine bırakmak onu ayrı
  karo yapar. İşlem sütunundaki `Unstack` simgesi (tek bir yığının tamamı seçiliyken) yığını
  ayrı karolara dağıtır.
- Hover bilgisi SwiftUI'dan değil, pencere denetleyicisinin zaten izlediği imleç konumundan
  gelir; durum yalnızca değişince atanır. İstirahatte hiçbir şey çizilmez.

### Çoklu seçim ve toplu çevirme

- ⌘-tıklama seçime ekler ya da çıkarır (şeritte tek dosya, gövdede bütün yığın). Düz tıklama
  seçimi yeniden kurar. Seçili kart "Görünüm"deki gibi tür renginde halka ve güçlü zemin alır.
  Bütünü seçili yığında halka öndeki kartta, arkadaki sekmeler parlar; yığının içinden tek dosya
  seçiliyse halka yalnızca onun kartında (arkadaysa sekmesinde) olur.
- Birden fazla dosya seçiliyken sütun: `3 files`, altında toplam boyut; `Show in Finder` hepsini
  gösterir, `Remove` hepsini raftan çıkarır.
- Ortak çipler: seçimdeki "çevrilebilir" dosyalar (ZIP dışında en az bir hedefi olanlar)
  üzerinden hesaplanır. Bir hedef, her çevrilebilir dosya ya o hedefi sunuyorsa ya da zaten o
  formattaysa ve en az biri sunuyorsa çıkar. Sıra, hedeflerin seçimde ilk göründüğü sıradır.
  Sonda her zaman `ZIP`. Hepsi ZIP ise yalnızca `Unzip`.
- Çipe basınca: o hedefi sunan her dosya çevrilir; zaten o formatta olan sessizce atlanır;
  hiçbir hedefi olmayan (PPTX, MKV…) atlanır ve sütunda söylenir: `Slides.pptx can't become
  PDF`, birden fazlaysa `2 files can't become PDF`. Başarısız olan olursa `Couldn't convert 1
  file`. Örnek: 2 DOCX + 1 PPTX seçili → `PDF` çıkar; iki DOCX çevrilir, PPTX atlanır.
- Toplu `ZIP`, Finder'ın `Compress`'i gibidir: hepsi tek `Archive.zip` olur (ilk dosyanın
  klasörüne; ad doluysa `Archive 2.zip`). Orijinaller diskte kalır; rafta seçimin yerini tek
  `Archive.zip` karosu alır.
- Dosyalar sırayla çevrilir. Ayrı karolar kendi işi bitince açılır; bir yığının dosyaları
  birlikte açılır (yığın tek koza olarak sarılır). `Cancel` hepsini iptal eder.

### İçeri bırakma

- Bir dosya sürüklenirken imleç adaya ya da dosya baloncuğuna girince ada beklemeden `Files` ile
  açılır (açıksa o sekmeye geçer); içerik kesikli çerçeve ve `Drop to hold` gösterir.
- Kabul edilenler: dosya ve klasör URL'leri; dosya sözleri (Safari'den görsel, Fotoğraflar, Mail
  eki); ham görsel verisi (PNG olarak yazılır). Söz verilen ve ham veriler
  `~/Library/Application Support/Symbiodock/Shelf/<uuid>/` altına alınır.
- Raf dosyayı kopyalamaz, konumunu tutar. Aynı dosya ikinci kez eklenmez, öne gelir (bir
  yığının üstüne bırakıldıysa o yığına geçer).
- İmleç bir karonun ya da yığının üstündeyken o hedef kesikli beyaz çerçeveyle vurgulanır ve
  baştaki boş yer tutucu gizlenir (yeri korunur): bırakılanlar o yığına katılır. Yer tutucu
  sürükleme adaya girdiği anda, imleç henüz bir karonun üstünde değilken yer açar; sonradan
  imlecin altından karo kaymaz.
- İçinde çevrilen dosya olan yığın (koza) bırakma almaz: başlık gibi davranır; vurgu yok,
  kalkmaz, bırakma reddedilir.
- Bırakma kabul edilince `.levelChange` titreşimi.

### Dışarı sürükleme

- Karoya basıp 6 pt çekince dosya sürüklemesi başlar; ada kopmaz. Sütuna ve boş alana basıp
  çekmek bugünkü gibi adayı koparır. Karoya tıklamak onu seçer.
- Yığında neyin sürükleneceğini basılan yer belirler, seçim değil: gövdeden tutulunca yığının
  bütün dosyaları birlikte gider; bir arka kartın şeridinden ya da öndeki kartın üst şeridinden
  tutulunca yalnızca o dosya gider. Her dosya ayrı bir sürükleme öğesidir (öndeki önce); ilk
  beşinin görüntüsü öndeki kartın resminden sağa yukarı 4'er pt yelpaze açar, gerisi görüntüsüz
  gider. Görüntü kartın gösterdiğidir: önizleme ya da tür camında tür simgesi, Finder simgesi
  değil.
- Sürüklenen karo adanın içinde başka bir karoya bırakılırsa yığına katılır (önüne), karo
  şeridinin boş yerine bırakılırsa (yığından geldiyse) ayrı karo olur (ayrıldığı yığının hemen
  arkasına); ikisinde de raftan çıkmaz. Hedef yığın kesikli çerçeveyle gösterilir; boş yer,
  satırın tamamını saran kesikli çerçeveyle: satırın üstüne çizilir, yer açmaz, böylece hiçbir
  karo imlecin altından kaymaz (yığınlar arasındaki 8 pt'lik boşluk da boş yerdir; yer tutucu
  satırı 72 pt kaydırıyordu ve bırakma komşu yığına düşüyordu). Bırakmanın reddedileceği yerde
  (sütun, başlık, dosyanın geldiği yığın, çevrilen yığın) çerçeve görünmez. Bütün bir yığını
  boş yere ya da bir dosyayı kendi yığınına bırakmak hiçbir şey değiştirmez ve reddedilir.
- Sürükleme adadan çıkıp ada kapandıktan sonra geri gelirse ada, dışarıdan gelen dosyada
  olduğu gibi beklemeden `Files` ile açılır.
- Kopya mı taşıma mı olacağına hedef uygulama karar verir (Finder'daki gibi). Çöp Sepeti'ne
  bırakma sunulmaz. Rafın kendi klasöründeki dosyalar (söz verilen, ham görsel) için takma ad
  (`.link`) da sunulmaz: klasör temizlenince takma ad kırılırdı.
- Başarılı bırakmada giden dosyalar raftan çıkar; iptal edilirse yerine döner. Adanın başka
  bir yerine bırakmak iptaldir. İçinde çevrilen dosya olan yığın ve çevrilen karo sürüklenmez.
- Sürükleme sırasında imleç adadan çıkınca ada her zamanki gibi kapanır ve panel tıklamaları
  bırakır; böylece bırakma alttaki uygulamaya gider.

### Çevirme

Kendi formatı listelenmez; ZIP dışındaki her öğede son çip `ZIP`'tir.

| Kaynak | Hedefler | Araç |
|---|---|---|
| Görsel (png, jpg, jpeg, heic, heif, tiff, tif, gif, bmp, webp, avif, jp2, psd, ico, icns, svg, raw) | PNG, JPEG, HEIC, TIFF, GIF, BMP, PDF | `/usr/bin/sips` |
| Belge (docx, doc, rtf, rtfd, txt, md, html, htm, odt, webarchive) | PDF, DOCX, RTF, TXT, HTML, ODT | `/usr/bin/textutil`; PDF: `NSTextView` + `NSPrintOperation` |
| PDF | PNG, JPEG, TXT | PDFKit (150 dpi) |
| Ses (mp3, m4a, aac, wav, aif, aiff, flac, caf) | M4A, WAV, AIFF, FLAC | `/usr/bin/afconvert` |
| Video (mov, mp4, m4v) | MP4, MOV, M4A | `AVAssetExportSession` |
| Klasör ve her dosya | ZIP | `/usr/bin/ditto -c -k --sequesterRsrc --keepParent` |
| ZIP | Unzip | `/usr/bin/ditto -x -k` |

- Çıktı orijinalin klasörüne, aynı adla ve yeni uzantıyla yazılır (`report.docx` → `report.pdf`);
  ad doluysa `report 2.pdf`, `report 3.pdf`. Önce aynı klasörde gizli geçici ada yazılır, bitince
  yeniden adlandırılır; hata ya da iptalde geçici dosya silinir.
- Çok sayfalı PDF → görsel: `report pages/report-01.png …` klasörü; karo klasör olur. Tek sayfada
  tek dosya. Metni olmayan PDF → TXT hatadır (`No text in this PDF`).
- Orijinal diskte kalır; karo yeni dosyayı gösterir ve seçili kalır.
- Klasöre yazılamıyorsa (`Can't write to this folder`) ya da araç başarısız olursa
  (`Couldn't convert to PDF`) karo eski haliyle açılır.
- Araçlar mutlak yolla, argüman dizisiyle, kabuk olmadan ve en az ortam değişkeniyle çalışır;
  uygulama kapanırken sonlandırılır.

### Venom sarma efekti

Karonun tamamını (önizleme, ad, rozet) kaplar; çentikteki efektle aynı çizim: metaball katmanı
(blur 5 + alpha eşiği 0,5), incelen şeritler, üstte beyaz %34 parlaklık.

1. **Engulf, 0,7 sn.** Karonun çevresinden 12 lif kademeli olarak içeri uzanır; uçları ince ve
   boncuklu, kökleri kalınlaşır; lifler birleşir ve karo tamamen siyah olur. Kapanınca
   `.levelChange` titreşimi.
2. **Cocoon.** Çevirme bitene kadar, en az 0,25 sn. Durağan siyah koza; kare kare çizim yok,
   yalnızca parlaklık Core Animation ile nefes alır. Karonun içeriği bu sırada değişir.
3. **Reveal, 0,6 sn.** Örtü ortadan incelip liflere ayrılır, lifler köklerine geri çekilir;
   altından yeni önizleme, ad ve rozet çıkar. Başında `.levelChange` titreşimi.

Hata ve iptalde de aynı açılış oynar. Reduce Motion: 0,2 sn kararma, 0,2 sn açılma.
İstirahatte ve koza beklerken `TimelineView` yoktur (animasyon maliyeti kuralı).

### Dosya baloncuğu

- Ada çentikte ve kapalıyken raf doluysa adanın **sağında** siyah daire: sol baloncukla aynı çap
  (28 pt, kısa çentikte çentik boyu − 4), aynı 6 pt boşluk, çentik bandında dikey ortalı. Kanatlar
  varsa onların sağında.
- İçinde en son eklenen dosyanın tür renginde disk (çapın 22/28'i) ve beyaz adet (99'dan çoksa
  `99+`). Adet dosya sayısıdır, yığın sayısı değil.
- Rafta başka türler de varsa en fazla 2 tane daha, arkada ve sağdan taşarak: her biri bir
  öncekinin %84'ü, çapın %36'sı kadar kayık, rengi %70 opak.
- Tür renkleri: görsel `#32ADE6`, PDF `#FF453A`, belge `#0A84FF`, ses `#FF375F`, video
  `#5E5CE6`, arşiv `#FF9F0A`, klasör `#64D2FF`, diğer `#8E8E93`.
- Üstünde bekleyince ada `Files` ile açılır. Üstüne dosya bırakılabilir.
- Geçiş sol baloncuğun aynası: adanın sağ kenarının arkasından kayıp büyür. Reduce Motion'da solar.
- Kenar ışığına, çentiğin altından geçen çizgiye ve sağdaki işarete dokunulmaz.

### Kalıcılık

- UserDefaults `shelfItems`: her öğe için kimlik, bookmark, klasör mü, yığın kimliği (eski
  kayıtlarda yok: her dosya ayrı karo). Açılışta çözülür;
  bulunamayan öğe düşer. Taşınan ya da yeniden adlandırılan dosya bookmark ile bulunur.
- Açılışta rafın klasöründe hiçbir karoya ait olmayan alt klasörler silinir. `Remove` ve
  `Clear Files` rafın kendi klasöründeki dosyayı hemen siler; başka yerdeki dosyaya dokunmaz.

## Risk

- Dosya baloncuğu çentiğin sağında 40–60 pt kaplar; oradaki menü çubuğu simgelerinin üstüne
  binebilir (sol baloncuktaki riskin aynısı).
- `NSPrintOperation` ana iş parçacığında çalışır; uzun belgede ada kısa süre donabilir. Koza
  durağan olduğu için görünmez; rahatsız ederse Core Text ile arka planda sayfalamaya geçilir.

## Doğrulanmamış

1. Başka uygulamanın sürüklemesi sırasında global `.leftMouseDragged` olayı geliyor (hover bugün
   de buna dayanıyor). Yedek: global `leftMouseDown` ile başlayıp bırakınca duran 30 Hz yoklama.
2. Sürükleme ortasında `ignoresMouseEvents = false` yapılan panel bırakma hedefi oluyor. Yedek:
   yalnızca dosya sürüklemesi boyunca gösterilen, ada boyunda ayrı küçük bırakma paneli.
3. `beginDraggingSession` sırasında 30 Hz yoklama zamanlayıcısı çalışmaya devam ediyor. Yedek:
   `draggingSession(_:movedTo:)` içinden `refreshPointer()` (ikisi de yazılır).

## Yapı

- Çekirdek (`Packages/SymbiodockCore/Sources/SymbiodockCore/`):
  - `IslandTab.files`; `TabOrder.reorderable`; `TabSelection.tabToOpen(... filesHasContent:)`.
  - `Files/FileKind.swift`, `Files/FileShelf.swift` (`ShelfItem`, `FileShelf`, `FileRequest`,
    `FileConversion`), `Files/ConversionCatalog.swift`, `Files/OutputNaming.swift`,
    `Files/SymbioteEngulf.swift`, `Files/EngulfTiming.swift`.
  - `SymbioteGeometry.swift`: `SymbioteSimulation`'ın şerit, eğri ve parlaklık yardımcıları
    modül içine açılır.
  - `IslandState`: `shelf`, `conversions`, `shelfNotice`, `isFileDragHovering`,
    `filesBubbleShown`.
  - `IslandLayout.filesBubbleFrame`, `filesBubbleHitRect`.
  - Yığınlar: `ShelfStack`, `FileShelf.stacks/selection`, `Files/StackLayout.swift` (kart
    çerçeveleri ve isabet), `ConversionCatalog.commonLabels/plan`, `IslandState.hoveredFile`,
    `fileDropTarget`.
- Uygulama (`Symbiodock/`):
  - `Files/`: `ShelfCoordinator`, `ShelfStorage`, `FilePreviews`, `ToolRunner`, `FileConverter`,
    `DocumentPDFWriter`, `DemoFiles`.
  - `Island/Files/`: `FilesContent`, `StackTile`, `FileCard`, `FileActionsColumn`, `EngulfView`,
    `FileKindPalette`, `FilesBubble`.
  - `Window/`: `ShelfStore`, `FileDragSource`; `IslandGeometry.fileDragRects`;
    `OverlayController` bırakma hedefi, dosya sürüklemesi ve iki baloncuk.
- Deneme: `SYMBIODOCK_DEMO_FILES=1|converting`; ekran dışı görüntüler `expanded-files.png`,
  `expanded-files-multi.png`, `expanded-files-hover.png`, `expanded-files-empty.png`,
  `expanded-files-drop.png`, `file-stacks.png`, `engulf.png`, `collapsed-files-bubble.png`.
  Tek çevirme, pencere açmadan: `SYMBIODOCK_CONVERT=<dosya> SYMBIODOCK_CONVERT_TO=<çip>`
  (yalnızca Debug).

## Kapsam dışı

Karoları yeniden sıralama; lastik bantla ya da ⇧ ile aralık seçimi; birbirinden ayrı seçili
karoları tek sürüklemede taşıma (yığın birlikte sürüklenir); metin ve bağlantı bırakma; XLSX/PPTX;
MP3 yazma; MKV/WebM; video → GIF; kenara yanaşık adada dosya baloncuğu; çevirme ayarları
(kalite, boyut); adadan dosya açma.
