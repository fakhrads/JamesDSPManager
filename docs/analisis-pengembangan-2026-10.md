# Analisis pengembangan JamesDSP Manager (Oktober 2026)

Target utama: Android 17 dengan root (KernelSU), dipakai bareng EarFun Air Pro 4+.

Ringkasan: project ini masih layak dikembangin. Engine JamesDSP sendiri udah nggak di-update sejak 2023, tapi masih stabil dan nggak butuh perubahan. Yang rawan justru lib AIDL. Lib yang ada sekarang di-build untuk effect HAL V2, sedangkan Android 17 udah pakai V4. Selain itu, app upstream punya beberapa fitur baru yang bisa diambil.

## 1. Kondisi upstream

| Repo | Aktivitas terakhir | Status |
| --- | --- | --- |
| james34602/JamesDSPManager (engine asli) | Kode terakhir 23 Nov 2023, setelah itu cuma FUNDING.yml (Jun 2025) | Diam. Release terakhir 28Nov2023 |
| ThePBone/JamesDSPManager branch `extensions` (submodule libjamesdsp app) | 24 Nov 2023 (`1b9f89d`) | Sama dengan yang kita pakai |
| anonymix007/JamesDSPManager (sumber lib AIDL) | 26 Mar 2025, "Implement AIDL JamesDSP effect" | PR #68 ke upstream masih OPEN. Build-nya cuma bisa di dalam AOSP tree |
| timschneeb/RootlessJamesDSP (app) | Merge terakhir 24 Jul 2026, PR masih masuk sampai Okt 2026 | Aktif lewat kontributor. Release resmi terakhir v1.6.13 (Des 2024) |
| ShadoV90/JamesDSPManager (modul) | Release 6.5-RC3-test4, 11 Jun 2026 | Ditinggal. Catatan rilisnya: "last version before maintain suspension" |
| zahahah/PIXAML | 2026 | Companion AML untuk Pixel di Android 17. Bukan pengganti modul ini |

Isi zip release terakhir ShadoV90 udah gue bandingin dengan repo ini. Nggak ada kerjaan dia yang ketinggalan. Bedanya cuma perbaikan yang udah kita commit (`==` jadi `=`, quoting di `find`, shebang `patch.sh`, `PAPPVER`).

## 2. Android 17: risiko utama ada di lib AIDL

### Fakta dari AOSP

- Di branch `android17-release`, `aidl_api/android.hardware.audio.effect` punya versi 1, 2, 3, dan 4. Android 15 berhenti di V2, Android 16 di V3.
- `compatibility_matrix.202604.xml` (Android 17) minta `android.hardware.audio.effect` versi 1 sampai 4. Jadi vendor bebas pakai versi mana pun di rentang itu.
- Antara V2 dan V4, file yang berubah: `Descriptor`, `Flags`, `Parameter`, `Processing`, `Range`, `State`, `HapticGenerator`, `Spatializer`, plus `Eraser` yang baru ditambah.

### Kondisi lib di modul

`common/files/aidl/libjamesdsp.so` nge-link ke:

```
android.hardware.audio.effect-V2-ndk.so
android.media.audio.common.types-V3-ndk.so
android.hardware.common-V2-ndk.so
android.hardware.common.fmq-V1-ndk.so
libaudioaidlcommon.so
```

`patch.sh` jalan setiap boot. Script ini nyari `<nama>-V*-ndk.so` dengan versi tertinggi di `/system/lib64`, `/apex/*/lib64`, dan `/vendor/lib64`, lalu ganti NEEDED di lib pakai `patchelf`. Di Android 17 hasilnya V2 diganti ke V4.

### Kenapa ini rawan

