# Open NavG — free turn-by-turn navigation for Garmin Venu 2

*Bahasa Indonesia di bawah.*

Open NavG is a free, open-source **Connect IQ data field** that adds route navigation to watches without maps, starting with the **Garmin Venu 2**. It runs inside the normal Run / Bike activity, so all of Garmin's own recording keeps working.

- Next-turn arrow with distance and a yellow countdown bar (full = turn now)
- **One** vibration about 20 m before each turn
- Off-route alert with a red line back to the route — explore side streets and always know the way back (explore mode turns the vibration off)
- Simple route line drawn in code on a black screen (light on the AMOLED battery), no map tiles
- 5 saved routes on the watch, choose by tapping the screen — no phone or internet needed once saved
- Run, bike, or motorbike (avoids toll roads)
- Community routes (GPX) and your own drawings via the **Open NavG Planner**
- English and Bahasa Indonesia, following the watch/phone language

## How it works
1. Phone settings (Connect IQ app → Open NavG → Settings): a destination (coordinates or a Google Maps link) **or** a route code from the Planner, plus a route name.
2. The watch asks a free routing server (Valhalla or OSRM, OpenStreetMap data) for the route through the phone, simplifies it and saves it to a slot.
3. All guidance — turns, off-route, arrival — is computed on the watch from the route's shape, using the watch's own GPS.

### Route codes
| Code | Use | Watch needs internet? |
|---|---|---|
| `NAVG1L:…` exact line | Community GPX routes | No |
| `NAVG1V:…` via points | Your own drawing (e.g. Strava art), snapped to real roads | Once, to fetch |

The **[Planner](https://rozanqaidi.github.io/Open-Navigation-Garmin/planner/)** (`docs/planner/`) turns a GPX file or points tapped on a map into a code you paste into the settings.

## Build
Requirements: Java 17+, [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the Venu 2 device, a developer key.

```bash
scripts/build.sh            # bin/OpenNavG.prg
scripts/build.sh --test     # unit tests; run with: monkeydo bin/OpenNavG-test.prg venu2 -t
```

## Credits
Map data © OpenStreetMap contributors. Routing by Valhalla and OSRM servers run by FOSSGIS — please respect their fair-use policies (the server is configurable in the settings).

## License
MIT — see [LICENSE](LICENSE).

---

# Open NavG — navigasi belokan gratis untuk Garmin Venu 2

Open NavG adalah **data field Connect IQ** gratis dan open-source yang menambahkan navigasi rute ke jam tanpa peta, dimulai dari **Garmin Venu 2**. Berjalan di dalam aktivitas Run/Bike biasa, jadi semua perekaman bawaan Garmin tetap jalan.

- Panah belokan berikutnya + jarak + bar kuning hitung mundur (penuh = belok sekarang)
- **Satu** getar sekitar 20 m sebelum belok
- Peringatan keluar jalur dengan garis merah ke rute — bebas masuk gang tapi selalu tahu jalan balik (mode jelajah mematikan getarnya)
- Garis rute sederhana digambar dengan kode di latar hitam (hemat baterai AMOLED), tanpa peta
- 5 rute tersimpan di jam, pilih dengan tap layar — tanpa HP/internet setelah tersimpan
- Lari, sepeda, atau motor (menghindari tol)
- Rute komunitas (GPX) dan gambar sendiri lewat **[Perencana Open NavG](https://rozanqaidi.github.io/Open-Navigation-Garmin/planner/)**
- Bahasa Inggris dan Indonesia, mengikuti bahasa jam/HP

Cara pakai lengkap ada di [PLAN.md](PLAN.md).
