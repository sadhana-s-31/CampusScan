/**
 * CampusScan — Scanner & Registration Controller
 * Handles camera barcode reading via ZXing, sound cues, API requests,
 * and duplicate registration modal alerts.
 */

let codeReader = null;
let currentCameraDeviceId = null;
let availableVideoDevices = [];
let isScanning = false;
let isProcessing = false;
let activeStudent = null;

// Audio Context for instant feedback without external audio files
let audioCtx = null;

function getAudioContext() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
    }
  }
  if (audioCtx && audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
  return audioCtx;
}

function playBeep(type = 'success') {
  try {
    const ctx = getAudioContext();
    if (!ctx) return;

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);

    const now = ctx.currentTime;

    if (type === 'success') {
      // Pleasant high double beep
      osc.type = 'sine';
      osc.frequency.setValueAtTime(880, now);
      osc.frequency.setValueAtTime(1174.66, now + 0.08); // High D
      gain.gain.setValueAtTime(0.2, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.25);
      osc.start(now);
      osc.stop(now + 0.25);
    } else if (type === 'duplicate') {
      // Low warning tone
      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(320, now);
      osc.frequency.setValueAtTime(240, now + 0.12);
      gain.gain.setValueAtTime(0.25, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.35);
      osc.start(now);
      osc.stop(now + 0.35);
    } else if (type === 'error') {
      // Error buzz
      osc.type = 'square';
      osc.frequency.setValueAtTime(200, now);
      gain.gain.setValueAtTime(0.2, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.3);
      osc.start(now);
      osc.stop(now + 0.3);
    }
  } catch (err) {
    console.warn("Audio playback not permitted or supported:", err);
  }
}

// Initialize on DOM load
document.addEventListener('DOMContentLoaded', () => {
  initBarcodeScanner();

  // Attach button listeners
  const btnToggle = document.getElementById('btn-toggle-camera');
  const btnStart = document.getElementById('btn-start-camera');
  const btnSwitch = document.getElementById('btn-switch-camera');
  const btnReset = document.getElementById('btn-reset-scanner');

  if (btnToggle) btnToggle.addEventListener('click', toggleCamera);
  if (btnStart) btnStart.addEventListener('click', startCamera);
  if (btnSwitch) btnSwitch.addEventListener('click', switchCamera);
  if (btnReset) btnReset.addEventListener('click', resetVerification);

  // Focus manual input on start
  const manualInput = document.getElementById('manual-student-id');
  if (manualInput) {
    manualInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        handleManualLookup();
      }
    });
  }
});

/**
 * Initialize ZXing MultiFormat Reader
 */
function initBarcodeScanner() {
  if (typeof ZXing === 'undefined') {
    console.error("ZXing library not found!");
    showCameraError("Barcode scanning engine failed to load. Please check your internet or local file.");
    return;
  }

  codeReader = new ZXing.BrowserMultiFormatReader();
}

/**
 * Start or stop camera based on state
 */
function toggleCamera() {
  if (isScanning) {
    stopCamera();
  } else {
    startCamera();
  }
}

/**
 * Start camera feed and begin continuous decoding
 */
async function startCamera() {
  if (!codeReader) initBarcodeScanner();
  hideCameraError();

  const videoElement = document.getElementById('scanner-video');
  const placeholder = document.getElementById('scanner-placeholder');
  const viewfinder = document.getElementById('viewfinder-container');
  const btnText = document.getElementById('camera-btn-text');
  const statusPill = document.getElementById('status-pill');

  try {
    // List available video inputs
    availableVideoDevices = await codeReader.listVideoInputDevices();

    if (!availableVideoDevices || availableVideoDevices.length === 0) {
      showCameraError("No video cameras found on this device.");
      return;
    }

    // Select rear camera by default on mobile if not already chosen
    if (!currentCameraDeviceId) {
      const rearCamera = availableVideoDevices.find(device => 
        /back|rear|environment|facing back/i.test(device.label)
      );
      currentCameraDeviceId = rearCamera ? rearCamera.deviceId : availableVideoDevices[0].deviceId;
    }

    // Update UI state
    isScanning = true;
    if (placeholder) placeholder.style.display = 'none';
    if (viewfinder) viewfinder.classList.add('scanning');
    if (btnText) btnText.textContent = 'Stop Camera';
    if (statusPill) {
      statusPill.className = 'badge badge-registered';
      statusPill.textContent = '● Camera Active';
    }

    // Begin decode loop
    codeReader.decodeFromVideoDevice(currentCameraDeviceId, videoElement, (result, err) => {
      if (result) {
        onBarcodeDetected(result.getText());
      }
      if (err && !(err instanceof ZXing.NotFoundException)) {
        // Continuous non-critical scan errors are normal while waiting for barcodes
      }
    });

  } catch (err) {
    console.error("Camera start error:", err);
    stopCamera();

    let msg = "Unable to access camera: " + (err.message || err.name);
    if (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError') {
      msg = "Camera permission was denied. Please allow camera access in your browser settings.";
    } else if (err.name === 'NotFoundError') {
      msg = "No suitable camera device found.";
    } else if (location.protocol !== 'https:' && location.hostname !== 'localhost' && location.hostname !== '127.0.0.1') {
      msg = "Mobile browsers require HTTPS to enable camera permissions. Please access via localhost or configure HTTPS.";
    }
    showCameraError(msg);
  }
}

