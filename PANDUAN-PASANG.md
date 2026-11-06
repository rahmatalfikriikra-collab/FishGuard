# FishGuard — Cara pasang & apa yang baru

APK `FishGuard-v6` membaca **tabel DPI asli dari portal KKP** dan **prakiraan cuaca/gelombang asli dari BMKG** langsung di HP, tanpa server perantara. Versi ini memperbaiki satu hal yang paling berbahaya dari versi sebelumnya: **koordinat titik DPI yang dulu dikarang sendiri kini semuanya hasil pembacaan tabel resmi KKP**, dan aplikasi tidak lagi bisa mengaku datanya "hari ini" padahal belum pernah mengunduh apa pun.

## File yang perlu dipasang

| File | Untuk HP apa | Ukuran | SHA256 (8 karakter awal) |
|---|---|---|---|
| `FishGuard-v6-arm64.apk` | **Hampir semua HP Android sekarang** (2018 ke atas, 64-bit) | 21,2 MB | `6EAB8431` |
| `FishGuard-v6-arm32.apk` | HP lama / murah 32-bit (2015–2018) | 19,2 MB | `A91F4198` |

Coba yang **arm64** dulu. Kalau saat dipasang muncul pesan "aplikasi tidak kompatibel" atau "App not installed", pakai yang **arm32**.

Keduanya bisa dipasang berdampingan dengan aplikasi FishGuard lama (nama paketnya berbeda), jadi Anda bisa membandingkan sebelum menghapus yang lama.

## Langkah pemasangan

1. Kirim file APK ke HP (WhatsApp ke diri sendiri, Google Drive, kabel USB, atau download langsung di HP).
2. Buka file APK-nya dari aplikasi **Files** / **Pengelola File**.
3. Android akan bertanya soal izin. Pilih **Setelan** (Settings) → aktifkan **Izinkan dari sumber ini** (Install unknown apps) untuk aplikasi yang Anda pakai membuka APK tersebut.
4. Kembali, lalu pilih **Instal**.
5. Kalau muncul peringatan **Play Protect** ("Aplikasi tidak dikenal"), pilih **Instal tetap** (Install anyway). Ini wajar untuk APK yang belum lewat Play Store.
6. Buka aplikasi **FishGuard**.
7. Saat pertama dibuka, izinkan **lokasi** dan **notifikasi**. Notifikasi dipakai untuk pengingat subuh dan kabar data baru.
8. **Di darat, sebelum berangkat:** tekan **Unduh** pada kartu data di Beranda, atau **Siapkan Data** di menu Siap Melaut. Tunggu sampai muncul "Data hari ini siap".

Syarat minimum: Android 7.0 (versi 24). Target: Android 16.

## Yang baru di v6 — dan alasannya

### 1. Semua titik DPI sekarang benar-benar dari tabel KKP

Versi sebelumnya membawa koordinat DPI yang **diketik tangan** sebagai contoh. Salah satunya jatuh di tengah kota Makassar — di darat, di atas pemukiman. Itu bukan kesalahan pembacaan; angkanya memang tidak pernah berasal dari KKP.

Sekarang seluruh paket data adalah **hasil OCR tabel DPI resmi KKP untuk 11 WPP**, tanggal 4 November 2026: 571 (25 titik) dan 572–718 (50 titik masing-masing), total **525 titik**. Nol baris gagal dibaca. Setiap titik menyimpan alamat gambar tabel aslinya, dan tombol **Lihat Tabel Asli di Portal KKP** membuka gambar itu di browser.

### 2. Titik yang jatuh di darat ditandai, bukan disembunyikan

Dari 525 titik, **satu** memang dicetak KKP di darat: WPP 573 nomor 40, di pesisir Lombok selatan (`116°27'57" BT 8°43'35" LS`). Itu koordinat terbitan KKP, apa adanya.

FishGuard tidak menghapusnya — menghapus data resmi berarti menutupi fakta. Tetapi:
- Di peta titik itu digambar **berlubang dan dicoret**, bukan lingkaran penuh.
- Di daftar titik muncul label **"di darat"**.
- Saat dibuka, lembar detailnya menampilkan peringatan di paling atas, dan tombolnya berubah menjadi **"Tetap Berangkat ke Sini"** — bukan "Mulai Perjalanan ke Sini".
- Titik itu **tidak pernah** muncul dalam rekomendasi titik terdekat, dan tidak pernah dipakai untuk menebak zona WPP Anda.

Pemeriksaannya memakai bitmap darat/laut 0,015° (~1,7 km) yang ikut terpasang, dibuat dari peta garis pantai Natural Earth — jadi bukan tebakan, dan jalan tanpa internet.

### 3. "Wajib unduh" — aplikasi tidak bisa lagi mengaku data baru

Ini yang paling penting untuk keselamatan. Dulu tombol **Siapkan Data** hanya menyiapkan paket bawaan, lalu mencatat waktu sekarang seolah-olah baru diunduh. Akibatnya aplikasi bisa menampilkan **"Data per 11.40, hari ini"** padahal tidak ada satu byte pun yang diunduh hari itu — dan paket bawaan itu dibaca di komputer saat APK dibuat, bisa berminggu-minggu sebelumnya.

