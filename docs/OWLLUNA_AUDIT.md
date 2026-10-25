# Audit OwlLuna (riset kompetitor open source)

Tanggal audit: 2026-10-25 · Repo: https://github.com/owaisazmal/OwlLuna (lisensi MIT) · Commit yang dibaca: `fbdde1d` (24 Okt 2026)

Tujuan: menilai kualitas kode OwlLuna dan memilih fitur atau praktik yang layak ditiru writePad.
Dokumen ini catatan riset, bukan rencana kerja. Item yang dipilih harus masuk `PLAN.md` dulu.

## Metode dan batasan

- Clone dangkal (`--depth 1`) ke folder scratchpad, hanya **dibaca**. Tidak di-build, tidak dijalankan, tidak ada tes yang dijalankan.
- Dibaca langsung: `Storage/NotebookPackage.swift` (penuh), `Editor/NotebookDocument.swift` (jalur ink, undo, simpan),
  `Editor/DocumentUndoManager.swift`, `Canvas/CanvasUndoProxy.swift`, `Canvas/PageStackLayout.swift`,
  `Canvas/StrokeHold.swift`, awal `Canvas/ShapeSnap.swift`, awal `Canvas/InkVectors.swift`, `docs/ARCHITECTURE.md`,
  `DEVICE-CHECKS.md`, `CONTRIBUTING.md`, CHANGELOG, workflow CI.
- **Tidak dibaca**: `LibrarySync`, `SyncCenter`, `NotebookRecorder`, sebagian besar view SwiftUI, dan hampir semua file tes.
  Klaim tentang sync, rekaman, dan performa hanya berasal dari dokumentasi mereka.
- Riwayat git tidak bisa diaudit (clone dangkal), jadi angka "118 commit" dari halaman GitHub tidak saya verifikasi.
- Semua angka performa dalam dokumen mereka berasal dari simulator. Mereka sendiri menulis itu.

## Gambaran ukuran

| | OwlLuna | writePad |
|---|---|---|
| Kode app (Swift) | sekitar 45.700 baris, 191 file | sekitar 2.700 baris, 22 file (setelah Milestone 6) |
| Kode tes | sekitar 21.600 baris unit (80 file) + 5.000 baris UI (37 file) | sekitar 1.400 baris unit (85 tes) + 330 baris UI (5 tes) |
| File terbesar | `Canvas/PageStack.swift` 3.095 baris, `Editor/EditorView.swift` 1.493, `Services/LibrarySync.swift` 1.171 | |
| Pihak ketiga | tidak ada (hanya framework Apple). Tidak ada `URLSession`/`URLRequest` di `OwlLuna/` (hasil grep) | sama |
| CI | build dengan warning jadi error, matriks iPadOS terbaru dan 18, nightly, UI smoke test | belum ada |

## Temuan audit

Tingkat: **T** tinggi, **S** sedang, **R** rendah. Semua temuan di bawah sudah saya cocokkan dengan kode, kecuali yang ditandai "belum diverifikasi".

### Kekuatan

1. **Urutan tulis yang aman.** `NotebookPackage.write` menulis ink tiap halaman secara atomic dulu, manifest terakhir
   (`NotebookPackage.swift:218-243`). Crash di tengah jalan tidak meninggalkan manifest yang menunjuk ke ink yang belum ada.
2. **File rusak tidak pernah ditimpa.** Yang gagal didekode diganti nama `.corrupt` lewat `Quarantine.move`. Ada
   `manifest.prev.json` sebagai cadangan, dan `recoverOrphans` memulihkan halaman baru yang ink-nya lebih baru dari manifest.
3. **Deteksi ink kosong palsu.** PencilKit mengembalikan `PKDrawing` kosong untuk data tanpa header, bukan error.
   `decodeInk` menangani itu (`NotebookPackage.swift:477-483`).
