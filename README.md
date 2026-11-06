# Open NavG — free turn-by-turn navigation for Garmin Venu 2

*Bahasa Indonesia di bawah.*

Open NavG is a free, open-source **Connect IQ data field** that adds route navigation to watches without maps, starting with the **Garmin Venu 2**. It runs inside the normal Run / Bike activity, so all of Garmin's own recording keeps working.

## Why this exists
Many Garmin watches, especially older or lifestyle models like the Venu 2, have **no course navigation at all**, and even cheaper current models only give a line to follow without telling you how to get back. Real turn guidance with maps and rerouting is reserved for watches that cost two to three times more. Open NavG gives a watch you already own:
- turn arrows with distance and one vibration before each turn,
- an off-route alert **with a line showing the way back**,
- a mode for **riding a motorbike** that avoids toll roads,
- route loading that works with an **iPhone**, not only Android.

No new watch, no subscription, no paid app.

- Next-turn arrow with distance and a yellow countdown bar (full = turn now)
- **One** vibration about 20 m before each turn
- Off-route alert with a red line back to the route — explore side streets and always know the way back (explore mode turns the vibration off)
- Simple route line drawn in code on a black screen (light on the AMOLED battery), no map tiles
- **Light street map**: the roads (thicker) and alleys (thin) around your route as plain lines, downloaded once with the route and then fully offline
- 5 saved routes on the watch, choose by tapping the screen — no phone or internet needed once saved
- Running, cycling, or riding a motorbike (avoids toll roads)
- Community routes (GPX) and your own drawings via the **Open NavG Planner**
- English and Bahasa Indonesia, following the watch/phone language

## How it works
1. Phone settings (Connect IQ app → Open NavG → Settings): a destination (coordinates or a Google Maps link) **or** a route code from the Planner, plus a route name.
2. The watch asks a free routing server (Valhalla or OSRM, OpenStreetMap data) for the route through the phone, simplifies it and saves it to a slot. Right after, it downloads the streets around the route from the same Valhalla server (about 1 minute for 10 km, a few minutes for a marathon: keep the phone close with Garmin Connect open).
3. All guidance — turns, off-route, arrival — is computed on the watch from the route's shape, using the watch's own GPS.

### Route codes
| Code | Use | Watch needs internet? |
|---|---|---|
| `NAVG1L:…` exact line | Community GPX routes | No |
| `NAVG1V:…` via points | Your own drawing (e.g. Strava art), snapped to real roads | Once, to fetch |

