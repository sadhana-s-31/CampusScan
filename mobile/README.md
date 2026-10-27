# CampusScan — Mobile Application (Flutter)

This is the dedicated mobile app companion for **CampusScan**. It connects directly to your central Flask backend to scan student ID barcodes with your phone's camera, display student profiles with photos, and enforce **real-time duplicate prevention**.

---

## 1. Prerequisites & Dependencies

In your Flutter project's `pubspec.yaml` (e.g. in `c:\Users\sadhana\OneDrive\Documents\flutter_application_1\pubspec.yaml`), make sure you have:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  simple_barcode_scanner: ^0.1.2
```

Then run in your Flutter terminal:
```bash
flutter pub get
```

---

## 2. Platform Permissions (Camera & Internet)

### Android (`android/app/src/main/AndroidManifest.xml`)
Ensure the following permissions are present inside the `<manifest>` tag:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```
*(Optional for Android 9+ HTTP traffic on local IP)*:
In `<application>` tag, add `android:usesCleartextTraffic="true"`:
```xml
<application
    ...
    android:usesCleartextTraffic="true">
```

### iOS (`ios/Runner/Info.plist`)
Add the camera usage description inside `<dict>`:
```xml
<key>NSCameraUsageDescription</key>
<string>CampusScan needs camera access to scan student ID card barcodes.</string>
```

---

## 3. Server Connection Settings

The mobile app connects to the central Flask backend running on your computer.

1. **Physical Phone (via Wi-Fi)**:
   - Ensure your phone and laptop are on the same Wi-Fi network.
   - Your computer's current Wi-Fi IP address is **`http://10.246.225.105:5000`**.
   - You can also change the IP inside the app at any time by tapping the ⚙️ **Settings icon** in the top-right corner.

2. **Android Emulator**:
   - Tap the ⚙️ **Settings icon** in the app and set the URL to:
     ```
     http://10.0.2.2:5000
     ```
     *(Android emulator routes `10.0.2.2` to your computer's `localhost`).*

---

## 4. Mobile Workflow Features

1. **Scan Student ID**:
   - Tap **"Open Camera Scanner"**.
   - Aim camera at the barcode on the student's ID card.
2. **Instant Verification**:
   - The app contacts `GET /api/students/<ID>` on the Flask server.
   - Displays student name, roll number, and student photograph.
3. **Registering Eligible Student**:
   - Tap **"Confirm & Register Student"**.
   - Submits `POST /api/register` with database transaction locking.
   - Shows green checkmark with registration timestamp.
4. **Duplicate Registration Prevention**:
   - If the student was already registered earlier, the app **immediately pops up**:
     > ⚠️ **"You have already registered!"**
     - Shows the student's photo, name, and previous registration timestamp.
     - Locks the registration button.
     - Lets you tap **"Scan Another Student"** to continue.
5. **Unknown Barcode Handling**:
   - If an unknown barcode is scanned, alerts: *"Student not found. Please add the student record before registering."*