4. **Debounce dengan batas atas.** Simpan ditunda 1,2 s tetapi mulai paling lambat 5 s setelah edit pertama yang belum
   tersimpan (`scheduleSave`, `NotebookDocument.swift:689-707`). Retry dengan backoff 1 s sampai 60 s, ada notifikasi
   "nothing has been lost" saat gagal.
5. **Snapshot di main thread hanya nilai.** `makePendingSave` menyalin manifest dan ink halaman yang kotor, lalu IO berjalan
   di actor `NotebookPackage`. Hanya halaman yang kotor yang ditulis.
6. **Kompatibilitas ke depan.** Field tak dikenal disimpan sebagai JSON mentah dan ditulis balik. Manifest versi lebih baru
   dibuka read-only dan tidak pernah dikarantina atau dibangun ulang.
7. **GC yang hati-hati.** File yatim dihapus hanya setelah manifest tersimpan, tidak pernah saat ada manifest `.corrupt`
   atau manifest hasil rebuild, dan aset dianggap dipakai kalau namanya muncul di string mana pun dalam manifest.
8. **Disiplin dokumentasi.** `ARCHITECTURE.md` mencatat keputusan, ukuran, dan batas ("Known limits"). `DEVICE-CHECKS.md`
   membedakan yang sudah lolos di iPad asli dari yang baru diuji di simulator. Ini praktik yang jujur dan patut ditiru.
9. **Privasi konsisten dengan klaim.** Tidak ada kode jaringan di app. Terjemahan, study guide, dan transkripsi memakai
   framework Apple on-device. Ada `PrivacyInfo.xcprivacy` untuk app dan widget.

### Risiko dan kelemahan

| # | Tingkat | Temuan | Lokasi |
|---|---|---|---|
| 1 | S | **Bergantung pada API privat/underscore.** `DocumentUndoManager` meng-override `__registerUndoWithTarget`, dan `CanvasUndoProxy` mengandalkan PencilKit yang memanggil "private grouping API" (kata mereka sendiri). Bisa rusak diam-diam di versi iPadOS berikutnya. | `DocumentUndoManager.swift:12`, `CanvasUndoProxy.swift:3-5` |
| 2 | S | **Kunci notebook bukan enkripsi.** Hanya flag `library.locked` plus Face ID di UI. File ink dan manifest tetap terbaca, termasuk di backup dan iCloud. Mereka menulis ini terang-terangan di dokumen. Jangan menyebutnya "aman" di pemasaran. | `ARCHITECTURE.md` bagian Locked notebooks |
| 3 | S | **Rebuild manifest dari ink menghilangkan metadata.** `rebuiltManifest` membuat semua halaman jadi kertas kosong Letter berjudul "Recovered Notebook". Item halaman (kotak teks, gambar, stiker) dan template kertas hilang. Asetnya masih tersimpan karena GC dikunci, tetapi pengguna harus menyusun ulang. | `NotebookPackage.swift:160-178` |
| 4 | R | **Cadangan manifest hanya satu generasi.** `backUpManifest` menghapus `prev` lalu menyalin. Crash di antara dua langkah itu tidak menyisakan cadangan, dan `prev` selalu hanya satu simpan di belakang. Manifest yang valid secara sintaks tetapi salah secara isi akan menyalin dirinya ke `prev` pada simpan berikutnya. | `NotebookPackage.swift:264-267` |
| 5 | R | **`hold` tidak melakukan apa pun.** Isinya `try work()`. Isolasi actor yang membuat simpan menunggu, bukan fungsi ini. Aman sekarang, tetapi namanya menyesatkan dan mudah rusak kalau closure diubah jadi async. | `NotebookPackage.swift:410` |
| 6 | R | **GC bergantung pada mtime file.** File dianggap yatim kalau `mtime <= tanggal manifest`. Jam yang meleset atau file hasil restore iCloud bisa mengubah hasilnya. Belum diverifikasi apakah itu pernah terjadi. | `NotebookPackage.swift:427-446` |
| 7 | S | **Undo menyimpan seluruh `PKDrawing` halaman per langkah.** Dibatasi `UndoBudget` (48 MB, 20 sampai 200 langkah), tetapi itu perkiraan yang belum dicocokkan dengan memory trace di perangkat (kata dokumen mereka). | `DocumentUndoManager.swift:35-42` |
| 8 | S | **File raksasa.** `PageStack.swift` 3.095 baris dalam satu file. Sulit ditinjau, dan kontributor baru akan kesulitan. | `Canvas/PageStack.swift` |
| 9 | R | **290 `try?`.** Banyak kegagalan IO ditelan tanpa log (mis. `removeItem`, `copyItem` di `backUpManifest`). Sebagian disengaja untuk best-effort, tetapi susah dilacak saat ada laporan. | seluruh `OwlLuna/` |
| 10 | R | **Satu `try!` dan 17 `fatalError()`.** Semua `fatalError` ada di `required init?(coder:)` (aman). `try!` di fallback `ModelContainer` in-memory dan `as! CGImage` pada `CALayer.contents` hampir tak mungkin gagal. | `LibraryIndex.swift:186`, `PageItemViews.swift:66` |
| 11 | S | **Risiko bus factor.** Satu pemilik, 2 kontributor, banyak proyek lain. Roadmap mengandalkan pengujian di iPad asli yang belum dikerjakan. | repo |
| 12 | S | **Hampir semua klaim performa belum terbukti di perangkat.** Hitch, memori pada zoom 5x, latensi Pencil, palm rejection: semuanya belum. Daftar centang "Device checks before 1.0" hampir kosong. | `DEVICE-CHECKS.md` |
| 13 | R | **Tidak jelas apakah CI benar-benar hijau.** Workflow memakai runner `xcode-27` (komentar mereka: belum ada label macos-27). Saya tidak memeriksa hasil run. | `.github/workflows/ci.yml` |

