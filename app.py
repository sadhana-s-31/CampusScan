"""
CampusScan — Smart Student Barcode Registration System
Backend Application (Flask + SQLite)
"""

import os
import re
import csv
import io
import sqlite3
from datetime import datetime
from functools import wraps
from flask import (
    Flask, render_template, request, redirect, url_for,
    session, flash, jsonify, send_from_directory, Response, make_response
)
from werkzeug.utils import secure_filename
from werkzeug.security import generate_password_hash, check_password_hash
import pandas as pd
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Application setup
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'campus-scan-dev-insecure-key-change-in-production-2026')
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16 MB max upload size
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'

# Base Directories
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'data')
STUDENTS_DIR = os.path.join(DATA_DIR, 'students')
UPLOADS_DIR = os.path.join(DATA_DIR, 'uploads')
DB_PATH = os.path.join(DATA_DIR, 'students.db')

# Ensure essential directories exist
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(STUDENTS_DIR, exist_ok=True)
os.makedirs(UPLOADS_DIR, exist_ok=True)

# Default admin configuration (override in .env)
DEFAULT_ADMIN_USER = os.environ.get('ADMIN_USERNAME', 'admin')
DEFAULT_ADMIN_PASS = os.environ.get('ADMIN_PASSWORD', 'admin123')

ALLOWED_EXCEL_EXTENSIONS = {'.csv', '.xlsx', '.xls'}
ALLOWED_IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp'}


