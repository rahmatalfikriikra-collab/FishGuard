# FishGuard â€” Aplikasi Navigasi Nelayan

Aplikasi Flutter untuk nelayan Indonesia: status laut, peta titik tangkap (DPI),
navigasi dan kompas, hitung BBM, SOS, dan asisten AI. Seluruh antarmuka berbahasa
Indonesia.

Dibangun dari PRD FishGuard, kode MVP Flutter yang dilampirkan, dan prototipe web
<https://prototipeindonesia.github.io/fishguard-app/>.

## Menjalankan

```bash
flutter pub get
flutter run
```

Panduan pemasangan APK dan pengaturan kunci AI ada di [INSTALL.md](INSTALL.md).

## Struktur

```
lib/
  main.dart                  titik masuk, splash, tema terang/gelap
  models/models.dart         SeaStatus, ForecastHour, WeatherArea, DpiPoint, formatter
  services/
    app_state.dart           keadaan pusat: profil, kontak, DPI, cuaca, perjalanan, API key
    local_data.dart          pembacaan aset + konfigurasi peta
    fuel_calculator.dart     rumus BBM + cadangan 10% + cek cukup pulang
    claude_service.dart      klien Messages API + penyusun saran lokal
    bmkg_service.dart        area perairan (poligon), prakiraan, peringatan dini
    kkp_pdpi_service.dart    unduh tabel DPI resmi per WPP dan tanggal
    dpi_table_parser.dart    baca tabel DPI (Bujur/Lintang D-M-S) jadi koordinat
    table_ocr.dart             pembaca tabel DPI murni Dart (grid + glyph)
  screens/
    onboarding_screen.dart   perkenalan tiga halaman
    login_screen.dart        nomor HP / mode tamu
    root_shell.dart          header, lima tab, tombol SOS
    beranda_screen.dart      status laut, cuaca, kesiapan, menu cepat, saran AI
    peta_screen.dart         peta skematik, daftar DPI, rute ke titik
    navigasi_screen.dart     kompas, jarak, BBM sisa, rekam perjalanan, catat tangkapan
    fuel_screen.dart         kalkulator BBM
    profil_screen.dart       profil kapal, kontak darurat, asisten AI, tema
    catch_log_screen.dart    catatan hasil tangkapan per titik DPI
  widgets/
    common.dart              kartu, tombol, badge, notice, sheet
    sea_map.dart             peta laut CustomPainter
    siap_melaut.dart         daftar periksa sebelum berangkat
    catch_sheet.dart         formulir catat tangkapan + baris riwayat
    dpi_fetch_sheet.dart     pilih zona WPP + tanggal, progres OCR
    sos_sheet.dart           lembar SOS
assets/data/                 dpi_<wpp>.json (11 WPP), land_mask.bin
tool/real/build_real_data.dart  pembuat ulang aset dari tabel KKP asli
tool/real/                   tabel KKP yang diunduh + poligon benua Natural Earth
tool/serve_web.ps1           server statis untuk pratinjau build web
test/                        parser tabel DPI, peringatan BMKG, integrasi langsung
```

## Status implementasi

Sudah jalan: beranda, peta dan daftar DPI, navigasi dan kompas, kalkulator BBM,
profil dan pengaturan, SOS, onboarding, login lokal, tema gelap, saran AI
(lokal + Claude bila kunci diisi), catatan hasil tangkapan per titik DPI, data
offline.

**Data langsung dari sumber resmi (tanpa backend, tanpa kunci API):**

- **BMKG** â€” `https://maritim.bmkg.go.id/marine2026-data/`. Area perairan
  dipilih otomatis dari posisi GPS lewat poligon `wilmetos.min.geojson`,
  prakiraan gelombang/angin per jam dari `perairan/{ID}.json`, dan peringatan
  dini resmi dari `warning/warnings.json` (dipetakan per nama perairan; level
  `sedang` menaikkan status ke WASPADA, `tinggi` ke atas ke TIDAK LAYAK).
- **KKP PDPI** â€” tabel DPI diunduh dari portal KKP lalu dibaca dengan OCR
  murni Dart (table_ocr.dart + aset templates.json) menjadi koordinat, jalan di semua platform termasuk browser. Karena KKP tidak menerbitkan tabel setiap hari, aplikasi otomatis mundur ke tanggal terakhir yang tersedia (maks. 7 hari).

Belum tersambung: OTP SMS, peta laut offline PMTiles, unggah otomatis catatan
tangkapan ke server, kalibrasi BBM pribadi, integrasi SAR, build iOS.

## Data

Aset di `assets/data/` adalah **hasil OCR tabel KKP yang benar-benar terbit**,
bukan angka karangan. Setiap `dpi_<wpp>.json` berasal dari
`tabel_dpi_<wpp>_<tanggal>.png` di portal KKP; koordinatnya dibaca dari gambar
apa adanya, termasuk satu titik WPP 573 yang KKP sendiri cetak di daratan
(pesisir Lombok selatan). Titik itu tetap ditampilkan — datanya milik KKP —
tetapi digambar berlubang dan dicoret, serta tidak pernah dijadikan tujuan
rekomendasi.

`land_mask.bin` adalah bitmap darat/laut 0.015° (~1,7 km) yang dipakai untuk
memutuskan apakah sebuah titik jatuh di darat. Bitmap ini dibuat dari poligon
Natural Earth 1:10m dan 1:50m.

Untuk membuat ulang seluruh aset dari tabel KKP:

```bash
flutter pub run tool\real\build_real_data.dart
```

Prakiraan cuaca **tidak** dibundel. Data cuaca hanya berasal dari BMKG secara
langsung dan disimpan sebagai cache yang dipakai ulang hanya selama jam-jamnya
masih di depan.

### Wajib unduh sebelum melaut

Paket data di dalam APK dibaca di komputer saat build, jadi bisa sudah
berumur berminggu-minggu saat dipakai. Karena itu aplikasi tidak menganggap
paket bawaan sebagai "data hari ini":

- `fetchDpi()` dan `fetchWeatherForPosition()` mencatat waktu unduhan yang
  sebenarnya; `markSynced()` (yang tidak memakai jaringan) tidak.
- Tombol mulai berlayar menampilkan gerbang "Unduh data dulu" bila tabel KKP
  atau prakiraan BMKG belum diunduh **hari ini** (WITA). Berlayar tetap
  diizinkan — aplikasi tidak boleh menjebak nelayan yang sudah di laut — tetapi
  tidak boleh berlayar sambil mengira datanya baru.
- Saat aplikasi dibuka atau kembali ke depan, `autoRefresh()` mengecek KKP dan
  BMKG; pengunduhan hanya terjadi bila memang ada tabel/prakiraan baru, dan
  berjalan lagi tiap 15 menit selama aplikasi terbuka.
