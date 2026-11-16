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

Seçtikleri: çevirme yalnızca yerleşik macOS araçlarıyla; çıktı orijinalin yanına yazılır ve
orijinal kalır; dışarı bırakılan karo raftan çıkar; raf yeniden açılışta geri gelir.

## Sınır

- "Her format" tek araçla olmaz. Yerleşik araçların yapabildiği kadarı var: karmaşık DOCX düzeni
  PDF'te birebir olmayabilir (TextEdit'in çıktısı kadar); XLSX/PPTX, MP3 yazma, MKV/WebM yok.
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

### İçeri bırakma

- Bir dosya sürüklenirken imleç adaya ya da dosya baloncuğuna girince ada beklemeden `Files` ile
  açılır (açıksa o sekmeye geçer); içerik kesikli çerçeve ve `Drop to hold` gösterir.
- Kabul edilenler: dosya ve klasör URL'leri; dosya sözleri (Safari'den görsel, Fotoğraflar, Mail
  eki); ham görsel verisi (PNG olarak yazılır). Söz verilen ve ham veriler
  `~/Library/Application Support/Symbiodock/Shelf/<uuid>/` altına alınır.
- Raf dosyayı kopyalamaz, konumunu tutar. Aynı dosya ikinci kez eklenmez, öne gelir.
- Bırakma kabul edilince `.levelChange` titreşimi.

### Dışarı sürükleme

- Karoya basıp 6 pt çekince dosya sürüklemesi başlar; ada kopmaz. Sütuna ve boş alana basıp
  çekmek bugünkü gibi adayı koparır. Karoya tıklamak onu seçer.
- Kopya mı taşıma mı olacağına hedef uygulama karar verir (Finder'daki gibi). Çöp Sepeti'ne
  bırakma sunulmaz.
- Başarılı bırakmada karo raftan çıkar; iptal edilirse yerine döner. Adanın kendi üstüne
  bırakmak iptaldir. Çevrilmekte olan karo sürüklenmez.
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
  `99+`).
- Rafta başka türler de varsa en fazla 2 tane daha, arkada ve sağdan taşarak: her biri bir
  öncekinin %84'ü, çapın %36'sı kadar kayık, rengi %70 opak.
- Tür renkleri: görsel `#32ADE6`, PDF `#FF453A`, belge `#0A84FF`, ses `#FF375F`, video
  `#5E5CE6`, arşiv `#FF9F0A`, klasör `#64D2FF`, diğer `#8E8E93`.
- Üstünde bekleyince ada `Files` ile açılır. Üstüne dosya bırakılabilir.
- Geçiş sol baloncuğun aynası: adanın sağ kenarının arkasından kayıp büyür. Reduce Motion'da solar.
- Kenar ışığına, çentiğin altından geçen çizgiye ve sağdaki işarete dokunulmaz.

### Kalıcılık

- UserDefaults `shelfItems`: her öğe için kimlik, bookmark, klasör mü. Açılışta çözülür;
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
- Uygulama (`Symbiodock/`):
  - `Files/`: `ShelfCoordinator`, `ShelfStorage`, `FilePreviews`, `ToolRunner`, `FileConverter`,
    `DocumentPDFWriter`, `DemoFiles`.
  - `Island/Files/`: `FilesContent`, `FileTile`, `FileActionsColumn`, `EngulfView`,
    `FileKindPalette`, `FilesBubble`.
  - `Window/`: `ShelfStore`, `FileDragSource`; `IslandGeometry.fileDragRects`;
    `OverlayController` bırakma hedefi, dosya sürüklemesi ve iki baloncuk.
- Deneme: `SYMBIODOCK_DEMO_FILES=1|converting`; ekran dışı görüntüler `expanded-files.png`,
  `expanded-files-empty.png`, `expanded-files-drop.png`, `engulf.png`,
  `collapsed-files-bubble.png`. Tek çevirme, pencere açmadan:
  `SYMBIODOCK_CONVERT=<dosya> SYMBIODOCK_CONVERT_TO=<çip>` (yalnızca Debug).

## Kapsam dışı

Çoklu seçim ve toplu sürükleme; karoları yeniden sıralama; metin ve bağlantı bırakma; XLSX/PPTX;
MP3 yazma; MKV/WebM; video → GIF; kenara yanaşık adada dosya baloncuğu; çevirme ayarları
(kalite, boyut); adadan dosya açma.