def get_db():
    """
    Connect to SQLite database with WAL mode and foreign keys enabled.
    Row factory returns sqlite3.Row for dictionary-like column access.
    """
    conn = sqlite3.connect(DB_PATH, timeout=20.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.execute("PRAGMA journal_mode = WAL;")
    return conn


def init_db():
    """
    Initialize SQLite schema for students, registrations, and admins.
    Seeds default admin if not present.
    """
    with get_db() as conn:
        cursor = conn.cursor()
        
        # Students table: student_id is PRIMARY KEY
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS students (
                student_id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                photo_filename TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        
        # Registrations table: student_id is UNIQUE & FOREIGN KEY
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS registrations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                student_id TEXT NOT NULL UNIQUE REFERENCES students(student_id) ON DELETE CASCADE,
                registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                registered_by TEXT DEFAULT 'scanner',
                notes TEXT
            );
        """)
        
        # Admin accounts table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS admins (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        
        # Check if admin exists; if not, seed default admin
        cursor.execute("SELECT id FROM admins WHERE username = ?", (DEFAULT_ADMIN_USER,))
        admin = cursor.fetchone()
        if not admin:
            hashed_pwd = generate_password_hash(DEFAULT_ADMIN_PASS, method='pbkdf2:sha256')
            cursor.execute("INSERT INTO admins (username, password_hash) VALUES (?, ?)", (DEFAULT_ADMIN_USER, hashed_pwd))
            print(f"[CampusScan] Initialized default admin user: '{DEFAULT_ADMIN_USER}' (Password: '{DEFAULT_ADMIN_PASS}')")
            
        # If students table is empty, check if sample CSV exists and import it
        cursor.execute("SELECT COUNT(*) AS cnt FROM students")
        row = cursor.fetchone()
        if row and row['cnt'] == 0:
            sample_csv = os.path.join(BASE_DIR, 'sample_data', 'sample_students.csv')
            if os.path.exists(sample_csv):
                try:
                    df = pd.read_csv(sample_csv)
                    for _, s_row in df.iterrows():
                        sid = str(s_row.get('student_id', '')).strip().upper()
                        sname = str(s_row.get('name', '')).strip()
                        if sid and sname:
                            cursor.execute(
                                "INSERT OR IGNORE INTO students (student_id, name) VALUES (?, ?)",
                                (sid, sname)
                            )
                    print(f"[CampusScan] Seeded sample students from {sample_csv}")
                except Exception as e:
                    print(f"[CampusScan] Note: Could not auto-seed sample CSV: {e}")
                    
        conn.commit()


# Initialize database on module load
init_db()


# ==============================================================================
# Helper Functions
# ==============================================================================

def find_student_photo_file(student_id: str):
    """
    Find matching photograph in data/students/ matching <student_id>.<ext>.
    Case-insensitive match for student_id and supported image extensions.
    """
    clean_id = str(student_id).strip().upper()
    if not clean_id:
        return None
        
    try:
        files = os.listdir(STUDENTS_DIR)
    except OSError:
        return None

    # Exact base name match with allowed extensions
    for filename in files:
        base, ext = os.path.splitext(filename)
        if base.strip().upper() == clean_id and ext.lower() in ALLOWED_IMAGE_EXTENSIONS:
            return filename
            
    return None


def get_photo_url(student_id: str):
    """
    Returns the URL for the student's photo or default avatar.
    """
    photo_file = find_student_photo_file(student_id)
    if photo_file:
        return url_for('serve_student_photo', student_id=student_id)
    return url_for('static', filename='images/default-profile.svg')


def admin_required(f):
    """
    Decorator to protect administrator routes.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('admin_logged_in'):
            flash("Administrator login required to access this page.", "warning")
            return redirect(url_for('login', next=request.url))
        return f(*args, **kwargs)
    return decorated_function


# ==============================================================================
# Public / Scanner Routes & APIs
# ==============================================================================

@app.route('/')
def index():
    """Main scanner and student registration page."""
    return render_template('index.html')


@app.route('/students/photo/<student_id>')
def serve_student_photo(student_id):
    """
    Safely serves the student's photograph from data/students/.
    Prevents path traversal and returns default SVG if not found.
    """
    safe_id = secure_filename(student_id).strip().upper()
    photo_file = find_student_photo_file(safe_id)
    if photo_file:
        return send_from_directory(STUDENTS_DIR, photo_file)
    return send_from_directory(os.path.join(BASE_DIR, 'static', 'images'), 'default-profile.svg')


@app.route('/api/students/<student_id>', methods=['GET'])
def get_student(student_id):
    """
    API endpoint: Search student by ID.
    Returns student profile, photo URL, and current registration status.
    """
    clean_id = student_id.strip().upper()
    if not clean_id:
        return jsonify({
            'success': False,
            'status': 'error',
            'message': 'Student ID cannot be empty.'
        }), 400

    with get_db() as conn:
        cursor = conn.cursor()
        
        # Query student record
        cursor.execute("SELECT * FROM students WHERE UPPER(student_id) = ?", (clean_id,))
        student = cursor.fetchone()
        
        if not student:
            return jsonify({
                'success': False,
                'status': 'not_found',
                'message': 'Student not found. Please add the student record before registering.'
            }), 404

        # Query registration record
        cursor.execute("SELECT * FROM registrations WHERE UPPER(student_id) = ?", (clean_id,))
        reg = cursor.fetchone()

        photo_url = get_photo_url(clean_id)

        if reg:
            return jsonify({
                'success': True,
                'status': 'already_registered',
                'message': 'You have already registered!',
                'student': {
                    'student_id': student['student_id'],
                    'name': student['name'],
                    'photo_url': photo_url,
                    'has_photo': find_student_photo_file(clean_id) is not None
                },
                'registration': {
                    'registered_at': reg['registered_at'],
                    'registered_by': reg['registered_by']
                }
            }), 200
        else:
            return jsonify({
                'success': True,
                'status': 'eligible',
                'message': 'Student found and eligible for registration.',
                'student': {
                    'student_id': student['student_id'],
                    'name': student['name'],
                    'photo_url': photo_url,
                    'has_photo': find_student_photo_file(clean_id) is not None
                }
            }), 200


@app.route('/api/register', methods=['POST'])
def register_student():
    """
    API endpoint: Register an eligible student.
    Enforces strict backend duplicate prevention via SQLite transactions,
    UNIQUE constraint checks, and database locks.
    """
    data = request.get_json(silent=True) or {}
    student_id = data.get('student_id', '').strip().upper()
    registered_by = data.get('registered_by', 'scanner').strip()

    if not student_id:
        return jsonify({
            'success': False,
            'status': 'error',
            'message': 'Student ID is required.'
        }), 400

    conn = get_db()
    try:
        # Use BEGIN IMMEDIATE to lock writer and prevent race conditions
        conn.execute("BEGIN IMMEDIATE")
        cursor = conn.cursor()

        # 1. Verify student exists in master student database
        cursor.execute("SELECT * FROM students WHERE UPPER(student_id) = ?", (student_id,))
        student = cursor.fetchone()

        if not student:
            conn.rollback()
            return jsonify({
                'success': False,
                'status': 'not_found',
                'message': 'Student not found. Please add the student record before registering.'
            }), 404

        # 2. Check if already registered
        cursor.execute("SELECT * FROM registrations WHERE UPPER(student_id) = ?", (student_id,))
        existing_reg = cursor.fetchone()

        if existing_reg:
            conn.rollback()
            photo_url = get_photo_url(student['student_id'])
            return jsonify({
                'success': False,
                'status': 'already_registered',
                'message': 'You have already registered!',
                'student': {
                    'student_id': student['student_id'],
                    'name': student['name'],
                    'photo_url': photo_url
                },
                'registration': {
                    'registered_at': existing_reg['registered_at'],
                    'registered_by': existing_reg['registered_by']
                }
            }), 409  # Conflict

        # 3. Insert registration record with current timestamp
        now_iso = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute("""
            INSERT INTO registrations (student_id, registered_at, registered_by)
            VALUES (?, ?, ?)
        """, (student['student_id'], now_iso, registered_by))

        conn.commit()

        photo_url = get_photo_url(student['student_id'])
        return jsonify({
            'success': True,
            'status': 'registered',
            'message': 'Student registered successfully!',
            'student': {
                'student_id': student['student_id'],
                'name': student['name'],
                'photo_url': photo_url
            },
            'registration': {
                'registered_at': now_iso,
                'registered_by': registered_by
            }
        }), 201

    except sqlite3.IntegrityError:
        # Catch duplicate constraint violation if concurrent request hit first
        conn.rollback()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM students WHERE UPPER(student_id) = ?", (student_id,))
        student = cursor.fetchone()
        cursor.execute("SELECT * FROM registrations WHERE UPPER(student_id) = ?", (student_id,))
        existing_reg = cursor.fetchone()
        
        reg_time = existing_reg['registered_at'] if existing_reg else datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        photo_url = get_photo_url(student_id)

        return jsonify({
            'success': False,
            'status': 'already_registered',
            'message': 'You have already registered!',
            'student': {
                'student_id': student['student_id'] if student else student_id,
                'name': student['name'] if student else 'Student',
                'photo_url': photo_url
            },
            'registration': {
                'registered_at': reg_time,
                'registered_by': existing_reg['registered_by'] if existing_reg else 'system'
            }
        }), 409

    except Exception as e:
        conn.rollback()
        return jsonify({
            'success': False,
            'status': 'error',
            'message': f"An error occurred during registration: {str(e)}"
        }), 500

    finally:
        conn.close()


# ==============================================================================
# Admin Authentication Routes
# ==============================================================================

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Administrator login page and verification."""
    if session.get('admin_logged_in'):
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()
        next_page = request.form.get('next') or request.args.get('next')

        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM admins WHERE username = ?", (username,))
            admin = cursor.fetchone()

            if admin and check_password_hash(admin['password_hash'], password):
                session['admin_logged_in'] = True
                session['admin_username'] = admin['username']
                flash(f"Welcome back, {admin['username']}!", "success")
                if next_page and next_page.startswith('/'):
                    return redirect(next_page)
                return redirect(url_for('dashboard'))
            else:
                flash("Invalid administrator username or password.", "danger")

    return render_template('login.html')


@app.route('/logout')
def logout():
    """Logs out current administrator."""
    session.clear()
    flash("You have been safely logged out.", "info")
    return redirect(url_for('login'))


# ==============================================================================
# Admin Dashboard & Analytics Routes
# ==============================================================================

@app.route('/dashboard')
@admin_required
def dashboard():
    """
    Administrator dashboard: summary statistics, search/filter table,
    and student registration monitoring.
    """
    with get_db() as conn:
        cursor = conn.cursor()
        
        # Summary counts
        cursor.execute("SELECT COUNT(*) AS total FROM students")
        total_students = cursor.fetchone()['total']
        
        cursor.execute("SELECT COUNT(*) AS total_reg FROM registrations")
        total_registered = cursor.fetchone()['total_reg']
        
        total_unregistered = max(0, total_students - total_registered)
        reg_rate = round((total_registered / total_students * 100), 1) if total_students > 0 else 0.0

        # Query all students with registration details
        cursor.execute("""
            SELECT 
                s.student_id,
                s.name,
                r.registered_at,
                r.registered_by,
                CASE WHEN r.student_id IS NOT NULL THEN 1 ELSE 0 END AS is_registered
            FROM students s
            LEFT JOIN registrations r ON s.student_id = r.student_id
            ORDER BY is_registered DESC, r.registered_at DESC, s.name ASC
        """)
        raw_students = cursor.fetchall()

        # Format student data with photo check
        students_list = []
        missing_photos_count = 0
        for s in raw_students:
            has_photo = find_student_photo_file(s['student_id']) is not None
            if not has_photo:
                missing_photos_count += 1
            students_list.append({
                'student_id': s['student_id'],
                'name': s['name'],
                'is_registered': bool(s['is_registered']),
                'registered_at': s['registered_at'],
                'registered_by': s['registered_by'],
                'has_photo': has_photo,
                'photo_url': get_photo_url(s['student_id'])
            })

    return render_template(
        'dashboard.html',
        total_students=total_students,
        total_registered=total_registered,
        total_unregistered=total_unregistered,
        registration_rate=reg_rate,
        missing_photos_count=missing_photos_count,
        students=students_list
    )


@app.route('/api/dashboard/stats')
@admin_required
def dashboard_stats_api():
    """Real-time JSON endpoint for dashboard analytics."""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) AS total FROM students")
        total_students = cursor.fetchone()['total']
        cursor.execute("SELECT COUNT(*) AS total_reg FROM registrations")
        total_registered = cursor.fetchone()['total_reg']
        
        total_unregistered = max(0, total_students - total_registered)
        reg_rate = round((total_registered / total_students * 100), 1) if total_students > 0 else 0.0

        return jsonify({
            'total_students': total_students,
            'total_registered': total_registered,
            'total_unregistered': total_unregistered,
            'registration_rate': reg_rate
        })


@app.route('/admin/export-csv')
@admin_required
def export_csv():
    """
    Exports full student registration report as a downloadable CSV.
    """
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT 
                s.student_id,
                s.name,
                CASE WHEN r.student_id IS NOT NULL THEN 'Registered' ELSE 'Not Registered' END AS status,
                COALESCE(r.registered_at, 'N/A') AS registered_at,
                COALESCE(r.registered_by, 'N/A') AS registered_by
            FROM students s
            LEFT JOIN registrations r ON s.student_id = r.student_id
            ORDER BY s.student_id ASC
        """)
        rows = cursor.fetchall()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Student ID', 'Student Name', 'Status', 'Registration Timestamp', 'Registered By'])
    for r in rows:
        writer.writerow([r['student_id'], r['name'], r['status'], r['registered_at'], r['registered_by']])

    filename = f"campuss_scan_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    response = make_response(output.getvalue())
    response.headers['Content-Disposition'] = f'attachment; filename={filename}'
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    return response