Sekarang:
- Waktu "diunduh" **hanya** dicatat oleh pengunduhan yang benar-benar memakai jaringan.
- Kalau tabel KKP atau prakiraan BMKG belum diunduh **hari ini** (menurut jam WITA, jamnya nelayan — bukan jam HP), tombol mulai berlayar memunculkan kotak **"Unduh data dulu"** berisi apa yang kurang.
- Berlayar **tetap diizinkan** — ada tombol **Tetap berangkat**. Aplikasi tidak boleh menjebak nelayan yang sudah di laut atau yang sinyalnya mati. Yang dicegah adalah berlayar sambil *mengira* datanya baru.
- Kartu di Beranda menampilkan **"Wajib unduh"** dan tombolnya berubah dari "Perbarui" menjadi "Unduh".

### 4. Data menyusul terbitnya KKP dan BMKG

- Saat aplikasi dibuka dan setiap kali kembali ke layar depan, FishGuard mengecek apakah KKP sudah menerbitkan tabel baru dan apakah BMKG memperbarui prakiraan. Pemeriksaannya murah — hanya menanyakan tanggal terbaru — dan tidak mengunduh apa pun kalau tidak ada yang baru.
- Selama aplikasi terbuka, pengecekan itu berjalan lagi **tiap 15 menit**.
- Sinkron latar belakang tiap 6 jam tetap ada (bisa dimatikan di **Profil → Sinkron Otomatis**), dan hasilnya dihitung sebagai unduhan hari itu juga — jadi kalau HP sudah mengunduh sendiri, aplikasi tidak akan meminta Anda mengunduh lagi.

### 5. Prakiraan cuaca contoh sudah dibuang

Versi lama membawa `weather.json` contoh. Prakiraan yang ikut dipaketkan di dalam APK **salah sejak APK itu selesai dibangun**, tetapi tetap menggambar tabel 48 jam dan warna status laut — persis jenis kesalahan yang tidak terlihat. Sekarang prakiraan cuaca **hanya** berasal dari BMKG langsung, dan cache-nya hanya dipakai ulang selama jam-jamnya masih di depan.

## Yang sudah ada sejak v5

**Tombol "Siapkan Data" benar-benar mengunduh**, berurutan: prakiraan BMKG → tabel DPI KKP → pemeriksaan GPS/baterai. Nama tahapnya muncul di tombol, jadi kalau sinyal putus Anda tahu berhenti di mana. Yang sudah terunduh tetap dipakai; menekan lagi melanjutkan, bukan mengulang.

**Spot tangkapan sendiri.** Menu **Peta → Spot Saya**: tombol **Tandai Spot Ini** menyimpan posisi Anda sekarang beserta nama dan catatan. Spot pribadi digambar sebagai **wajik hijau**, sedangkan titik DPI tetap **lingkaran bernomor**. Semuanya tersimpan di HP.

**Peta offline diperbarui sendiri** saat salinan sudah lebih dari 24 jam.

**Antrean data yang lebih jelas.** **Profil → Data Menunggu Terkirim** menampilkan status, jumlah catatan, kesalahan terakhir, dan tombol **Coba Kirim Sekarang**. Server FishGuard belum ada, jadi hasilnya tetap "menunggu" — tetapi catatan Anda tidak pernah hilang dan aplikasi tidak berpura-pura sudah terkirim.

## Yang sudah ada sejak v4

**Sinkron otomatis di latar belakang** tiap 6 jam walaupun aplikasi ditutup (Profil → Sinkron Otomatis).

**Pengingat subuh** — notifikasi harian sebelum berangkat, jam bisa diatur (03.00–06.30), di **Profil → Pengingat Subuh**.

**Kalibrasi solar** — isi kolom "Solar terpakai" di **Profil → Riwayat Pelayaran**, dan estimasi berikutnya menyesuaikan kapal Anda.

**Peta jejak & bagikan riwayat** — setiap pelayaran menyimpan jejaknya; tombol **Bagikan Riwayat** mengirim catatan sebagai teks ke WhatsApp/SMS.

**Peringatan cuaca saat melaut** — kalau status perairan berubah menjadi **TIDAK LAYAK** sementara Anda mencatat pelayaran, muncul peringatan lengkap dengan tombol **Pandu pulang**.

**Peta DPI langsung dari KKP.** Menu **Peta** → **Ambil data DPI hari ini**. Aplikasi mencari tanggal terbaru yang tabelnya sudah terbit (KKP biasanya menerbitkan sehari setelahnya), mengunduh gambarnya, lalu membacanya sendiri di HP.

Pembacaan tabelnya **ditulis penuh dalam Dart** — tidak memakai Google ML Kit. APK jadi jauh lebih kecil (86,9 MB → 21,2 MB), jalan di semua HP Android tanpa Google Play Services, dan hasilnya lebih tepat: deteksi grid dan pencocokan bentuk angka, bukan tebak-tebakan teks.