1. **Layout struct beda.** Lib di-compile dengan header V2. `Parameter` dan `Descriptor` di V4 punya varian union dan field tambahan, jadi ukuran object-nya bisa beda dari yang diasumsikan lib. Effect factory memanggil `queryEffect()` dan `createEffect()` langsung di dalam proses, dan `Descriptor` dioper sebagai struct C++. Kalau ukurannya nggak cocok, efeknya bisa nggak kebaca, audio HAL crash, atau efeknya diam tanpa bunyi. Ganti NEEDED cuma ngakalin linker, ABI-nya tetap nggak sama.
2. **Versi yang dipilih belum tentu versi yang dipakai HAL.** `sort | tail -n 1` ngambil versi tertinggi dari partisi mana pun. Bisa aja `/system` punya V4 padahal service effect HAL di `/vendor` masih V3. Yang harus dicocokin itu versi yang di-link oleh service effect HAL di vendor.
3. **`libaudioaidlcommon.so` nggak berversi.** Lib ini diambil dari device, dan ABI-nya bisa berubah antar rilis Android.

Ada kabar bagus juga. README PIXAML nyatet bahwa di Pixel 10 Pro XL Android 17 (`CP2A.260705.006`), JamesDSP tetap jalan tanpa PIXAML lewat `IFactory/default`. Jadi jalurnya masih kebuka. Yang perlu dibenerin itu kecocokan versinya.

### Rencana perbaikan

| Prioritas | Kerjaan | Catatan |
| --- | --- | --- |
| P0 | `patch.sh` pilih versi berdasarkan NEEDED dari binary effect HAL di `/vendor/bin/hw/*audio*`, bukan versi tertinggi | Kecil, bisa langsung dikerjain |
| P0 | Build ulang lib AIDL untuk V3 dan V4 dari source anonymix007 (`Android.bp`) di AOSP `android17-release`. Kirim satu lib per versi, terus `install.sh` pilih yang cocok | Butuh checkout AOSP, terlalu berat buat disk lokal 50 GB. Lebih realistis dijalanin di GitHub Actions dengan sparse checkout, atau di mesin build terpisah |
| P1 | Log diagnosa di `service.sh`: versi HAL yang kedetect, lib yang dipilih, dan apakah UUID JamesDSP muncul di `dumpsys media.audio_flinger` | Biar laporan bug dari user lain gampang dibaca |
| P2 | Pantau PIXAML untuk device non-Pixel yang butuh AML | Opsional |

## 3. App: fitur upstream yang bisa diambil

Fork kita berbasis upstream `58e6b1b` (Agu 2025). Sejak itu upstream nambah 13 commit:

| Fitur | Sumber | Jalan di mode root? | Catatan |
| --- | --- | --- | --- |
| Parametric EQ dengan UI kurva | PR #318 (Apr 2026) | Ya | Murni Kotlin. Respons PEQ digabung ke GEQ, jadi nggak perlu ubah libjamesdsp atau lib AIDL |
| File convolver per sample rate | PR #337 (Jul 2026) | Ya | Berguna kalau output BT gonta-ganti 44.1/48/96 kHz |
| Fix sesi notifikasi rootless | PR #336 | Nggak relevan | Khusus rootless |
| Info Android 15+ (screen share protection) | PR #309 | Nggak relevan | Khusus rootless |

PR upstream yang masih open dan perlu dipantau:

- **#351**: migrasi ke AGP 9/Gradle 9 dan update dependency. Bakal kepake buat naikin `targetSdk`.
- **#350**: mode low-latency, Android EQ, PEQ per channel. Sebagian besar khusus rootless, dan PEQ per channel butuh ubah libjamesdsp.
- **#338**: ngikutin sample rate USB. Khusus rootless.

Merge upstream bakal konflik di `RootAudioProcessorService.kt` dan `JamesDspRemoteEngine.kt`, karena dua file itu udah kita ubah. Konfliknya kecil dan bisa diberesin manual.

Hal lain di app:

- `targetSdk = 34`. App masih bisa di-install di Android 17, tapi sebaiknya dinaikin ke 35 atau 36 bareng migrasi AGP. Edge-to-edge perlu dicek setelahnya.
- AutoEQ di app masih jalan. Backend `aeq.timschneeberger.me` ngebales hasil pencarian kalau request-nya bawa User-Agent app. Request tanpa User-Agent itu dapat 404, jadi jangan dikira servernya mati.

