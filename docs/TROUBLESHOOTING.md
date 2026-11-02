# Exalted Industrial Machine Vision — Troubleshooting Guide

Version: 1.0.0  
Product: Exalted (MatrixScan)

---

## 1. Hardware & Network Connectivity Issues

### Issue 1.1: Unable to Connect to Keyence SR-751 (Connection Refused / Timeout)
- **Symptom**: Exalted reports `Connection timed out` or status remains `DISCONNECTED`.
- **Causes & Resolutions**:
  1. **IP Subnet Mismatch**: Verify that both the host PC and Keyence reader are on the same subnet (e.g., PC on `192.168.100.10`, Reader on `192.168.100.100`, Subnet mask `255.255.255.0`).
  2. **Firewall Blocking TCP Port 9004**:
     - *Linux*: Run `sudo ufw allow 9004/tcp`
     - *Windows*: Add an inbound rule in Windows Defender Firewall for TCP port 9004.
  3. **Multiple Network Adapters**: If the PC has both Wi-Fi and Ethernet active, ensure routing sends traffic destined for `192.168.100.0/24` out the Ethernet interface.

---

### Issue 1.2: Keyence Decodes Successfully, but No Image Appears in Exalted
- **Symptom**: The barcode string is received over TCP, but the CMOS image is not updated.
- **Causes & Resolutions**:
  1. **FTP Port 2121 Blocked**: Verify that the Exalted embedded FTP server is running and port 2121 is open in the OS firewall.
     - *Linux test*: `nc -zv 127.0.0.1 2121`
  2. **Reader FTP Server IP Mismatch**: In Keyence AutoID Navigator, ensure the FTP Server destination IP is set to the host PC's exact Ethernet IP address, not `127.0.0.1` or the gateway.
  3. **Passive Mode (PASV) Port Range**: When in passive mode, the embedded FTP server dynamically assigns a data port. Ensure local traffic on the interface is not restricted by local packet filtering.

---

## 2. Barcode & 2D Code Decoding Issues

### Issue 2.1: Dot-Peen Data Matrix on Cast/Machined Metal Not Reading
- **Symptom**: Standard camera reads paper barcodes, but fails to read dot-peen marks on metal surfaces.
- **Root Cause**: Dot-peen markings consist of indented dots without connected lines. Surface glare, milling marks, and oil create noise.
- **Resolutions**:
  1. **Enable Dot-Peen Morphological Rank Filter**:
     - In the C++20 engine, dot-peen filtering combines morphological dilation and rank filtering to bridge individual dots into solid matrix modules.
     - In Settings > Decoder Engine, ensure **Dot-Peen Enhancement** is set to **Enabled**.
  2. **Adjust Lighting Angle**: Use low-angle darkfield illumination to cast shadows in the dot indentations while deflecting specular reflection away from the lens.
  3. **High-Effort Mode (`tryHarder`)**: Ensure `tryHarder = true` is active (enabled by default for image file and high-resolution inspection).

---

### Issue 2.2: Damaged Quiet Zone
- **Symptom**: The barcode is clearly visible to the human eye, but the decoder does not locate it.
- **Resolution**: Data Matrix requires a minimum quiet zone of 1 module width surrounding the entire symbol. If printed text or product edges infringe on the quiet zone, use the **OCR / OCV Workspace ROI Cropping tool** to isolate the symbol from neighboring text before decoding.

---

## 3. OCR & OCV Verification Issues

### Issue 3.1: OCR Engine Fails with "Tesseract Not Available"
- **Symptom**: OCR workspace displays `Tesseract executable not found or failed to execute`.
- **Causes & Resolutions**:
  - *Linux*: Verify Tesseract is installed:
    ```bash
    sudo apt update && sudo apt install tesseract-ocr tesseract-ocr-eng libtesseract5
    which tesseract  # should return /usr/bin/tesseract
    ```
  - *Windows*: Ensure Tesseract is installed and its folder (e.g. `C:\Program Files\Tesseract-OCR`) is present in the system `PATH`, or placed in Exalted's application directory.
  - *Language Packs*: Ensure traineddata models exist in `/usr/share/tesseract-ocr/5/tessdata/` (Linux) or `tessdata/` (Windows).

---

### Issue 3.2: OCV Evaluation Returns INCONCLUSIVE
- **Symptom**: OCR recognized characters, but the OCV verdict shows amber `INCONCLUSIVE`.
- **Causes & Resolutions**:
  1. **Confidence Below Threshold**: By default, Exalted requires a minimum confidence score (e.g., $\ge 60\%$) to declare a definitive PASS or FAIL. If lighting was uneven or the image blurred, confidence drops below the threshold.
  2. **Recipe Threshold Adjustment**: In the OCV Recipe settings, the required confidence threshold can be adjusted to match line conditions (e.g., lowered to 45% for high-speed dot-matrix inkjet markings).

---

### Issue 3.3: Expiration Date Evaluation Fails Incorrectly
- **Symptom**: The expiration date `EXP: 2027-10-15` fails evaluation.
- **Resolutions**:
  1. **Date Format Matching**: Ensure the rule's date pattern matches the print layout (e.g. `YYYY-MM-DD` vs `DD/MM/YYYY` vs `MM/YY`).
  2. **System Clock Drift**: Exalted calculates whether the date has expired against the host system clock. Ensure the host PC time and timezone are NTP-synchronized.

---

## 4. Database, Image Storage & Backup

### Issue 4.1: Missing Images in History
- **Symptom**: The history entry exists, but clicking details displays `Image file missing`.
- **Resolution**:
  - Images are saved in permanent application storage (`<app_data>/exalted_images/`).
  - Do not manually empty or delete files in this directory.
  - Run **System Settings > Storage & Integrity > Validate Image Integrity** to scan the database and verify that all referenced image files exist on disk.

---

### Issue 4.2: Restoring from Backup Fails
- **Symptom**: The backup restore process returns an error or fails validation.
- **Resolution**:
  - Ensure the backup archive was produced by Exalted (`.exalted-backup` or JSON export format).
  - Check file permissions to ensure Exalted has write access to the target database and settings directory.
