# MacDPI

macOS için Discord ve Roblox'a yönelik DPI bypass. Bu iki uygulama, TUN modundaki
[sing-box](https://github.com/SagerNet/sing-box) arkasında duran yerel bir
[byedpi](https://github.com/hufrea/byedpi) proxy'sinden geçirilir. Makinedeki diğer
her şey normal şekilde çıkar.

İnternet sağlayıcı bu servisleri aynı anda üç yolla engelliyor: SNI tabanlı DPI, DNS
zehirleme ve QUIC. Bu kurulum üçünü de aşar. Hem Apple Silicon hem Intel Mac'lerde
çalışır.

## Gereksinimler

- macOS (Apple Silicon veya Intel)
- Yönetici şifresi (sing-box TUN arayüzünü kurmak için root ister)

`ciadpi` ve `sing-box` binary'leri `bin/Build.sh` tarafından kaynaktan derlenir;
script gereken derleme araçlarını kendisi indirir (bkz. Derleme). Binary'ler yoksa
veya farklı bir işlemci için derlenmişse, `Run.sh` ilk çalıştırmada onları otomatik
derler.

## Çalıştırma

```
./Run.sh
```

Gerekirse binary'leri derler, `settings.conf`'tan sing-box config'ini üretir, proxy
ve tüneli başlatır, Wi-Fi'yi sabit IP'ye alır ve DNS'i DoH üzerinden Cloudflare'e
yönlendirir. Ctrl+C her şeyi durdurur ve ağı DHCP'ye geri döndürür.

Yalnızca proxy ya da yalnızca tünel:

```
./core/RunDPI.sh
./core/RunSingBox.sh
```

### Düzen

```
Run.sh  ServiceInstall.sh  ServiceRemove.sh  ServiceRestart.sh  settings.conf
bin/    ciadpi, sing-box (derlenmiş), Build.sh
core/   GenConfig.sh, RunDPI.sh, RunSingBox.sh
net/    SetStaticIP.sh, UnsetStaticIP.sh
logs/   box.log, service.log
```

Kök dizinde giriş noktaları ve `settings.conf` durur; gerisi işlevine göre
gruplanmıştır. Her script proje kökünden doğrudan çalıştırılabilir.

## Servis olarak çalıştırma

Bypass'ı yeniden başlatmalar arasında açık tutmak için launchd servisi olarak kur:

```
./ServiceInstall.sh
./ServiceRemove.sh
```

Kurulum gerekirse binary'leri derler, sonra açılışta çalışan bir sistem servisi
kaydeder. Kaldırma servisi durdurur, siler ve ağı DHCP'ye döndürür.

Servis çalışırken `settings.conf`'u izler. O dosyayı düzenleyip kaydedince servis
birkaç saniye içinde kendini yeniden başlatır ve config'i değişikliklerinle yeniden
üretir — elle bir adım gerekmez. Kendin yeniden başlatmak için:

```
./ServiceRestart.sh
```

(Bu otomatik yeniden başlatma yalnızca serviste olur. Ön planda çalışan bir
`./Run.sh` için config değişikliklerini durdurup yeniden başlatınca uygular.)

Bunun çalışması için proje Desktop, Documents ve Downloads dışında olmalı. macOS
arka plan servislerinin bu klasörleri okumasını engeller, o yüzden
`ServiceInstall.sh` oralardan çalışmayı reddeder. `~/MacDPI` gibi bir yer uygundur.
Bu sadece servisi etkiler; `./Run.sh`'ı elle her yerden çalıştırabilirsin.

## Yapılandırma

Her şey tek bir dosyayla, `settings.conf` ile yönetilir. Düzenlenecek bir
`config.json` yok — sing-box config'i `settings.conf`'tan üretilip her çalıştırmada
doğrudan sing-box'a aktarılır, yani hiç diske yazılmaz. `settings.conf` şunları
belirler:

- `PROXY_PORT` — ciadpi ile sing-box'ın paylaştığı yerel port
- `CIADPI_ARGS` — desync stratejisi (bkz. Desync stratejisini değiştirme)
- `DOH_SERVER` — DoH çözümleyici, ki sağlayıcı DNS'i zehirleyemesin
- `BLOCK_QUIC` — UDP 443'ü düşür ki uygulamalar desync'in çalıştığı TCP'ye düşsün
- `MODE` — `selective` yalnızca listelenen `APPS` ve `DOMAINS`'i bypass'tan geçirir,
  geri kalan her şeyi direkt gönderir; `global` her şeyi bypass'tan geçirir, yalnızca
  LAN trafiği ile ciadpi'nin kendi bağlantıları hariç
- `APPS` / `DOMAINS` — `selective` modunda neyin bypass edileceği

`core/GenConfig.sh` config'i üretir: argümansız çalışınca stdout'a yazar (sing-box'a
aktarılan budur); `core/GenConfig.sh --out cfg.json` ise bir dosyaya yazar, üretilen
config'i incelemek için kullanışlı. Her iki durumda da sing-box ile doğrulanır ve
`Run.sh` bu doğrulamayı ağa dokunmadan önce yapar, böylece bozuk bir `settings.conf`
erkenden hata verir.

byedpi, `CIADPI_ARGS`'taki desync stratejilerini bir yedek zinciri olarak çalıştırır.
Bağlantı sıfırlanır ya da TLS el sıkışması başarısız olursa bir sonrakine geçer ve
kazananı IP başına önbelleğe alır.

## Sabit IP

sing-box'ın TUN yönlendirmesi DHCP kira yenilemelerini iyi atlatamaz. Yenilemede
varsayılan rota birkaç saniye düşer, sing-box bunu "arayüz yok" diye okur ve tüm
bağlantıları dondurur; bu da oyun ortasında kopma olarak görünür. Sabit IP'nin
kirası olmadığından yenilemesi de olmaz, yani bu hiç yaşanmaz. Run.sh başlangıçta
uygular, çıkışta DHCP'ye döndürür.

Adres, modemin alt ağı artı `.240` host'udur; bu, olağan DHCP havuzunun dışına
düşmek için seçilmiştir. Havuzun farklıysa `net/SetStaticIP.sh` başındaki
`STATIC_HOST` değerini değiştir.

Elle yapmak için:

```
./net/SetStaticIP.sh
./net/UnsetStaticIP.sh
```

## DNS

Sağlayıcı engelli alan adları için sahte adresler döndürür ve 53 numaralı porttaki
düz DNS'i engeller; dolayısıyla hâlâ gerçek yanıt veren tek çözümleyici 443
üzerinden DoH'dir. sing-box DoH ile çözer ve 53 portunu hijack eder, ama yalnızca
tünelden geçen DNS'e dokunabilir; yerel modeme giden sorgular tünelden geçmez.
Sistem DNS'ini yerel olmayan bir adres olan 1.1.1.1'e ayarlamak, bu sorguları
tünelden geçmeye ve hijack'e yakalanmaya zorlar. Run.sh bunu yapar ve çıkışta DNS'i
geri koyar.

## Derleme

```
./bin/Build.sh
```

Tek script iki binary'yi de derler. byedpi ve sing-box'ın sabitlenmiş sürümlerini
GitHub'dan klonlar, `bin/` içine `ciadpi` ve `sing-box` olarak derler ve ardından
kaynakları siler. Hangi makinede çalışıyorsa ona göre derler, yani aynı repo hem
Apple Silicon hem Intel'de çalışır.

Bir derleme aracı eksikse kurmadan önce aşama aşama sorar ve reddedersen durur:

- byedpi için C derleyici (Xcode Command Line Tools)
- sing-box için Go (Homebrew üzerinden; yoksa önce Homebrew kurmayı önerir)

Sürümleri değiştirmek için `bin/Build.sh` başındaki `SINGBOX_TAG` ve `BYEDPI_REF`
değerlerini düzenleyip tekrar çalıştır.

## Desync stratejisini değiştirme

`settings.conf` içindeki `CIADPI_ARGS`'ı düzenle. `--fake` ve `--timeout` macOS'te
derleme dışı bırakılmıştır, yani fake paketlere dayanan hiçbir rehber burada işe
yaramaz. İşe yarayanlar: `--split`, `--disorder`, `--oob`, `--disoob`, `--tlsrec`,
`--mod-http`.

Çalışan kurulumu bozmadan bir strateji denemek için onu boş bir portta çalıştır ve
üzerinden istek gönder:

```
./bin/ciadpi --port 1081 <flags> &
curl -sk -o /dev/null -w "%{http_code}\n" -x socks5h://127.0.0.1:1081 https://discord.com
```

`000` dışındaki her şey geçtiği anlamına gelir.

## Loglar

sing-box `logs/box.log`'a `warn` seviyesinde yazar. Run.sh başlangıçta temizler ve
çalışırken 10 MB ile sınırlar, böylece sınırsız büyümez. launchd servisi ayrıca
kendi çıktısını `logs/service.log`'a yazar.
