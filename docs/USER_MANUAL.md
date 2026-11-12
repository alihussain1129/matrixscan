# Exalted Industrial Machine Vision Platform — User Manual

Version: 1.0.0  
Product: Exalted (MatrixScan)  
Target Platforms: Linux Desktop (x86_64), Windows Desktop (x64), Android Mobile (ARM64 / ARMv7)

---

## 1. Overview & System Capabilities

**Exalted** is an industrial-grade machine vision, Optical Character Recognition (OCR), Optical Character Verification (OCV), and high-speed barcode decoding platform. Designed for production floors, packaging facilities, logistics lines, and automated inspection cells, Exalted operates entirely **offline** without requiring cloud connectivity.

### Core Capabilities:
- **High-Speed Barcode & 2D Matrix Decoding**: C++20 native decoding engine powered by ZXing-C++ with dot-peen rank morphological filters for DPM (Direct Part Marking) on cast and machined metals.
- **Offline OCR Engine**: Tesseract 5.3 TSV recognition on Desktop (Linux / Windows) and Google ML Kit on Android.
- **Interactive ROI Selection**: Region of Interest drag-and-crop for isolated character recognition.
- **OCV Rule Verification Engine**: Industrial rule evaluation (Exact Match, Regex, Lot Code, Expiration Date, Serial Numbers, Numeric Ranges) with character-level diff highlighting and explainable PASS / FAIL verdicts.
- **Keyence SR-751 Industrial Code Reader Integration**: Direct TCP/IP socket control (`LON`, `LOFF`, `T1`, `PRG`, `FTPOUT`, `BEEP`) and built-in Dart FTP receiver (port 2121) for CMOS image capture and real-time verification.
- **Dual-Tab Traceability & History**: Clean separation between Barcode Decoder Scans and OCR/OCV Records with full search, filtering, CSV/JSON export, and disaster recovery backup.

---

## 2. Navigating the Interface

### Desktop Layout (Linux & Windows)
On Windows and Linux, `AppShell` selects `ExaltedShell`, the responsive workstation interface. Its navigation sidebar adapts to available window width, with desktop top bar, status bar, keyboard shortcuts, command palette, and image-import actions:
- **Dashboard**: System overview, device statuses, recent activity, and quick-launch inspection actions.
- **Scanner / Decoder**: Live camera scanner, file scanning, and batch decoding.
- **OCR / OCV Workspace**: Industrial image inspection, ROI crop, offline OCR, rule verification, and recipe management.
- **Keyence Hardware**: Connection status, TCP/IP live controls, trigger actions, and CMOS inspection stream.
- **History & Records**: Dedicated tabs for Decoder Scans and OCR Records with search and export.
- **System Settings**: Diagnostics, OCR engine parameters, Keyence network configuration, and backup/restore.

### Mobile Layout (Android)
On mobile displays (width < 900px), Exalted transitions seamlessly to an intuitive bottom navigation bar while retaining full access to all features and modals.

---

## 3. Barcode & 2D Code Decoding Workspace

### Supported Barcode & 2D Formats
- **2D Matrix Codes**: Data Matrix (ECC 200, square and rectangular formats, dot-peen DPM), QR Code, Micro QR Code, Aztec, PDF417, MaxiCode.
- **1D Linear Barcodes**: Code 128 (GS1-128), Code 39, Code 93, Codabar, EAN-8, EAN-13, UPC-A, UPC-E, ITF (Interleaved 2 of 5), GS1 DataBar, GS1 DataBar Expanded.

### Live Camera Scanning
1. Navigate to **Scanner**.
2. Point the camera at the target code. The scanning isolate processes frames continuously using the C++20 engine.
3. Upon detection, a bounding box is rendered over the code, the decoded string is parsed (including GS1 Application Identifiers), a confirmation tone sounds, and the result card appears.

### Image File Import & Batch Decoding
1. In the Scanner workspace, click **Import Image** or drag-and-drop an image file (`.png`, `.jpg`, `.bmp`, `.tiff`).
2. The image is decoded using the high-effort (`tryHarder`) pipeline, applying contrast enhancement and rank filters for difficult marks.

---

## 4. OCR & OCV Industrial Workspace