## 4. EarFun Air Pro 4+

Codec yang didukung: LDAC, aptX Lossless, aptX Adaptive, AAC, SBC, dan LC3 (LE Audio/Auracast). Bluetooth 6.0. Spatial audio bawaan nggak ada.

Dampaknya ke JamesDSP:

- **Codec nggak ngaruh ke DSP.** JamesDSP mode root ngolah PCM di efek audio sebelum di-encode ke Bluetooth. LDAC, aptX, dan LC3 semuanya kena efek yang sama. Kalau HP pakai A2DP offload, encoding-nya di DSP hardware, tapi itu tetap setelah mixer.
- **Kalau efek kadang nggak kedengeran,** coba matiin Spatial audio di setelan device Bluetooth (Android tetap bisa nyalain spatializer walaupun earbud-nya nggak punya head tracking). Jalur spatializer dan offload itu tempat paling mungkin efeknya ke-bypass. Ini dugaan yang perlu dites, belum terbukti.
- **EQ di app EarFun** sebaiknya diset ke default atau flat, biar EQ-nya nggak numpuk dengan JamesDSP.
- **AutoEQ:** database AutoEQ punya "EarFun Air Pro 4 (ANC off)" dan "(ANC on)" dari Regan Cipher, dan dua-duanya bisa dicari dari GEQ di app. Model 4+ belum ada. Tuning-nya bisa beda, jadi pakai profil itu sebagai titik awal aja, terus koreksi pakai telinga.
- **Headroom:** profil AutoEQ dan bass boost bisa bikin clipping. Kasih preamp negatif sesuai boost terbesar dan nyalain limiter.
- **LE Audio vs A2DP:** LE Audio pakai jalur output sendiri. Kalau efek jalan di LDAC tapi nggak jalan di LE Audio (atau sebaliknya), kabarin, karena itu bug yang bisa dikejar.

## 5. Data yang dibutuhin dari HP

Jalanin pakai `su` (Termux atau `adb shell`), terus kirim hasilnya:

```sh
getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.id
service list | grep -i 'audio.effect'
M=/data/adb/modules/ainur_jamesdsp
for f in /vendor/bin/hw/*audio*; do echo "$f"; "$M/tools/patchelf" --print-needed "$f" 2>/dev/null | grep -E 'effect|media.audio'; done
ls /system/lib64 /vendor/lib64 /apex/*/lib64 2>/dev/null | grep -E 'audio.effect-V|media.audio.common.types-V' | sort -u
"$M/tools/patchelf" --print-needed /vendor/lib64/soundfx/libjamesdsp.so
cat "$M"/logs/*.txt
dumpsys media.audio_flinger | grep -i -B2 -A6 'f27317f4'
logcat -d | grep -iE 'jamesdsp|EffectFactory|AHAL_' | tail -80
```

Dari output ini kelihatan versi effect HAL yang dipakai vendor, versi yang dipilih `patch.sh`, dan apakah AudioFlinger beneran muat efek JamesDSP.

## 6. Hasil tes di device (11 Okt 2026)

Device: POCO F7 (`onyx`), crDroid 13 (Android 17, SDK 37), blob vendor dari HyperOS OS3.0.7.0.WOLMIXM (HyperOS 3, Android 16, patch Februari 2026; string fingerprint-nya nulis 15, tapi kode `W` di nomor build itu Android 16), KernelSU. Dites lewat wireless adb.

