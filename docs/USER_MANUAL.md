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
- **Keyence SR-751 Industrial Code Reader Integration**: TCP command and Data Port 1 connections, with an embedded FTP image receiver. Physical scanner, trigger, and image-transfer compatibility must be verified on the actual device.
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
On Android and iOS, AppShell selects the phone-first MobileShell with bottom navigation. Windows and Linux always use the workstation ExaltedShell; its sidebar adapts to the available window width.

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
2. Enter the reader's IP address (factory default: `192.168.100.100`) and Command Port (factory default: `9004`).
3. Enter Data Port 1 if it differs from the Command Port; leave it blank to reuse the Command Port. Configure Data Port 1 on the reader as an Ethernet server (`Remote IP = 0.0.0.0`).
4. Click **Connect**. A verified command connection does not by itself prove that barcode data is arriving on Data Port 1.

### Commands & Operations:
- **Identity (`KEYENCE`)**: Read-only model and system-version query used for verification.
- **Reader Error Status (`ERRSTAT`)**: Documented read-only error-status query.
- **Trigger Read (`LON` / `LOFF`)**: Documented timing controls; operator action only, and test them only in a safe machine state.
- Other commands, including `T1`, `T2`, `PRG`, `BEEP`, and `FTPOUT`, are not enabled in the default command allow-list because their use has not been verified for this integration.

### FTP Image Transfer and Inspection:
1. Configure the FTP receiver in **Settings → FTP Receiver**. The SR-750 FTP service default is TCP port `21`; active FTP data uses local source port `20`.
2. Set the scanner's FTP destination IP to the PC's Ethernet address and configure the scanner's FTP client credentials to match Exalted's receiver credentials.
3. On Linux, binding ports 20/21 may require `CAP_NET_BIND_SERVICE`. Do not run Exalted as root. Android may not permit binding these ports in the normal app sandbox.
4. The SR-750 default remote FTP directory is `image`; Exalted accepts it as a virtual directory and stores the uploaded file in managed media storage.
5. Configure image saving/FTP on the reader and test a real upload. A running listener alone does not prove that the scanner can authenticate or transfer an image.
6. Exalted currently pairs barcode and image arrivals by a time window; it does not yet have a verified device transaction ID. Do not treat that pairing as production traceability proof.

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