/**
 * Stop active camera stream
 */
function stopCamera() {
  if (codeReader) {
    codeReader.reset();
  }
  isScanning = false;

  const placeholder = document.getElementById('scanner-placeholder');
  const viewfinder = document.getElementById('viewfinder-container');
  const btnText = document.getElementById('camera-btn-text');
  const statusPill = document.getElementById('status-pill');

  if (placeholder) placeholder.style.display = 'block';
  if (viewfinder) viewfinder.classList.remove('scanning');
  if (btnText) btnText.textContent = 'Start Camera';
  if (statusPill) {
    statusPill.className = 'badge badge-unregistered';
    statusPill.textContent = '● Camera Idle';
  }
}

/**
 * Switch camera (e.g. front / back)
 */
async function switchCamera() {
  if (!availableVideoDevices || availableVideoDevices.length <= 1) {
    // Refresh device list
    if (codeReader) {
      availableVideoDevices = await codeReader.listVideoInputDevices();
    }
  }

  if (availableVideoDevices.length <= 1) {
    alert("Only one camera device is available on this system.");
    return;
  }

  // Find next device
  const currentIndex = availableVideoDevices.findIndex(d => d.deviceId === currentCameraDeviceId);
  const nextIndex = (currentIndex + 1) % availableVideoDevices.length;
  currentCameraDeviceId = availableVideoDevices[nextIndex].deviceId;

  if (isScanning) {
    stopCamera();
    setTimeout(() => startCamera(), 300);
  }
}

/**
 * Handle Barcode Read
 * Prevents multiple concurrent API hits using a cooldown lock.
 */
function onBarcodeDetected(scannedText) {
  if (!scannedText || isProcessing) return;

  const cleanId = scannedText.trim().toUpperCase();
  if (!cleanId) return;

  console.log(`[CampusScan] Barcode Scanned: ${cleanId}`);

  // Lock scanner to avoid repeated triggers
  isProcessing = true;

  // Set in manual input field for visual feedback
  const manualInput = document.getElementById('manual-student-id');
  if (manualInput) manualInput.value = cleanId;

  // Query Student API
  lookupStudent(cleanId);
}

/**
 * Manual lookup handler from form submit
 */
function handleManualLookup() {
  const manualInput = document.getElementById('manual-student-id');
  if (!manualInput) return;

  const studentId = manualInput.value.trim().toUpperCase();
  if (!studentId) {
    alert("Please enter a student ID or roll number.");
    manualInput.focus();
    return;
  }

  lookupStudent(studentId);
}

/**
 * Quick fill helper for test chips
 */
function quickFill(id) {
  const input = document.getElementById('manual-student-id');
  if (input) {
    input.value = id;
    lookupStudent(id);
  }
}

/**
 * Query Backend for Student Information & Registration Status
 */