The **[Planner](https://rozanqaidi.github.io/Open-Navigation-Garmin/planner/)** (`docs/planner/`) turns a GPX file or points tapped on a map into a code you paste into the settings.

## Other watches and other brands
**More Garmin watches.** Only the Venu 2 is built and tested today. Watches with **Connect IQ API 5.0 or newer** (for example Venu 3, Forerunner 165/255) can run the same code: adding one is mostly adding it to `manifest.xml`, checking the layout in the simulator and testing outdoors.

**Older watches (API 3.x, e.g. Venu, Venu Sq, vívoactive 4, Forerunner 245)** have GPS and a compass, but Connect IQ gives their data fields only 32 KB of memory and no direct web access, so they need a slimmer **Lite** build: routes from Planner codes (no web access needed on the watch), turn arrows, vibration and off-route alerts, without the map. **If you own one of these watches, you can help build and test it** — contributions are very welcome.

**Other brands (Huawei, Amazfit, Wear OS, …).** The interesting parts are plain algorithms that can be ported to any watch platform (MIT licence, so commercial or personal forks are fine):

| Part | File | What it does |
|---|---|---|
| Route code | `source/RouteCode.mc`, `source/Polyline.mc` | `NAVG1L:` / `NAVG1V:` + Google polyline (precision 5): a short text that carries a whole route |
| Simplify | `source/Simplifier.mc` | Douglas–Peucker that runs in small steps (for slow watches with a watchdog) |
| Turn detection | `source/Route.mc` | Finds left/right/U-turns from the route's shape alone — no turn list needed from the server |
| Guidance | `source/Navigator.mc` | Snaps GPS to the route, next turn + distance, off-route with hysteresis, rejoin point ahead, arrival |
| Routing | `source/RouteFetcher.mc` | Free Valhalla / OSRM requests (foot, bike, riding a motorbike without tolls) |
| Street map | `source/StreetMap.mc` | Downloads the streets around a route from Valhalla `/expansion` (1 request/s), stores them compactly (2 m int16 grid) and draws them heading-up |
| Planner | `docs/planner/` | Web page (no build, no server) that makes route codes from GPX or a drawn line — reusable as-is by any watch app |
| Screens | `source/OpenNavGView.mc`, `source/Draw.mc` | Everything drawn in code; use as a reference design |

The unit tests in `source/test/` describe the expected behaviour and make good test cases for a port.

## Build
Requirements: Java 17+, [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the Venu 2 device, a developer key.

```bash
scripts/build.sh            # bin/OpenNavG.prg
scripts/build.sh --test     # unit tests; run with: monkeydo bin/OpenNavG-test.prg venu2 -t
```

## Credits
Map data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) ([ODbL](https://opendatacommons.org/licenses/odbl/)) — [report or fix a map error](https://www.openstreetmap.org/fixthemap). Routing and street map by the Valhalla and OSRM servers run by [FOSSGIS](https://fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen) — the app sends at most one request per second and keeps the server configurable in the settings, as their terms ask.

## License
MIT — see [LICENSE](LICENSE).

---

# Open NavG — navigasi belokan gratis untuk Garmin Venu 2

Open NavG adalah **data field Connect IQ** gratis dan open-source yang menambahkan navigasi rute ke jam tanpa peta, dimulai dari **Garmin Venu 2**. Berjalan di dalam aktivitas Run/Bike biasa, jadi semua perekaman bawaan Garmin tetap jalan.

**Kenapa dibuat:** banyak jam Garmin, terutama seri lama atau seri gaya hidup seperti Venu 2, **sama sekali tidak punya navigasi rute**. Seri yang lebih murah pun umumnya hanya memberi garis tanpa petunjuk jalan kembali. Navigasi lengkap dengan peta dan rute ulang hanya ada di jam yang harganya dua sampai tiga kali lipat. Open NavG memberi jam yang sudah Anda punya: panah belokan dengan jarak, satu getar sebelum belok, garis untuk kembali ke rute, mode riding motorbike tanpa tol, dan bisa diisi rute dari **iPhone**. Tanpa beli jam baru dan tanpa langganan.

**Untuk jam lain dan merek lain:** saat ini baru Venu 2 yang dibangun dan diuji. Jam dengan **Connect IQ API 5.0 ke atas** (misalnya Venu 3, Forerunner 165/255) bisa ditambahkan lewat `manifest.xml` lalu diuji. **Jam lama (API 3.x, misalnya Venu, Venu Sq, vívoactive 4, Forerunner 245)** punya GPS dan kompas, tapi data field-nya hanya diberi memori 32 KB dan tidak bisa mengakses internet langsung, jadi perlu versi **Lite** yang lebih ramping: rute dari kode Perencana, panah belokan, getar, dan peringatan keluar jalur, tanpa peta. **Bagi yang memiliki jam-jam ini, Anda dapat ikut berkontribusi** membangun dan mengujinya. Bagian intinya berupa algoritma biasa yang bisa dipindahkan ke platform jam lain seperti Huawei, Amazfit, atau Wear OS: kode rute, penyederhanaan, deteksi belokan dari bentuk rute, navigator keluar/kembali jalur, dan Perencana web. Lisensinya MIT. Detail file ada di bagian *Other watches and other brands* di atas.

- Panah belokan berikutnya + jarak + bar kuning hitung mundur (penuh = belok sekarang)
- **Satu** getar sekitar 20 m sebelum belok
- Peringatan keluar jalur dengan garis merah ke rute — bebas masuk gang tapi selalu tahu jalan balik (mode jelajah mematikan getarnya)
- Garis rute sederhana digambar dengan kode di latar hitam (hemat baterai AMOLED), tanpa peta gambar
- **Peta ringan**: jalan (tebal) dan gang (tipis) di sekitar rute berupa garis, diunduh sekali bersama rute lalu sepenuhnya offline
- 5 rute tersimpan di jam, pilih dengan tap layar — tanpa HP/internet setelah tersimpan
- Lari, sepeda, atau riding motorbike (menghindari tol)
- Rute komunitas (GPX) dan gambar sendiri lewat **[Perencana Open NavG](https://rozanqaidi.github.io/Open-Navigation-Garmin/planner/)**
- Bahasa Inggris dan Indonesia, mengikuti bahasa jam/HP

Cara pakai lengkap ada di [PLAN.md](PLAN.md).
