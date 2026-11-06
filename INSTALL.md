# Panduan Instalasi FishGuard

Aplikasi Flutter untuk nelayan: status laut, peta titik tangkap (DPI), navigasi,
hitung BBM, SOS, dan asisten AI. Seluruh teks antarmuka berbahasa Indonesia.

---

## 1. Bagian cepat — pasang APK di HP Android

### 1.1 Salin APK ke HP

File APK ada di folder ini:

```
C:\Users\ACER\fishguard_app\build\app\outputs\flutter-apk\
```

Ada dua pilihan — **pakai yang sesuai jenis HP Anda**:

| Berkas | Ukuran | Untuk |
|---|---|---|
| `app-arm64-v8a-release.apk` | 30,9 MB | **Hampir semua HP Android keluaran 2017 ke atas** — pilih ini bila ragu |
| `app-armeabi-v7a-release.apk` | 24,4 MB | HP Android lama (32-bit) |
| `app-release.apk` | 82,8 MB | Satu berkas untuk semua jenis HP, termasuk emulator |

Kalau tidak yakin HP Anda 64-bit atau tidak: hampir semua HP yang dijual sejak
2017 adalah 64-bit, jadi ambil `app-arm64-v8a-release.apk`. Kalau saat dipasang
muncul "APK tidak kompatibel dengan HP ini", pakai `app-armeabi-v7a-release.apk`
atau `app-release.apk`.

Pilih salah satu cara memindahkannya:

- **Kabel USB** — colok HP ke komputer, pilih mode "Transfer file / MTP",
  buka penyimpanan HP, seret berkas APK ke folder `Download`.
- **Google Drive / WhatsApp** — kirim file ke diri sendiri, lalu buka di HP.
- **adb** (bila USB debugging aktif):

