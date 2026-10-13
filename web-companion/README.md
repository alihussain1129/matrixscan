# Exalted Scanner Web Edition

This browser edition complements the Exalted Scanner Flutter Android app in the MatrixScan repository. It uses ZXing to scan QR, Micro QR, Data Matrix, Aztec, PDF417, MaxiCode, EAN/UPC, Code 39/93/128, Codabar, ITF, and RSS formats from a camera stream or selected image.

## Privacy and platform differences

- Camera frames and selected images are decoded locally. The web companion does not upload them or send scan results to a server.
- Camera access requires HTTPS (or localhost) and the user's permission.
- The native Android app remains the full-featured version. Its C++ FFI decoder and ML Kit OCR are mobile-specific and are not part of this browser edition.
- Recent results exist only in the open tab and are cleared when it closes.

## Run locally

```powershell
npm ci
npm run dev
```

For a production build:

```powershell
npm run build
npm run preview
```

## Deployment

The repository's `Deploy MatrixScan web companion` GitHub Actions workflow builds this folder and publishes it to GitHub Pages when changes are pushed to `live-scan-debug`. The deployed path is:

https://alihussain1129.github.io/matrixscan/