## Fitur dan praktik yang layak ditiru

Prioritas: **P1** murah dan langsung mengurangi risiko writePad, **P2** nilai pengguna jelas, **P3** besar atau nanti.
Ukuran: S (sehari atau kurang), M (beberapa hari), L (sekitar seminggu atau lebih), XL (berbulan-bulan).
Lisensi MIT: boleh menyalin kode asal menyertakan pemberitahuan hak cipta dan lisensi. Saran saya menulis ulang dari ide,
karena arsitekturnya berbeda dan aturan "tanpa dependensi baru" tidak melarang, tetapi menyalin menambah beban atribusi.

### P1: ketahanan data (cocok dengan aturan "Never lose ink")

| Fitur | Di OwlLuna | Kondisi writePad | Ukuran |
|---|---|---|---|
| Karantina file rusak (`.corrupt`), tidak menimpa | `Quarantine.move` | **selesai (M6)**: manifest dan drawing | S |
| `manifest.prev.json` sebagai cadangan baca | `readManifest` | **selesai (M6)** | S |
| Urutan tulis: ink dulu, manifest terakhir | `write(_:)` | **sudah ada** (`EditorViewModel.saveNow`: ink, markup PDF, lalu manifest) | - |
| Batas latensi simpan (maksimal 5 s) di atas debounce | `scheduleSave` | **selesai (M6)**: `SaveTiming` | S |
| Retry dengan backoff dan notifikasi gagal simpan | `performSave` | **selesai (M6)**: 1 s berlipat, maks 60 s, banner tetap ada | S |
| IO simpan di luar main thread | actor `NotebookPackage` | **belum** (sisa M6): `saveNow` masih sinkron di `@MainActor` | M |
| Pemeriksaan header `PKDrawing` kosong palsu | `decodeInk` | **selesai (M6)** | S |
| Pemulihan halaman yatim setelah crash | `recoverOrphans` | **selesai (M6)** | M |
| Simpan hanya halaman yang kotor (per-halaman) | `makePendingSave` | **sudah ada** (`dirtyPageIDs`) | - |
| Pertahankan field tak dikenal (JSON passthrough) | `JSONValue`, `ManifestCodec` | **belum** (sisa M6) | M |