```bash
adb install -r "C:\Users\ACER\fishguard_app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

### 1.2 Izinkan pemasangan dari sumber tak dikenal

APK ini tidak lewat Play Store, jadi Android akan meminta izin sekali.

- **Android 8 ke atas** — saat membuka APK muncul "Untuk keamanan, HP Anda
  diblokir dari memasang aplikasi tak dikenal". Ketuk **Setelan**, lalu aktifkan
  **Izinkan dari sumber ini** untuk aplikasi yang membuka file (File Manager,
  Chrome, WhatsApp).
- **Android 7 ke bawah** — Setelan → Keamanan → **Sumber tidak dikenal** → aktifkan.

### 1.3 Pasang dan buka

Ketuk berkas APK yang sudah disalin → **Pasang** → **Buka**. Ikon **FishGuard**
muncul di laci aplikasi.

> **Catatan tanda tangan.** APK ini masih ditandatangani dengan kunci debug
> (`android/app/build.gradle.kts` baris 36), cukup untuk dipasang manual dan
> dibagikan ke beberapa HP. Untuk Play Store atau pembaruan yang bisa
> menimpa versi lama, buat keystore rilis sendiri dan ganti `signingConfig`
> sebelum build.

### 1.4 Izin yang diminta saat pertama dibuka

| Izin | Dipakai untuk | Bila ditolak |
|---|---|---|
| Lokasi | Menaruh kapal di peta, kompas, jarak ke titik tangkap | Aplikasi memakai titik pelabuhan default (Barombong) |
| Internet | Cuaca, data DPI, asisten AI | Data offline tetap jalan, AI nonaktif |

Aplikasi tetap bisa dipakai tanpa kedua izin di atas, hanya kurang akurat.

---

## 2. Bagian cepat — iPhone

**APK Android tidak bisa dipasang di iPhone.** iOS hanya menerima aplikasi yang
ditandatangani Apple. Tiga jalur yang tersedia:

| Jalur | Syarat | Catatan |
|---|---|---|
| **TestFlight / App Store** | Akun Apple Developer (USD 99/tahun) + Mac | Jalur resmi untuk pengguna umum |
| **Xcode langsung ke HP** | Mac + Xcode + akun Apple ID gratis | Aplikasi kedaluwarsa setelah 7 hari, harus dipasang ulang |
| **Simulator iOS** | Mac + Xcode | Hanya untuk melihat tampilan, bukan untuk dibawa melaut |

Sumber Flutter untuk iOS sudah ada di folder `ios/`, tetapi **build iOS harus
dijalankan di macOS** — Xcode tidak tersedia di Windows. Bila nanti ada Mac:

```bash
flutter build ipa --release
```

Hasilnya diunggah ke App Store Connect lewat Xcode Organizer atau `xcrun altool`.

---

## 3. Menjalankan dari kode sumber (untuk pengembangan)

### 3.1 Perkakas yang sudah terpasang di komputer ini

| Perkakas | Lokasi |
|---|---|
| Flutter SDK 3.47.9 | `C:\Users\ACER\flutter-sdk\flutter` |
| JDK 17 | `C:\Users\ACER\fishguard-setup\jdk\jdk-17.0.20.1+1` |
| Android SDK | `C:\Users\ACER\fishguard-setup\android-sdk` |
| Proyek aplikasi | `C:\Users\ACER\fishguard_app` |

### 3.2 Variabel lingkungan

Buka PowerShell baru, lalu jalankan tiga baris ini sekali per sesi:

```bash
$env:JAVA_HOME='C:\Users\ACER\fishguard-setup\jdk\jdk-17.0.20.1+1'
```

```bash
$env:ANDROID_HOME='C:\Users\ACER\fishguard-setup\android-sdk'
```

```bash
$env:PATH="C:\Users\ACER\flutter-sdk\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
```

### 3.3 Perintah yang sering dipakai

```bash
cd C:\Users\ACER\fishguard_app
```

```bash
flutter run
```

`flutter run` memasang aplikasi ke HP yang tersambung lewat USB (atau emulator)
dengan mode debug dan hot reload — setiap simpan file, tampilan langsung berubah.

```bash
flutter build apk --release --split-per-abi
```

Menghasilkan tiga APK rilis di `build\app\outputs\flutter-apk\` — satu per jenis
prosesor, masing-masing jauh lebih kecil daripada satu APK gabungan. Tanpa
`--split-per-abi`, hasilnya satu berkas `app-release.apk` berisi ketiga jenis
sekaligus.

```bash
flutter analyze
```

Memeriksa kesalahan kode.

```bash
flutter test
```

Menjalankan seluruh uji. Uji yang memanggil server sungguhan diberi tanda
`live` dan tidak ikut berjalan secara bawaan; jalankan terpisah dengan:

```bash
flutter test --tags live test/live_integration_test.dart
```

> **Catatan Gradle.** Jangan menjalankan dua build sekaligus. Bila muncul
> `Timeout waiting to lock build logic queue`, tutup semua proses `java` lalu
> hapus folder `android\.gradle` dan `build`, kemudian build ulang.
>
> Bila `flutter build apk` berhenti dengan `No Android SDK found`, set dulu
> variabel lingkungannya di jendela PowerShell yang sama:
>
> ```bash
> $env:ANDROID_HOME = "C:\Users\ACER\fishguard-setup\android-sdk"
> ```

### 3.4 Bila `flutter` tidak dikenali

Pastikan baris `$env:PATH` di 3.2 sudah dijalankan di jendela PowerShell yang
sama. Untuk permanen, tambahkan lewat System Properties → Environment Variables.

---

## 4. Menghubungkan asisten AI

Fitur "Saran AI" di Beranda memakai dua lapis:

1. **Lokal (bawaan)** — saran disusun dari data cuaca, gelombang, dan jarak titik
   tangkap yang ada di aplikasi. Selalu aktif, tanpa internet, tanpa biaya.
2. **AI sungguhan (opsional)** — bila kunci API diisi, FishGuard mengirim ringkasan
   kondisi hari itu ke Claude dan menampilkan jawaban yang lebih luwes.

### 4.1 Mengisi kunci API

1. Buka tab **Profil** → bagian **Asisten AI**.
2. Tempel kunci API Anthropic (berawalan `sk-ant-...`) di kolom
   **Kunci API Anthropic**.
3. Pilih model pada dropdown **Model** (bawaan: `claude-opus-5-5`).
4. Pastikan sakelar **Pakai AI** menyala.
5. Kembali ke **Beranda**, tarik ke bawah untuk memuat ulang saran.

Kunci disimpan di penyimpanan lokal HP (`shared_preferences`) dan hanya dikirim ke
`api.anthropic.com`. Bila kuota habis atau kunci salah, aplikasi otomatis kembali
ke saran lokal dan menampilkan pesan kesalahan singkat.

> **Penting.** Jangan memakai kunci API pribadi di HP yang dipakai bersama, dan
> jangan menaruh kunci di dalam kode sumber. Untuk pemakaian bersama, kunci
> sebaiknya diletakkan di server perantara, bukan di aplikasi.

---

## 4A. Mencatat hasil tangkapan

Ada tiga jalan masuk:

- **Beranda** → kartu **Hasil Tangkapan** (menampilkan total hari ini) atau
  menu cepat **Catat Ikan**.
- **Navigasi** → tombol **Catat Hasil Tangkapan**. Bila tujuan DPI sudah
  dipilih, tangkapan otomatis terikat ke titik itu.
- **Profil** → **Hasil Tangkapan**, untuk melihat dan menghapus catatan lama.

Isi formulir: jenis ikan, berat (kg), jumlah ekor, catatan (opsional), lalu
pilih lokasi — titik DPI tujuan atau posisi kapal saat itu.

> Catatan disimpan di HP (`shared_preferences`) dan belum diunggah ke server.
> Setelah dua catatan atau lebih di titik yang sama, aplikasi menandai titik
> itu sebagai yang paling produktif. Data DPI tetap prakiraan, bukan jaminan.

---

## 5. Data yang dibawa di dalam aplikasi

| Berkas | Isi | Sumber |
|---|---|---|
| `assets/data/dpi_<wpp>.json` | Titik tangkap untuk 11 WPP (571, 572, 573, 711–718) | Hasil OCR tabel DPI resmi KKP |
| `assets/data/land_mask.bin` | Bitmap darat/laut 0,015° (~1,7 km) | Natural Earth 1:10m + 1:50m |

Setiap titik dibaca langsung dari `tabel_dpi_<wpp>_<tanggal>.png` di portal
KKP, apa adanya — tidak ada koordinat yang dikarang. Satu titik WPP 573 memang
KKP cetak di daratan (pesisir Lombok selatan); titik itu tetap ditampilkan
tetapi digambar berlubang dan dicoret, dan tidak pernah dijadikan tujuan
rekomendasi.

Prakiraan cuaca **tidak dibundel**: cuaca selalu diambil langsung dari BMKG
saat aplikasi dipakai, lalu di-cache hanya selama jam-jamnya masih di depan.

Data ini dibaca tanpa internet. Untuk membuat ulang dari tabel KKP:

```bash
flutter pub run tool\real\build_real_data.dart
```

**Penting:** paket bawaan ini dibaca saat build, bukan saat berlayar. Aplikasi
karena itu mewajibkan unduhan hari itu juga sebelum berangkat (lihat
`README.md`, bagian "Wajib unduh sebelum melaut").

---

## 6. Kalau ada masalah

| Gejala | Penyebab dan solusi |
|---|---|
| "Aplikasi tidak terpasang" | APK lama dengan tanda tangan berbeda. Hapus FishGuard lama, pasang lagi |
| "Aplikasi diblokir" | Izin sumber tak dikenal belum aktif — lihat 1.2 |
| Peta kosong | Data aset belum terbaca. Jalankan `flutter clean` lalu build ulang |
| Saran AI selalu lokal | Kunci API kosong atau sakelar **Pakai AI** mati — lihat 4.1 |
| Posisi kapal tidak muncul | Izin lokasi ditolak atau GPS belum dapat sinyal. Buka di luar ruangan |
| Build gagal `lock build logic queue` | Proses Gradle tertinggal — lihat catatan di 3.3 |

---

## 7. Sambungan ke server resmi

Aplikasi ini **sudah** mengambil data langsung dari server resmi, tanpa backend
dan tanpa kunci API. Data contoh di dalam paket hanya dipakai bila jaringan
tidak ada.

**BMKG** (`https://maritim.bmkg.go.id/marine2026-data/`)