- **JamesDSP jalan.** Di `dumpsys media.audio_flinger`, efek `f27317f4-...` nempel di output `AUDIO_DEVICE_OUT_BLUETOOTH_A2DP` dengan state ACTIVE, ngolah float 48 kHz.
- **Effect HAL-nya V2, bukan V4.** `/system` punya `audio.effect-V4`, tapi HAL Qualcomm (`libaudioeffecthal.qti.so` di proses `audiohalservice.qti`) link ke `audio.effect-V2` dan `common.types-V3` dari `/vendor`. Jadi buat ROM custom di atas vendor lama, yang nentuin itu versi vendor, bukan versi Android-nya. Lib AIDL V2 di modul pas buat device ini.
- **Bug `patch.sh` kebukti.** Lib di-patch dari `common.types-V3` ke `V5`, padahal V3 ada di vendor. Proses HAL jadi muat types V2, V3, dan V5 barengan. Sekarang udah dibenerin: dependency cuma diganti kalau versi aslinya nggak ada di `/vendor/lib64` atau `/odm/lib64`, dan lib dipulihin dari salinan asli (`tools/libjamesdsp-aidl.so`) setiap boot. Udah dites di device untuk dua kasus, versi ada dan versi hilang.
- **Effect HAL tetap V2 walaupun blob-nya udah Android 16.** Device ini rilis dengan Android 15 (`ro.board.first_api_level=202404`), dan aturan vendor freeze Google ngebolehin vendor tetap pakai versi HAL waktu rilis. Framework Android 17 nerima effect V1 sampai V4. Per Oktober 2026, POCO F7 belum punya HyperOS 4 (Android 17) stable, baru beta (OS4.0.0.2.XOLMIXM). Kalau nanti ROM pindah ke blob HyperOS 4, cek ulang versi HAL-nya.
- Spatializer nggak didukung di device ini, jadi jalur bypass lewat spatializer nggak berlaku.
- Earbud nyambung lewat A2DP (LDAC/aptX HD tersedia), bukan LE Audio.
- Ada satu instance JamesDSP nyangkut di "Orphan Effect Chains" dari sesi audio yang udah ditutup. Ini kebocoran kecil di app yang perlu dikejar.

## 7. Urutan kerja yang disaranin

1. ~~Ambil data dari HP~~ dan ~~benerin `patch.sh`~~ (selesai, lihat bagian 6).
2. Tes di device lain yang vendor-nya beneran Android 17 (V4), misalnya Pixel.
3. Siapin pipeline build lib AIDL V3 dan V4 dari AOSP `android17-release`, lalu `install.sh` pilih lib sesuai versi HAL.
4. Merge upstream app (PEQ dan convolver per sample rate), naikin versi app ke 1.6.17.
5. Naikin `targetSdk` setelah PR #351 masuk upstream, atau port sendiri.

## Sumber

- AOSP `hardware/interfaces`, branch `android17-release`: `audio/aidl/aidl_api/android.hardware.audio.effect/` dan `compatibility_matrices/compatibility_matrix.202604.xml`
- [AIDL Audio HAL, source.android.com](https://source.android.com/docs/core/audio/aidl-implement)
- [james34602/JamesDSPManager](https://github.com/james34602/JamesDSPManager) dan [PR #68 Implement AIDL JamesDSP Effect](https://github.com/james34602/JamesDSPManager/pull/68)
- [anonymix007/JamesDSPManager](https://github.com/anonymix007/JamesDSPManager)
- [timschneeb/RootlessJamesDSP](https://github.com/timschneeb/RootlessJamesDSP), PR #318, #336, #337, #338, #350, #351
- [ShadoV90/JamesDSPManager release 6.5-RC3-test4](https://github.com/ShadoV90/JamesDSPManager/releases)
- [zahahah/PIXAML](https://github.com/zahahah/PIXAML)
- [timschneeb/AutoEqApi](https://github.com/timschneeb/AutoEqApi) dan [AutoEq index](https://github.com/jaakkopasanen/AutoEq/blob/master/results/INDEX.md)
- Spesifikasi EarFun Air Pro 4+: [GSMArena](https://m.gsmarena.com/earfun_air_pro_4_review-amp-71154.php), [Techaeris](https://techaeris.com/2026/02/21/earfun-air-pro-4-plus-review/), [kakaku.com](https://kakaku.com/item/J0000049795/spec/)