Catatan: ini sebagian besar mengisi celah yang ada di `AGENTS.md` ("Never lose ink"). Sudah dijadikan Milestone 6 "Storage hardening" di `PLAN.md`.

**Celah yang ikut terbawa ke writePad** (ditemukan saat review M6, 25 Okt 2026):
- Seperti temuan 4, cadangan manifest hanya satu generasi, dan manifest yang valid tetapi salah isinya akan tersalin ke `prev`.
  Bedanya, writePad menulis `prev` secara atomic (tanpa hapus dulu), jadi tidak ada jeda tanpa cadangan.
- Seperti temuan 6, pemulihan halaman yatim bergantung pada mtime file lawan `updatedAt` manifest. Jam yang meleset atau
  file hasil restore bisa membuat halaman yang sengaja dihapus muncul lagi (bukan kehilangan data, tetapi membingungkan).
- Diperbaiki saat review: manifest yang **ada tetapi tidak terbaca** (error IO sesaat) dulu diganti dengan cadangan yang
  lebih lama, sehingga perubahan terakhir hilang saat simpan berikutnya. Sekarang pemuatan berhenti dengan error dan
  tidak menimpa apa pun (`NotebookStoreRecoveryTests.unreadableManifestIsNotReplacedByTheOlderBackup`).

### P1: proses dan kualitas

