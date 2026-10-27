# CampusScan — Smart Student Barcode Registration System

**CampusScan** is a responsive web application designed for colleges and universities to register students by scanning the barcode on their college ID cards. It features real-time camera barcode scanning, photo and name verification, an administrator portal with analytics, CSV/Excel import/export, and **uncompromising duplicate registration prevention** enforced at both the browser and database levels.

---

## Table of Contents

1. [Features](#features)
2. [Technology Stack](#technology-stack)
3. [Project Structure](#project-structure)
4. [Beginner-Friendly Setup Guide (Windows & VS Code)](#beginner-friendly-setup-guide-windows--vs-code)
   - [Step 1: Install Python and VS Code](#step-1-install-python-and-vs-code)
   - [Step 2: Open the Project in VS Code](#step-2-open-the-project-in-vs-code)
   - [Step 3: Create a Python Virtual Environment](#step-3-create-a-python-virtual-environment)
   - [Step 4: Activate the Virtual Environment in PowerShell](#step-4-activate-the-virtual-environment-in-powershell)
   - [Step 5: Install Project Dependencies](#step-5-install-project-dependencies)
   - [Step 6: Start the Flask Server](#step-6-start-the-flask-server)
   - [Step 7: Open the Application in your Browser](#step-7-open-the-application-in-your-browser)
5. [How to Use CampusScan](#how-to-use-campuss-scan)
   - [Scanning a Barcode with Camera](#scanning-a-barcode-with-camera)
   - [Testing with Quick Test Chips or Manual Roll Number](#testing-with-quick-test-chips-or-manual-roll-number)
   - [Testing the Duplicate Registration Warning](#testing-the-duplicate-registration-warning)
   - [Managing Student Records (Manual & CSV/Excel Import)](#managing-student-records-manual--csvexcel-import)
   - [Adding Student Photographs](#adding-student-photographs)
   - [Using the Admin Dashboard & CSV Export](#using-the-admin-dashboard--csv-export)
6. [Mobile Phone Access & Wi-Fi Setup](#mobile-phone-access--wi-fi-setup)
   - [Accessing via Local Wi-Fi](#accessing-via-local-wi-fi)
   - [Why Mobile Cameras Require HTTPS (and How to Run with SSL)](#why-mobile-cameras-require-https-and-how-to-run-with-ssl)
   - [Shared Database Architecture](#shared-database-architecture)
7. [Automated Testing Suite](#automated-testing-suite)
8. [Troubleshooting & Common Errors](#troubleshooting--common-errors)

---

## Features

- **High-Performance Camera Barcode Scanner**: Scans Code 128, Code 39, QR Codes, and other common formats directly in modern web browsers using the local ZXing library.
- **Audio Feedback**: Subtle, pleasant audio chimes on successful registration and distinct warning tones on duplicate or unknown barcodes.
- **Strict Duplicate Registration Prevention**:
  - **Database Level**: `student_id` is a `UNIQUE` primary key constraint in SQLite with `WAL` journaling mode and `BEGIN IMMEDIATE` transaction locking to guarantee single registration even under heavy concurrent requests.
  - **Frontend Level**: Instant warning popup modal displaying the student's name, ID, photograph, and original registration timestamp, with the register button permanently locked.
- **Master Student Database Integrity**: Unknown scanned barcodes prompt the administrator to add the student record first; incomplete records are never automatically created.
- **Multiple Data Ingestion Methods**:
  - Flexible CSV / Excel (.xlsx, .xls) import with automatic column header detection (`student_id`, `roll_no`, `name`, etc.).
  - Preserves existing registration timestamps during imports.
  - Automatic photo matching from `data/students/<STUDENT_ID>.<ext>`.
  - Manual student entry form with optional direct photo upload.
- **Professional Admin Dashboard**:
  - Live KPI cards: Total Students, Total Registered, Pending, and Completion Rate.
  - Live instant search and status filtering (All, Registered, Pending).
  - One-click CSV export of attendance/registration reports.
- **Security & Authentication**:
  - Session-based admin portal with PBKDF2 password hashing.
  - Protected administrative endpoints and safe file serving (prevents directory traversal).

---

## Technology Stack

- **Backend**: Python 3.10+ / Flask 3.x
- **Database**: SQLite3 (with WAL mode, foreign keys, and atomic transactions)
- **Frontend**: HTML5, Vanilla CSS3 (Custom Design System with Inter typography), JavaScript (ES6+)
- **Barcode Engine**: ZXing Browser Library (vendored locally in `static/js/zxing.min.js` for offline reliability)
- **Data Processing**: pandas & openpyxl
- **Image Processing**: Pillow

---

## Project Structure

```
club project 1/
├── app.py                      # Core Flask backend and REST API routes
├── generate_sample_data.py     # Utility to generate sample students, photos & spreadsheets
├── test_live_server.py         # End-to-end integration test against running server
├── requirements.txt            # Python dependencies
├── README.md                   # Complete documentation and setup manual
├── .env.example                # Environment variables template
├── .gitignore                  # Git exclusions (venv, temp files, secrets)
├── data/
│   ├── students.db             # SQLite database (auto-created with schema)
│   ├── students/               # Student photo storage (e.g., 23CS001.jpg)
│   └── uploads/                # Temporary directory for spreadsheet uploads
├── static/
│   ├── css/
│   │   └── style.css           # Modern, responsive CSS design system
│   ├── js/
│   │   ├── zxing.min.js        # Vendored ZXing barcode scanning engine
│   │   ├── scanner.js          # Camera controls, audio cues & duplicate modal handler
│   │   └── dashboard.js        # Live search, status filter & table controls
│   └── images/
│       ├── default-profile.svg # Sleek SVG placeholder avatar
│       └── logo.svg            # CampusScan logo badge
├── templates/
│   ├── base.html               # Master layout with responsive navbar & flash alerts
│   ├── index.html              # Barcode scanner, manual lookup & duplicate warning popup
│   ├── login.html              # Admin login interface
│   ├── records.html            # Student records catalog & CSV/Excel upload
│   └── dashboard.html          # Registration analytics & CSV export
├── tests/
│   ├── __init__.py
│   ├── test_students.py        # Student creation, duplicate ID & CSV tests
│   └── test_registration.py    # Registration, duplicate prevention & concurrency tests
└── sample_data/
    ├── sample_students.csv     # Ready-to-use sample student CSV
    ├── sample_students.xlsx    # Ready-to-use sample student Excel workbook
    └── photos/                 # Sample student ID photos for instant testing
```

---

## Beginner-Friendly Setup Guide (Windows & VS Code)

Follow these exact steps in **Windows PowerShell**.

### Step 1: Install Python and VS Code
1. If Python is not yet installed on your PC, download Python 3.12 or newer from [python.org](https://www.python.org/downloads/) and ensure you check the box **"Add python.exe to PATH"** during installation.
2. Download and install **Visual Studio Code** from [code.visualstudio.com](https://code.visualstudio.com/).

### Step 2: Open the Project in VS Code
1. Launch VS Code.
2. Go to **File** > **Open Folder...** and select this project directory:
   ```
   C:\Users\sadhana\New folder\club project 1
   ```
3. Open a new terminal by pressing ``Ctrl + ` `` (backtick) or choosing **Terminal** > **New Terminal**.

### Step 3: Create a Python Virtual Environment
In the VS Code PowerShell terminal, run:
```powershell
python -m venv .venv
```
*(If you have `uv` installed, you can also use `uv venv .venv`).*

### Step 4: Activate the Virtual Environment in PowerShell
Run the following command to activate your virtual environment:
```powershell
.\.venv\Scripts\Activate.ps1
```
> **Tip for Windows execution policy:** If PowerShell displays an execution policy error, run this once:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```
> Then re-run `.\.venv\Scripts\Activate.ps1`. When activated, `(.venv)` will appear at the start of your terminal prompt.

### Step 5: Install Project Dependencies
Install all required packages from `requirements.txt`:
```powershell
pip install -r requirements.txt
```

### Step 6: Start the Flask Server
Start the CampusScan application:
```powershell
python app.py
```

You will see:
```text
=======================================================
 CampusScan — Smart Student Barcode Registration System
 Server running at: http://127.0.0.1:5000
 Default Admin: 'admin' | Password: 'admin123'
=======================================================
```

### Step 7: Open the Application in your Browser
Open your browser (Google Chrome, Microsoft Edge, or Firefox) and navigate to:
```
http://127.0.0.1:5000/
```

---

## How to Use CampusScan

### Scanning a Barcode with Camera
1. Click **Start Camera** on the main page.
2. Grant camera permission when prompted by your browser.
3. Hold a student ID card with a barcode (Code 128, Code 39, QR Code) up to your camera.
4. The targeting reticle will detect the barcode and play a chime.
5. The student's photograph, full name, and roll number will appear in the verification panel.
6. Click **Confirm & Register Student** to complete registration.

### Testing with Quick Test Chips or Manual Roll Number
No physical barcode handy? No problem!
- Under **Manual Student Lookup**, click any of the pre-configured quick test chips:
  - `23CS001` (Aarav Sharma)
  - `23CS002` (Diya Patel)
  - `23CS003` (Rohan Verma)
  - `23CS004` (Sneha Reddy)
- Or type any ID and press **Enter** / click **Search**.

### Testing the Duplicate Registration Warning
This is the core anti-fraud feature of CampusScan:
1. Scan or click `23CS001` and click **Confirm & Register Student**.
2. Notice the green **"Registration Successful!"** popup showing the registration timestamp.
3. Close the modal or click **Scan Next Student**.
4. Now, scan or enter `23CS001` **a second time**.
5. **Immediately**, the system triggers the amber warning popup:
   > ⚠️ **"You have already registered!"**
   - Displays the student's name, ID, and photograph.
   - Shows the exact date & time when the student registered earlier.
   - The Register button is permanently locked to prevent duplicates.
   - Click **Scan Another Student** to resume scanning.

### Managing Student Records (Manual & CSV/Excel Import)
1. In the navigation bar, click **Admin Login**.
2. Enter username `admin` and password `admin123`.
3. Click **Student Records** in the navigation bar.
4. **Manual Entry**: Fill in the Student ID and Full Name, attach an optional photograph, and click **Save Student Record**.
5. **Spreadsheet Bulk Import**:
   - Click **Choose Spreadsheet File** and select `sample_data/sample_students.csv` or any `.xlsx` file.
   - Click **Upload & Import**.
   - The system validates columns, adds new students, updates names, skips invalid rows, and calculates photo coverage.
   - **Crucial Note:** Re-importing a roster **never wipes or resets existing registration timestamps**.

### Adding Student Photographs
CampusScan supports two ways to link student photos:
1. **Filename Matching (Recommended for bulk photos)**:
   Place photos inside the `data/students/` directory named with their unique student ID:
   ```
   data/students/23CS001.jpg
   data/students/23CS002.png
   data/students/23CS003.jpeg
   data/students/23CS004.webp
   ```
   The application matches them case-insensitively and serves them securely.
2. **Web Upload**:
   Upload photos individually using the **Add Student** form in the Admin Records page.

### Using the Admin Dashboard & CSV Export
1. Navigate to **Dashboard** (`/dashboard`).
2. View real-time statistics: Total Students, Total Registered, Pending, and Completion Rate.
3. Use the search bar to filter students by name or roll number in real-time.
4. Click **Export to CSV** to download `campus_scan_report_<timestamp>.csv` for official college reporting.

---

## Mobile Phone Access & Wi-Fi Setup

CampusScan works directly in mobile browsers without requiring separate Android or iOS native apps.

### Accessing via Local Wi-Fi
To scan student ID cards using smartphone cameras:
1. Ensure your laptop/PC and your smartphone are connected to the **same Wi-Fi network**.
2. Find your computer's local IP address (the Flask server prints it upon starting, e.g. `http://10.62.245.2:5000` or `http://192.168.1.X:5000`).
   - You can also check your IP in PowerShell using:
     ```powershell
     ipconfig
     ```
     Look for the **IPv4 Address** under your Wireless LAN adapter.
3. On your smartphone, open Chrome or Safari and navigate to:
   ```
   http://<YOUR-IP-ADDRESS>:5000
   ```

### Why Mobile Cameras Require HTTPS (and How to Run with SSL)
For user privacy and security, modern smartphone browsers (Chrome for Android, iOS Safari) **block camera access on non-localhost HTTP connections**.

To enable camera access on mobile over Wi-Fi, run the Flask server with SSL:

#### Option A: Ad-Hoc SSL Certificate (Fastest)
Install `cryptography` and run Flask with an ad-hoc certificate:
```powershell
pip install cryptography
flask run --host=0.0.0.0 --port=5000 --cert=adhoc
```
On your mobile phone, open `https://<YOUR-IP-ADDRESS>:5000`. Your browser will show a self-signed certificate warning; tap **Advanced** > **Proceed to site** to grant camera access.

#### Option B: Port Forwarding / Ngrok (For Remote Scanning)
If scanning from cellular networks or different Wi-Fi networks:
```powershell
# Using ngrok to provide a secure public HTTPS tunnel
ngrok http 5000
```
Open the generated `https://xxxx.ngrok-free.app` URL on any mobile device.

### Shared Database Architecture
All connected devices (laptops, multiple staff smartphones scanning at different college entry gates) connect to the **same central Flask server and shared SQLite database**.
- When Smartphone A scans student `23CS001`, the registration is committed with a database transaction.
- If Smartphone B attempts to scan student `23CS001` one second later, it will immediately receive the duplicate warning.
- *Note on Scaling:* SQLite with WAL mode easily handles small-to-medium deployments (dozens of concurrent scanners). For high-volume campus setups with hundreds of simultaneous scanners across campuses, PostgreSQL can be connected simply by changing the database connection string.

---

## Automated Testing Suite

CampusScan includes 13 automated unit, integration, and concurrency tests:

1. Adding a new student
2. Rejecting duplicate student IDs in the master student table
3. Successfully registering an eligible student
4. Rejecting a second registration attempt with HTTP 409 Conflict
5. Verifying duplicate warning message content and timestamp display
6. Returning clear 404 error for unknown student IDs without auto-creating incomplete profiles
7. Bulk importing student data from CSV
8. Rejecting invalid spreadsheets with missing required headers
9. Preserving registration timestamps during student roster re-imports
10. Case-insensitive photo matching by filename
11. Protecting administrator routes against unauthenticated access
12. **Concurrent Registration Race Condition Handling**: 10 simultaneous threads attempting to register the same student concurrently; verifies that **exactly one** succeeds and all 9 receive 409 Conflict.
13. End-to-end live HTTP server integration testing.

To run the full test suite:
```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py" -v
```

To run the live HTTP server integration test (while `python app.py` is running):
```powershell
.\.venv\Scripts\python.exe test_live_server.py
```

---

## Troubleshooting & Common Errors

| Issue | Cause | Solution |
|---|---|---|
| `Camera permission was denied` | Browser blocked webcam/phone camera | Click the lock/settings icon in your browser address bar and set Camera to **Allow**. |
| `Mobile camera does not start on Wi-Fi` | Mobile browsers require HTTPS outside localhost | Start Flask with `--cert=adhoc` or use an HTTPS tunnel (see [Mobile Phone Access](#why-mobile-cameras-require-https-and-how-to-run-with-ssl)). |
| `Student not found` warning popup | Scanned ID is not in the student catalog | Add the student via **Student Records** or import the class CSV/Excel file before registering. |
| `Port 5000 is already in use` | Another program is using port 5000 | Set an alternative port in PowerShell: `$env:PORT=5050; python app.py` |
| `Script execution is disabled on this system` | Windows PowerShell execution policy | Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` in PowerShell. |
| `Missing required columns` when importing CSV | Column names do not match expected aliases | Ensure your spreadsheet has at least one ID column (`student_id`, `roll_no`, `roll_number`, `register_number`) and one Name column (`name`, `student_name`). |
