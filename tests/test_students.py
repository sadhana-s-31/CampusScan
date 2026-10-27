"""
Unit and Integration Tests for Student Records and Management.
Tests:
1. Adding a new student
2. Rejecting duplicate student IDs in the student table
3. Importing student data from CSV
4. Matching student photos by filename
5. Preventing unauthenticated access to administrator pages
"""

import os
import io
import tempfile
import unittest
import sqlite3
import pandas as pd

import app


class TestStudentManagement(unittest.TestCase):

    def setUp(self):
        # Configure app for testing
        app.app.config['TESTING'] = True
        app.app.config['WTF_CSRF_ENABLED'] = False
        app.app.config['SECRET_KEY'] = 'test-secret-key-1234'

        # Create temporary database
        self.db_fd, self.temp_db_path = tempfile.mkstemp(suffix='.db')
        self.orig_db_path = app.DB_PATH
        app.DB_PATH = self.temp_db_path

        # Initialize schema in test database
        app.init_db()

        self.client = app.app.test_client()

    def tearDown(self):
        # Restore original database path and clean up temp db
        app.DB_PATH = self.orig_db_path
        os.close(self.db_fd)
        if os.path.exists(self.temp_db_path):
            try:
                os.remove(self.temp_db_path)
            except OSError:
                pass

    def login_admin(self):
        """Helper to simulate logged-in admin session."""
        with self.client.session_transaction() as sess:
            sess['admin_logged_in'] = True
            sess['admin_username'] = 'admin'

    def test_1_add_new_student(self):
        """Test adding a brand new student successfully."""
        self.login_admin()

        response = self.client.post('/admin/add-student', data={
            'student_id': 'TEST001',
            'name': 'Rahul Sharma'
        }, follow_redirects=True)

        self.assertEqual(response.status_code, 200)

        # Verify student exists in test database
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM students WHERE student_id = 'TEST001'")
            row = cursor.fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row['name'], 'Rahul Sharma')

    def test_2_reject_duplicate_student_id(self):
        """Test rejecting student addition when student_id already exists."""
        self.login_admin()

        # Add initial student
        self.client.post('/admin/add-student', data={
            'student_id': 'DUP001',
            'name': 'Original Student'
        }, follow_redirects=True)

        # Attempt to add student with identical ID
        response = self.client.post('/admin/add-student', data={
            'student_id': 'DUP001',
            'name': 'Duplicate Student'
        }, follow_redirects=True)

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"already exists", response.data)

        # Verify student table still has only 1 record with original name
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) AS cnt FROM students WHERE student_id = 'DUP001'")
            self.assertEqual(cursor.fetchone()['cnt'], 1)
            cursor.execute("SELECT name FROM students WHERE student_id = 'DUP001'")
            self.assertEqual(cursor.fetchone()['name'], 'Original Student')

    def test_3_import_student_data_from_csv(self):
        """Test bulk importing student data from CSV and matching columns."""
        self.login_admin()

        csv_content = (
            "roll_no,student_name\n"
            "CSV001,Priya Mehta\n"
            "CSV002,Amit Kumar\n"
            "CSV003,Deepa Nair\n"
        ).encode('utf-8')

        data = {
            'file': (io.BytesIO(csv_content), 'students.csv')
        }

        response = self.client.post(
            '/admin/import-students',
            data=data,
            content_type='multipart/form-data',
            follow_redirects=True
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Import complete", response.data)

        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM students WHERE student_id IN ('CSV001', 'CSV002', 'CSV003')")
            rows = cursor.fetchall()
            self.assertEqual(len(rows), 3)

    def test_4_import_rejects_missing_columns(self):
        """Test that importing CSV with invalid headers gives clear error message."""
        self.login_admin()

        invalid_csv = (
            "email,phone,address\n"
            "test@college.edu,9999999999,Main Campus\n"
        ).encode('utf-8')

        data = {
            'file': (io.BytesIO(invalid_csv), 'invalid.csv')
        }

        response = self.client.post(
            '/admin/import-students',
            data=data,
            content_type='multipart/form-data',
            follow_redirects=True
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Missing required columns", response.data)

    def test_5_match_student_photo_by_filename(self):
        """Test photo lookup matching student ID case-insensitively with supported extensions."""
        # Check student 23CS001 which has 23CS001.jpg in data/students/
        photo_found = app.find_student_photo_file('23cs001')
        self.assertIsNotNone(photo_found)
        self.assertTrue(photo_found.lower().startswith('23cs001'))

        # Check unknown student ID
        unknown_photo = app.find_student_photo_file('NONEXISTENT_STUDENT_999')
        self.assertIsNone(unknown_photo)

    def test_6_unauthenticated_admin_access_prevention(self):
        """Test that unauthenticated requests to admin routes are redirected to login."""
        protected_endpoints = ['/dashboard', '/records', '/admin/export-csv']

        for endpoint in protected_endpoints:
            response = self.client.get(endpoint)
            self.assertEqual(response.status_code, 302, f"Endpoint {endpoint} was not protected!")
            self.assertIn('/login', response.headers.get('Location', ''))

    def test_7_api_add_student_with_photo(self):
        """Test adding student with optional photo via public API without session cookies."""
        import json
        dummy_img = io.BytesIO(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xff\xdb\x00C\x00")
        response = self.client.post('/api/students/add', data={
            'student_id': 'API_STUDENT_01',
            'name': 'API Test Student',
            'photo': (dummy_img, 'profile.jpg')
        }, content_type='multipart/form-data')

        self.assertEqual(response.status_code, 201)
        res_data = json.loads(response.data.decode('utf-8'))
        self.assertTrue(res_data['success'])
        self.assertEqual(res_data['student']['student_id'], 'API_STUDENT_01')
        self.assertEqual(res_data['student']['name'], 'API Test Student')


if __name__ == '__main__':
    unittest.main()