The **OCR / OCV Workspace** allows operators to inspect character markings on labels, packaging, and metal components.

### Step-by-Step Inspection Workflow:
1. **Load Image**: Click **Open Image** or click **Take Photo** to capture an image from the camera.
2. **Select Region of Interest (ROI)**:
   - Click and drag over the image preview to draw a bounding rectangle around the text to inspect (e.g., expiration date or batch number).
   - Click **Crop Selected ROI** to crop the image precisely.
3. **Select OCV Rule (Recipe)**:
   - Choose a preset or custom rule from the **Active Verification Rule** dropdown:
     - `Exact Match`: Compares against an exact string.
     - `Regex Pattern`: Validates formatting (e.g., `^LOT-[A-Z0-9]{6}$`).
     - `Lot Code`: Validates industrial batch/lot prefixes.
     - `Expiry Date`: Confirms the date string is syntactically valid and has not expired against current system time.
     - `Numeric Range`: Verifies readings or tolerances fall within specified numerical limits.
4. **Run OCR & Verify**:
   - Click **Run OCR & Verify**.
   - The offline Tesseract TSV engine parses the image and computes word/character coordinates and confidence scores.
   - The **OCV Engine** evaluates the text against the selected rule and outputs:
     - **PASS (Green)**: Mark meets all verification criteria and confidence threshold.
     - **FAIL (Red)**: Mark fails format or content verification, accompanied by a character-level diff showing mismatched, missing, or inserted characters.
     - **INCONCLUSIVE (Amber)**: Low optical contrast or confidence score below required threshold.
5. **Edit & Save**:
   - The operator can edit recognized text if manual verification is needed.
   - Click **Save to History** to record the inspection result, image path, rule evaluation, and timestamp.

---

## 5. Keyence SR-751 Device Integration

Exalted directly manages Keyence SR-751 industrial code readers over Ethernet.

### Setting Up Connection:
1. Navigate to **Keyence Hardware** (or Settings > Keyence Hardware).
2. Enter the Keyence Reader's IP address (default: `192.168.100.100`) and command port (default: `9004`).
3. Set the Local FTP Port (default: `2121`).
4. Click **Connect**. The status indicator turns **ONLINE (Connected)**.

### Commands & Operations:
- **Trigger Read (`LON` / `LOFF`)**: Commands the reader to emit lighting and decode.
- **Test Mode (`T1` / `T2`)**: Runs hardware alignment and tuning tests.
- **Beep (`BEEP`)**: Emits the audible buzzer on the Keyence unit.
- **Bank Select (`PRG,xx`)**: Switches active reading parameter banks.
- **FTP Image Transfer (`FTPOUT`)**: Commands the Keyence camera to transmit the current CMOS image buffer to Exalted's embedded FTP receiver.

### Automated Inspection Pipeline:
When enabled, Exalted links the barcode string decoded by the Keyence reader with the CMOS image sent over FTP:
1. Keyence reads the 2D Data Matrix on the product.
2. Keyence uploads the captured image to Exalted via FTP on port 2121.
3. Exalted automatically triggers OCR/OCV on the printed alphanumeric text in the image.
4. The system validates both the 2D code and the printed human-readable text simultaneously.

---

## 6. History, Search & Traceability

### Separation of Concerns:
- **Decoder Scans Tab**: Stores barcode symbology, raw payload, GS1 structured elements, decode time ($\mu$s), and timestamp.
- **OCR Records Tab**: Stores recognized text, confidence percentage, permanent image path, OCV rule evaluation verdict, and character diffs.

### Exporting Records:
- Click **Export (CSV)** or **Export (JSON)** in the History toolbar.
- The exported file includes full audit data suitable for ISO 9001 and MES traceability logging.

---

## 7. Disaster Recovery & Backup

1. Navigate to **System Settings > Backup & Disaster Recovery**.
2. Click **Create Backup Archive**.
3. Exalted creates an atomic snapshot containing:
   - Full SQLite database records (Decoder scans and OCR history).
   - OCV inspection recipes and rules.
   - User configuration and hardware settings.
4. To restore from a previous backup, click **Restore from Backup** and select the `.exalted-backup` archive. All records and recipes will be restored and validated for integrity.