| Praktik | Catatan | Ukuran |
|---|---|---|
| `docs/DEVICE-CHECKS.md` (daftar centang uji di iPad asli, dengan rekaman dan versi iPadOS) | langsung menjawab item PLAN.md "Test on real iPad" | S |
| Template issue yang meminta model iPad, versi iPadOS, versi app, dan Pencil atau jari | berguna begitu ada pengguna lain | S |
| CI GitHub Actions dengan `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | writePad belum punya CI | S |
| `performAccessibilityAudit` di XCUITest (light, dark, teks besar) | murah, menangkap kontras dan label | S |

### P2: fitur yang dirasakan pengguna

| Fitur | Cara kerja di OwlLuna | Catatan untuk writePad | Ukuran |
|---|---|---|---|
| **Shape snap (draw and hold)** | `StrokeHoldRecognizer` adalah `UIGestureRecognizer` yang tidak pernah mengenali; ia hanya mencatat berapa lama sentuhan diam sebelum diangkat. Setelah 0,45 s, `ShapeRecognizer` (geometri murni, bisa dites) mencari garis, panah, elips, atau poligon, lalu stroke diganti. | Trik gesture recognizer-nya kecil dan bisa dipakai apa adanya sebagai ide. `ShapeRecognizer` sekitar 368 baris dan murni geometri, jadi mudah dites. Ini fitur yang paling sering dicari pengguna GoodNotes. | M |
| **Ekspor PDF yang bisa dicari** | `PageWords` menulis kata hasil Vision sebagai teks tak kasat mata di bawah ink | writePad meratakan ink ke gambar saat ekspor, jadi hasil ekspor tidak bisa dicari | M |
| **Ink vektor di ekspor PDF** | `InkVectors` menggambar pen, fineliner, dan fountain pen sebagai bentuk vektor; ink bertekstur dipakai sebagai gambar | writePad memakai `drawing.image(scale ≤ 2)` (`NotebookExporter.swift:162`), jadi ekspor buram saat di-zoom dan berukuran besar. Perbaikan terbesar untuk kualitas ekspor, tetapi membutuhkan tes piksel terhadap rendering PencilKit | L |
| **Pencarian tulisan tangan** | Vision per halaman, di-cache dengan hash ink, hanya membaca ulang kalau ink berubah | writePad baru mencari judul | M |
| **Recently Deleted** | hapus lunak dengan masa simpan 7, 30, atau 90 hari | mencegah kehilangan karena salah sentuh | S sampai M |
| **Tag dan Smart Shelves** | tag di manifest, filter tersimpan | nanti, setelah library bertambah | M |
| **Backup dan restore yang hanya menambah** | arsip LZFSE; restore tidak pernah menimpa | cocok dengan aturan "never lose" | M |
| **Ekspor Markdown/teks biasa** | dari hasil OCR | murah kalau pencarian sudah ada | S |
| **Mode kidal dan pilihan Appearance** | pengaturan sederhana | S |
| **Dokumen satu UndoManager, terpisah dari kanvas** | `DocumentUndoManager` plus `CanvasUndoProxy` | hanya relevan kalau kita pindah ke kanvas per halaman. **Hati-hati**: bergantung pada API privat (temuan 1) | L |

### P3: besar, nanti, atau di luar cakupan

| Fitur | Catatan |
|---|---|
| Kanvas per halaman dengan jendela viewport | Keputusan arsitektur terbesar. Benchmark mereka menunjukkan operasi halaman 114 ms (satu kanvas) lawan 3 ms (per halaman) pada notebook uji 100 halaman, tetapi itu angka simulator. **Ukur dulu writePad di iPad asli** (item PLAN.md yang belum dicentang) sebelum memutuskan. |
| Tray pena sendiri (preset hingga 8 pena) menggantikan `PKToolPicker` | alasan mereka: picker tidak bisa diberi gaya atau item sendiri. Nilai besar untuk UX, tetapi mengharuskan menangani double-tap dan squeeze Pencil sendiri |
| Item halaman (kotak teks, gambar, stiker, tautan, tape) | sistem layer besar. Pilih satu per satu |
| Jendela zoom | berguna untuk tulisan kecil, kompleks |
| Whiteboard 40.000 pt | murah di desain mereka berkat jendela viewport, mahal tanpa itu |
| Sync iCloud | XL. Prinsipnya layak ditiru kelak: jangan menggabung halaman, versi lama jadi "(conflicted copy)", tiga tanggal (lokal, jauh, terakhir sepakat), tanda hapus. Mereka sendiri baru menguji sebagian di iCloud asli |
| Rekaman audio, replay ink, transkripsi, flashcard, study guide, presentasi layar kedua | di luar tujuan writePad saat ini |

## Komentar dan rekomendasi

1. **Mulai dari P1.** Biayanya kecil, tidak mengubah UI, dan menutup risiko kehilangan data yang jadi aturan utama proyek.
   Bagian "Storage hardening" bisa selesai tanpa mengubah arsitektur editor.
2. **Ukur sebelum migrasi arsitektur.** Jangan memindahkan writePad ke kanvas per halaman hanya karena benchmark simulator
   mereka. Jalankan uji 100+ halaman di iPad asli dulu. Kalau lolos, simpan satu kanvas dan tunda migrasi.
3. **Shape snap dan ekspor vektor** adalah dua fitur yang paling terasa dibanding aplikasi lain. Shape snap lebih murah dan
   bisa dikirim lebih dulu.
4. **Jangan meniru dari mereka**: ketergantungan pada API privat untuk undo (temuan 1), file 3.000 baris, dan klaim
   keamanan untuk kunci notebook. Catat ini sebagai pelajaran, bukan resep.
5. **Kolaborasi**: titik masuk paling realistis tetap `good first issue` mereka dan pengujian perangkat. Kontribusi apa pun
   ke repo mereka adalah keputusan Anda. Saya tidak menghubungi atau mengomentari apa pun di GitHub mereka.

## Tindak lanjut yang belum dikerjakan

- [ ] Membaca `LibrarySync.swift`, `SyncCenter.swift`, dan `NotebookRecorder.swift` (audit sync).
- [ ] Menjalankan test suite mereka di simulator untuk memeriksa klaim "tests pass".
- [ ] Membandingkan `ShapeRecognizer` dengan implementasi alternatif sebelum memilih pendekatan.
- [x] Memutuskan item P1 mana yang masuk `PLAN.md` (Milestone 6, 6 dari 8 item teknis selesai per 25 Okt 2026).