async function lookupStudent(studentId) {
  setProfileLoadingState(true, studentId);

  try {
    const response = await fetch(`/api/students/${encodeURIComponent(studentId)}`);
    const data = await response.json();

    setProfileLoadingState(false);

    if (response.status === 404 || data.status === 'not_found') {
      // 1. Unknown Student
      playBeep('error');
      showNotFoundModal(studentId, data.message);
      return;
    }

    if (!data.success) {
      alert(data.message || "Failed to search student record.");
      return;
    }

    activeStudent = data.student;

    if (data.status === 'already_registered') {
      // 2. Duplicate Registration Detected! (STRICT REQUIREMENT)
      playBeep('duplicate');
      renderStudentProfile(data.student, 'registered', data.registration);
      showDuplicateModal(data.student, data.registration);
    } else {
      // 3. Eligible for Registration
      playBeep('success');
      renderStudentProfile(data.student, 'eligible');
    }

  } catch (err) {
    console.error("Lookup error:", err);
    setProfileLoadingState(false);
    alert("Network or server error while searching for student.");
  } finally {
    // Cooldown lock release
    setTimeout(() => {
      isProcessing = false;
    }, 1500);
  }
}

/**
 * Render Student Profile Card in Verification Column
 */
function renderStudentProfile(student, status, registration = null) {
  const photoEl = document.getElementById('student-photo');
  const nameEl = document.getElementById('student-name');
  const idEl = document.getElementById('student-id-display');
  const badgeEl = document.getElementById('profile-status-badge');
  const statusMsgEl = document.getElementById('student-status-message');
  const registerBtn = document.getElementById('btn-register-student');
  const scanAnotherBtn = document.getElementById('btn-scan-another');

  if (photoEl) photoEl.src = student.photo_url || '/static/images/default-profile.svg';
  if (nameEl) nameEl.textContent = student.name;
  if (idEl) idEl.textContent = student.student_id;

  if (status === 'registered') {
    badgeEl.className = 'badge badge-warning';
    badgeEl.textContent = 'Already Registered';
    statusMsgEl.innerHTML = `⚠️ <strong>Registered on:</strong> ${registration ? registration.registered_at : 'Earlier'}`;
    statusMsgEl.style.color = 'var(--warning-text)';
    
    registerBtn.style.display = 'none';
    scanAnotherBtn.style.display = 'block';
  } else {
    badgeEl.className = 'badge badge-registered';
    badgeEl.textContent = 'Eligible to Register';
    statusMsgEl.textContent = 'Student verified in database. Click below to complete registration.';
    statusMsgEl.style.color = 'var(--success-text)';

    registerBtn.style.display = 'block';
    registerBtn.disabled = false;
    registerBtn.innerHTML = `<span>✓</span> Confirm & Register (${student.student_id})`;
    scanAnotherBtn.style.display = 'block';
  }
}

/**
 * Submit Registration to Backend
 */
async function executeRegistration() {
  if (!activeStudent || !activeStudent.student_id) {
    alert("No eligible student selected for registration.");
    return;
  }

  const registerBtn = document.getElementById('btn-register-student');
  if (registerBtn) {
    registerBtn.disabled = true;
    registerBtn.innerHTML = `<span class="spinner"></span> Registering...`;
  }

  try {
    const response = await fetch('/api/register', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        student_id: activeStudent.student_id,
        registered_by: 'camera_scanner'
      })
    });

    const data = await response.json();

    if (response.status === 201 && data.success) {
      // Successful registration!
      playBeep('success');
      showSuccessModal(data.student, data.registration);
      renderStudentProfile(data.student, 'registered', data.registration);
    } else if (response.status === 409 || data.status === 'already_registered') {
      // Backend caught duplicate!
      playBeep('duplicate');
      showDuplicateModal(data.student || activeStudent, data.registration);
      renderStudentProfile(data.student || activeStudent, 'registered', data.registration);
    } else {
      alert(data.message || "Registration failed.");
      if (registerBtn) registerBtn.disabled = false;
    }

  } catch (err) {
    console.error("Registration request error:", err);
    alert("Server error during registration.");
    if (registerBtn) registerBtn.disabled = false;
  }
}

/**
 * Display Duplicate Registration Warning Modal
 */
function showDuplicateModal(student, registration) {
  const modal = document.getElementById('duplicate-modal');
  const nameEl = document.getElementById('dup-modal-name');
  const idEl = document.getElementById('dup-modal-id');
  const photoEl = document.getElementById('dup-modal-photo');
  const timeEl = document.getElementById('dup-modal-timestamp');

  if (nameEl) nameEl.textContent = student.name;
  if (idEl) idEl.textContent = `ID: ${student.student_id}`;
  if (photoEl) photoEl.src = student.photo_url || '/static/images/default-profile.svg';
  if (timeEl) timeEl.textContent = registration && registration.registered_at ? registration.registered_at : 'Previously recorded';

  if (modal) modal.classList.add('show');
}

