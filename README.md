# Exalted Scanner

Exalted Scanner is the product name. MatrixScan is the GitHub repository.

The Flutter Android app scans QR codes, Data Matrix, and a wide range of 1D and 2D barcode formats using its native C++ decoder and platform integrations.

## Browser edition

The browser companion uses ZXing to read supported QR and barcode formats from a camera or image. Decoding happens locally in the browser; scan data is not uploaded.

- Live app: https://alihussain1129.github.io/matrixscan/
- Source repository: https://github.com/alihussain1129/matrixscan
- Browser companion guide: [web-companion/README.md](web-companion/README.md)

The browser edition is separate from the Flutter Android app. Mobile-specific features such as native C++ FFI decoding and ML Kit OCR are not available in the browser.

## Run the Android app

```powershell
flutter pub get
flutter run
```

## Run the browser companion

```powershell
cd web-companion
npm ci
npm run dev
```

GitHub Actions builds and deploys the browser companion to GitHub Pages when changes are pushed to the `live-scan-debug` branch.