# ==============================================================================
# Admin Student Records Management Routes
# ==============================================================================

@app.route('/records')
@admin_required
def records():
    """
    Student records management page:
    - Add individual student
    - Bulk upload CSV/Excel
    - Photo match status
    """
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT 
                s.student_id, 
                s.name, 
                s.created_at,
                CASE WHEN r.student_id IS NOT NULL THEN 1 ELSE 0 END AS is_registered,
                r.registered_at
            FROM students s
            LEFT JOIN registrations r ON s.student_id = r.student_id
            ORDER BY s.student_id ASC
        """)
        rows = cursor.fetchall()

    students = []
    missing_photo_count = 0
    for r in rows:
        has_photo = find_student_photo_file(r['student_id']) is not None
        if not has_photo:
            missing_photo_count += 1
        students.append({
            'student_id': r['student_id'],
            'name': r['name'],
            'created_at': r['created_at'],
            'is_registered': bool(r['is_registered']),
            'registered_at': r['registered_at'],
            'has_photo': has_photo,
            'photo_url': get_photo_url(r['student_id'])
        })

    return render_template(
        'records.html',
        students=students,
        total_students=len(students),
        missing_photo_count=missing_photo_count
    )


@app.route('/admin/add-student', methods=['POST'])
@admin_required
def add_student():
    """
    Manual student entry endpoint.
    Validates student ID uniqueness and handles optional photograph upload.
    """
    student_id = request.form.get('student_id', '').strip().upper()
    name = request.form.get('name', '').strip()
    photo_file = request.files.get('photo')

    if not student_id or not name:
        flash("Student ID and Full Name are both required.", "danger")
        return redirect(url_for('records'))

    with get_db() as conn:
        cursor = conn.cursor()
        
        # Check if student ID already exists
        cursor.execute("SELECT student_id FROM students WHERE UPPER(student_id) = ?", (student_id,))
        if cursor.fetchone():
            flash(f"Student with ID '{student_id}' already exists in the database.", "warning")
            return redirect(url_for('records'))

        photo_filename = None
        # Handle photo upload if supplied
        if photo_file and photo_file.filename:
            _, ext = os.path.splitext(photo_file.filename)
            ext = ext.lower()
            if ext in ALLOWED_IMAGE_EXTENSIONS:
                safe_filename = f"{student_id}{ext}"
                dest_path = os.path.join(STUDENTS_DIR, safe_filename)
                photo_file.save(dest_path)
                photo_filename = safe_filename
            else:
                flash("Invalid image format. Supported formats: JPG, JPEG, PNG, WEBP.", "warning")

        cursor.execute(
            "INSERT INTO students (student_id, name, photo_filename) VALUES (?, ?, ?)",
            (student_id, name, photo_filename)
        )
        conn.commit()

    flash(f"Student '{name}' ({student_id}) added successfully!", "success")
    return redirect(url_for('records'))


@app.route('/admin/import-students', methods=['POST'])
@admin_required
def import_students():
    """
    Bulk import students from Excel (.xlsx, .xls) or CSV files.
    Validates required columns, adds new students, updates existing names,
    skips invalid rows, and preserves all existing registration timestamps!
    """
    if 'file' not in request.files:
        flash("No file was uploaded.", "danger")
        return redirect(url_for('records'))

    file = request.files['file']
    if not file or not file.filename:
        flash("Please select a valid CSV or Excel file.", "danger")
        return redirect(url_for('records'))

    _, ext = os.path.splitext(file.filename)
    ext = ext.lower()
    if ext not in ALLOWED_EXCEL_EXTENSIONS:
        flash("Invalid file format. Please upload a .csv, .xlsx, or .xls file.", "danger")
        return redirect(url_for('records'))

    # Save to uploads folder securely
    upload_path = os.path.join(UPLOADS_DIR, secure_filename(file.filename))
    file.save(upload_path)

    try:
        if ext == '.csv':
            # Try reading with utf-8, fallback to latin-1
            try:
                df = pd.read_csv(upload_path, dtype=str)
            except UnicodeDecodeError:
                df = pd.read_csv(upload_path, encoding='latin1', dtype=str)
        else:
            df = pd.read_excel(upload_path, dtype=str)

        # Normalize column names: lowercase, strip, replace spaces/underscores
        raw_cols = df.columns.tolist()
        normalized_cols = {col: re.sub(r'[\s_]+', '', str(col).strip().lower()) for col in raw_cols}

        id_aliases = {'studentid', 'rollno', 'rollnumber', 'registernumber', 'regno', 'id', 'roll'}
        name_aliases = {'name', 'studentname', 'fullname', 'student'}

        id_col = None
        name_col = None

        for orig_col, norm_col in normalized_cols.items():
            if norm_col in id_aliases and not id_col:
                id_col = orig_col
            elif norm_col in name_aliases and not name_col:
                name_col = orig_col

        if not id_col or not name_col:
            found_cols_str = ", ".join(f"'{c}'" for c in raw_cols)
            flash(
                f"Missing required columns! We need a Student ID column (e.g. student_id, roll_no) "
                f"and a Name column (e.g. name, student_name). Uploaded columns were: {found_cols_str}",
                "danger"
            )
            return redirect(url_for('records'))

        # Track import statistics
        added_count = 0
        updated_count = 0
        skipped_count = 0
        missing_photos = 0

        with get_db() as conn:
            cursor = conn.cursor()

            for _, row in df.iterrows():
                raw_id = row.get(id_col)
                raw_name = row.get(name_col)

                if pd.isna(raw_id) or pd.isna(raw_name):
                    skipped_count += 1
                    continue

                sid = str(raw_id).strip().upper()
                sname = str(raw_name).strip()

                if not sid or not sname:
                    skipped_count += 1
                    continue

                # Check if student exists
                cursor.execute("SELECT student_id, name FROM students WHERE UPPER(student_id) = ?", (sid,))
                existing = cursor.fetchone()

                if existing:
                    # Update name if changed; DO NOT touch registrations or timestamps!
                    if existing['name'] != sname:
                        cursor.execute("UPDATE students SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE UPPER(student_id) = ?", (sname, sid))
                        updated_count += 1
                else:
                    cursor.execute("INSERT INTO students (student_id, name) VALUES (?, ?)", (sid, sname))
                    added_count += 1

                # Check photo presence
                if not find_student_photo_file(sid):
                    missing_photos += 1

            conn.commit()

        # Clean up temporary uploaded file
        if os.path.exists(upload_path):
            os.remove(upload_path)

        flash(
            f"Import complete! {added_count} new student(s) added, {updated_count} record(s) updated, "
            f"{skipped_count} invalid row(s) skipped. ({missing_photos} students currently missing photos).",
            "success"
        )

    except Exception as e:
        if os.path.exists(upload_path):
            os.remove(upload_path)
        flash(f"Error processing import file: {str(e)}", "danger")

    return redirect(url_for('records'))


@app.route('/admin/delete-student/<student_id>', methods=['POST'])
@admin_required
def delete_student(student_id):
    """Delete a student and cascade delete registration."""
    clean_id = student_id.strip().upper()
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM students WHERE UPPER(student_id) = ?", (clean_id,))
        conn.commit()
    flash(f"Student '{clean_id}' deleted successfully.", "info")
    return redirect(url_for('records'))


@app.route('/admin/reset-registration/<student_id>', methods=['POST'])
@admin_required
def reset_registration(student_id):
    """
    Allows admin to reset a student's registration status (for testing or re-scanning).
    """
    clean_id = student_id.strip().upper()
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM registrations WHERE UPPER(student_id) = ?", (clean_id,))
        conn.commit()
    flash(f"Registration for student '{clean_id}' has been cleared.", "success")
    return redirect(url_for('dashboard'))


@app.route('/sample_data/<path:filename>')
def serve_sample_data(filename):
    """Serve sample CSV and Excel files for easy testing."""
    sample_dir = os.path.join(BASE_DIR, 'sample_data')
    return send_from_directory(sample_dir, secure_filename(filename), as_attachment=True)


if __name__ == '__main__':
    # Default local development server
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_DEBUG', 'False').lower() in ('true', '1')
    print(f"\n=======================================================")
    print(f" CampusScan — Smart Student Barcode Registration System")
    print(f" Server running at: http://127.0.0.1:{port}")
    print(f" Default Admin: '{DEFAULT_ADMIN_USER}' | Password: '{DEFAULT_ADMIN_PASS}'")
    print(f"=======================================================\n")
    app.run(host='0.0.0.0', port=port, debug=debug)