**Cuaca & gelombang langsung dari BMKG** sesuai posisi GPS Anda, dengan 375 perairan yang bisa dipilih kalau GPS belum dapat. Beranda menampilkan prakiraan per 3 jam untuk 24 jam ke depan.

**Peringatan dini BMKG** — status kuning/oranye/merah berasal dari buletin resmi BMKG hari itu.

**Rekomendasi AI** memakai Claude API kalau Anda mengisi kunci di **Profil → Asisten AI**. Tanpa kunci, saran tetap muncul dari aturan lokal — selalu ada jawaban walau offline.

## Yang belum nyata (dan dikatakan apa adanya di aplikasi)

Beberapa hal di PRD bergantung pada server yang belum ada. FishGuard tidak memalsukannya:

- **OTP SMS/WhatsApp** — belum ada gateway OTP. Tombol "Kirim Kode OTP" menyimpan nomor sebagai identitas di HP; tidak ada SMS yang benar-benar dikirim, dan aplikasi mengatakannya.
- **SOS ke tim SAR** — FishGuard membuka aplikasi SMS berisi koordinat untuk kontak darurat Anda, lalu Anda menekan kirim di sana. Aplikasi tidak bisa memastikan SMS terkirim, jadi kalau aplikasi SMS gagal dibuka, FishGuard mencoba lagi tiap 2 menit sampai 10 kali dan menampilkan koordinat besar di layar untuk dibacakan lewat radio.
- **Kirim data ke server** — belum ada server. Antrean disimpan di HP.

## Data yang ikut terpasang

Hanya **data asli**: 11 berkas `dpi_<wpp>.json` hasil OCR tabel KKP tanggal 4 November 2026, dan `land_mask.bin` untuk pemeriksaan darat/laut. Tidak ada prakiraan cuaca contoh.

Paket ini tetap ikut terpasang supaya aplikasi tidak kosong saat pertama dibuka atau saat tidak ada sinyal — tetapi aplikasi **tidak** menganggapnya sebagai data hari ini. Untuk berlayar, tetap harus unduh.

## Kalau ada masalah

**"Tabel belum tersedia"** — KKP belum menerbitkan tabel untuk tanggal itu. Aplikasi otomatis mundur sampai 7 hari ke belakang. KKP biasanya menerbitkan sekitar pukul 10–11 pagi WITA; kalau dicoba sebelum itu, tabel hari ini memang belum ada. Coba lagi nanti atau pilih zona WPP lain.

**"Tidak bisa menghubungi portal KKP"** — periksa kuota/sinyal. Portal KKP kadang lambat; coba lagi beberapa saat.

**"Gridnya tidak dikenali"** — format gambar tabel KKP berubah. Kirimkan tangkapan layar ke pengembang.

**Muncul "Unduh data dulu" padahal sudah menekan Siapkan Data** — berarti unduhannya belum berhasil, bukan belum ditekan. Periksa pesan terakhir di tombol Siapkan Data dan sinyal Anda. Kalau memang tidak ada sinyal, pilih **Tetap berangkat** — data yang tersimpan tetap bisa dipakai, hanya saja bukan data hari ini.

**Lokasi tidak muncul** — nyalakan GPS dan izinkan akses lokasi untuk FishGuard (Setelan → Aplikasi → FishGuard → Izin → Lokasi).

**Pengingat subuh tidak berbunyi** — Android kadang membatasi notifikasi aplikasi yang jarang dibuka. Buka Setelan → Aplikasi → FishGuard → Baterai, pilih **Tidak dibatasi** (Unrestricted). Pengingatnya memakai alarm tidak-eksak, jadi bisa bergeser beberapa menit.

**"Siapkan Data" berhenti di satu tahap** — teks di tombol menunjukkan tahap mana. Yang sudah terunduh tetap tersimpan; coba lagi saat sinyal membaik. Kalau DPI yang gagal, cuaca tetap diperbarui, dan sebaliknya.

**Spot saya hilang** — spot hanya tersimpan di HP ini. Menghapus aplikasi, membersihkan data, atau pindah HP akan menghapusnya. Belum ada cadangan karena belum ada server.

## Membangun ulang dari kode

```powershell
cd C:\Users\ACER\fishguard_app
$env:JAVA_HOME="C:\Users\ACER\jdk\jdk-17.0.13+11"
$env:ANDROID_HOME="C:\Users\ACER\fishguard-setup\android-sdk"
C:\Users\ACER\flutter-sdk\flutter\bin\flutter.bat build apk --release --split-per-abi
```

Membuat ulang seluruh aset data dari tabel KKP asli (butuh internet; mengunduh gambar tabel lalu membacanya):

```powershell
C:\Users\ACER\flutter-sdk\flutter\bin\flutter.bat pub run tool\real\build_real_data.dart
```

Uji otomatis (termasuk uji langsung ke server KKP dan BMKG):

```powershell
C:\Users\ACER\flutter-sdk\flutter\bin\flutter.bat test
```

Tanpa koneksi internet, lewati uji jaringan:

```powershell
C:\Users\ACER\flutter-sdk\flutter\bin\flutter.bat test --exclude-tags live
```