- Area perairan dipilih otomatis dari posisi GPS lewat poligon
  `meta/wilmetos.min.geojson`; bila posisi di luar semua poligon, dipakai area
  terdekat.
- Prakiraan gelombang dan angin per jam dari `perairan/{ID}.json`.
- Peringatan dini resmi dari `warning/warnings.json`. Nama perairan di berkas
  itu sama persis dengan nama di `meta/area_province.json`, jadi dipetakan
  langsung. Level `sedang` menaikkan status ke WASPADA; `tinggi`,
  `sangat_tinggi`, dan `ekstrem` ke TIDAK LAYAK.

**KKP PDPI** (portal KKP)

- Tabel DPI diunduh sebagai PNG lalu dibaca dengan OCR murni Dart
  (table_ocr.dart + aset glyph templates.json) menjadi koordinat, untuk 11
  zona WPP. Tidak perlu ML Kit dan jalan di semua platform, termasuk browser.
- KKP tidak menerbitkan tabel setiap hari. Bila tanggal yang dipilih belum ada,
  aplikasi otomatis mundur ke tanggal terakhir yang tersedia (maksimal 7 hari)
  dan memberi tahu tanggal mana yang dipakai.

Masih perlu untuk versi produksi:

- Login OTP lewat SMS
- Peta laut offline (PMTiles) untuk area yang lebih luas
- Unggah otomatis catatan tangkapan (antrian PREP-9 belum ada)
- Integrasi resmi dengan tim SAR untuk SOS
- Build iOS (lihat bagian 5)