function closeDuplicateModal() {
  const modal = document.getElementById('duplicate-modal');
  if (modal) modal.classList.remove('show');
  resetVerification();
}

/**
 * Display Registration Success Modal
 */
function showSuccessModal(student, registration) {
  const modal = document.getElementById('success-modal');
  const nameEl = document.getElementById('success-modal-name');
  const idEl = document.getElementById('success-modal-id');
  const photoEl = document.getElementById('success-modal-photo');
  const timeEl = document.getElementById('success-modal-timestamp');

  if (nameEl) nameEl.textContent = student.name;
  if (idEl) idEl.textContent = `ID: ${student.student_id}`;
  if (photoEl) photoEl.src = student.photo_url || '/static/images/default-profile.svg';
  if (timeEl) timeEl.textContent = registration ? registration.registered_at : new Date().toLocaleString();

  if (modal) modal.classList.add('show');
}

function closeSuccessModal() {
  const modal = document.getElementById('success-modal');
  if (modal) modal.classList.remove('show');
  resetVerification();
}

/**
 * Display Student Not Found Warning Modal
 */
function showNotFoundModal(studentId, message) {
  const modal = document.getElementById('notfound-modal');
  const idEl = document.getElementById('notfound-id');
  const msgEl = document.getElementById('notfound-message');

  if (idEl) idEl.textContent = studentId;
  if (msgEl && message) msgEl.textContent = message;

  if (modal) modal.classList.add('show');
}

function closeNotFoundModal() {
  const modal = document.getElementById('notfound-modal');
  if (modal) modal.classList.remove('show');
  resetVerification();
}

/**
 * Reset verification panel for next student
 */
function resetVerification() {
  activeStudent = null;
  isProcessing = false;

  const photoEl = document.getElementById('student-photo');
  const nameEl = document.getElementById('student-name');
  const idEl = document.getElementById('student-id-display');
  const badgeEl = document.getElementById('profile-status-badge');
  const statusMsgEl = document.getElementById('student-status-message');
  const registerBtn = document.getElementById('btn-register-student');
  const scanAnotherBtn = document.getElementById('btn-scan-another');
  const manualInput = document.getElementById('manual-student-id');

  if (photoEl) photoEl.src = '/static/images/default-profile.svg';
  if (nameEl) nameEl.textContent = 'No Student Scanned';
  if (idEl) idEl.textContent = '—';
  if (badgeEl) {
    badgeEl.className = 'badge badge-unregistered';
    badgeEl.textContent = 'Awaiting Scan';
  }
  if (statusMsgEl) {
    statusMsgEl.textContent = 'Scan a barcode or enter roll number to begin registration.';
    statusMsgEl.style.color = 'var(--text-muted)';
  }
  if (registerBtn) registerBtn.style.display = 'none';
  if (scanAnotherBtn) scanAnotherBtn.style.display = 'none';
  if (manualInput) {
    manualInput.value = '';
    manualInput.focus();
  }
}

/**
 * Visual loading indicator in verification panel
 */
function setProfileLoadingState(loading, studentId = '') {
  const nameEl = document.getElementById('student-name');
  const idEl = document.getElementById('student-id-display');
  const badgeEl = document.getElementById('profile-status-badge');
  const statusMsgEl = document.getElementById('student-status-message');

  if (loading) {
    if (nameEl) nameEl.innerHTML = `<span class="spinner spinner-dark"></span> Searching...`;
    if (idEl) idEl.textContent = studentId;
    if (badgeEl) {
      badgeEl.className = 'badge badge-unregistered';
      badgeEl.textContent = 'Searching DB...';
    }
    if (statusMsgEl) statusMsgEl.textContent = 'Retrieving profile and registration history...';
  }
}

/**
 * Error box handlers
 */
function showCameraError(msg) {
  const errorBox = document.getElementById('camera-error-box');
  const errorMsg = document.getElementById('camera-error-message');
  if (errorBox && errorMsg) {
    errorMsg.textContent = msg;
    errorBox.style.display = 'block';
  }
}

function hideCameraError() {
  const errorBox = document.getElementById('camera-error-box');
  if (errorBox) errorBox.style.display = 'none';
}
