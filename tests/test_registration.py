"""
Unit and Concurrency Tests for Student Registration & Duplicate Prevention.
Tests:
1. Successfully registering an eligible student
2. Rejecting a second registration for the same student
3. Returning clear error for an unknown student ID (no auto-creation)
4. Preserving registration timestamps during student imports
5. Handling concurrent registration attempts safely
"""

import os
import io
import time
import tempfile
import unittest
import threading
import sqlite3

import app


class TestStudentRegistration(unittest.TestCase):

    def setUp(self):
        # Configure app for testing
        app.app.config['TESTING'] = True
        app.app.config['SECRET_KEY'] = 'test-secret-registration'

        # Create temporary database
        self.db_fd, self.temp_db_path = tempfile.mkstemp(suffix='.db')
        self.orig_db_path = app.DB_PATH
        app.DB_PATH = self.temp_db_path

        # Initialize schema in test database
        app.init_db()

        # Seed test students
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("INSERT OR REPLACE INTO students (student_id, name) VALUES ('ELIGIBLE01', 'Alice Green')")
            cursor.execute("INSERT OR REPLACE INTO students (student_id, name) VALUES ('ELIGIBLE02', 'Bob White')")
            conn.commit()

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

    def test_1_lookup_eligible_student(self):
        """Test looking up an existing, unregistered student returns eligible status."""
        response = self.client.get('/api/students/ELIGIBLE01')
        self.assertEqual(response.status_code, 200)

        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertEqual(data['status'], 'eligible')
        self.assertEqual(data['student']['student_id'], 'ELIGIBLE01')
        self.assertEqual(data['student']['name'], 'Alice Green')

    def test_2_register_eligible_student_success(self):
        """Test successfully registering an eligible student."""
        response = self.client.post('/api/register', json={
            'student_id': 'ELIGIBLE01',
            'registered_by': 'test_scanner'
        })

        self.assertEqual(response.status_code, 201)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertEqual(data['status'], 'registered')
        self.assertIn('registered_at', data['registration'])

        # Verify entry in registrations table
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM registrations WHERE student_id = 'ELIGIBLE01'")
            reg = cursor.fetchone()
            self.assertIsNotNone(reg)
            self.assertEqual(reg['registered_by'], 'test_scanner')

    def test_3_reject_second_registration_duplicate(self):
        """Test that registering an already registered student returns duplicate warning and 409 Conflict."""
        # 1. First registration
        res1 = self.client.post('/api/register', json={
            'student_id': 'ELIGIBLE01',
            'registered_by': 'scanner_1'
        })
        self.assertEqual(res1.status_code, 201)
        first_timestamp = res1.get_json()['registration']['registered_at']

        # 2. Second registration attempt for identical student
        res2 = self.client.post('/api/register', json={
            'student_id': 'ELIGIBLE01',
            'registered_by': 'scanner_2'
        })

        # MUST return 409 Conflict
        self.assertEqual(res2.status_code, 409)
        data2 = res2.get_json()
        self.assertFalse(data2['success'])
        self.assertEqual(data2['status'], 'already_registered')
        self.assertEqual(data2['message'], 'You have already registered!')
        self.assertEqual(data2['student']['student_id'], 'ELIGIBLE01')
        self.assertEqual(data2['registration']['registered_at'], first_timestamp)

        # Verify registrations table has exactly ONE record for this student
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) AS cnt FROM registrations WHERE student_id = 'ELIGIBLE01'")
            self.assertEqual(cursor.fetchone()['cnt'], 1)

    def test_4_lookup_already_registered_student(self):
        """Test GET /api/students returns already_registered status when student was previously registered."""
        # Register first
        self.client.post('/api/register', json={'student_id': 'ELIGIBLE01'})

        # Now search
        response = self.client.get('/api/students/ELIGIBLE01')
        self.assertEqual(response.status_code, 200)

        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertEqual(data['status'], 'already_registered')
        self.assertEqual(data['message'], 'You have already registered!')
        self.assertIn('registered_at', data['registration'])

    def test_5_unknown_student_returns_error_and_no_profile_created(self):
        """Test unknown student ID returns clear error and does NOT auto-create incomplete profile."""
        unknown_id = 'UNKNOWN_999_NOT_IN_DB'

        # 1. Lookup
        lookup_res = self.client.get(f'/api/students/{unknown_id}')
        self.assertEqual(lookup_res.status_code, 404)
        data = lookup_res.get_json()
        self.assertFalse(data['success'])
        self.assertEqual(data['status'], 'not_found')
        self.assertIn("Student not found. Please add the student record before registering.", data['message'])

        # 2. Direct register attempt
        reg_res = self.client.post('/api/register', json={'student_id': unknown_id})
        self.assertEqual(reg_res.status_code, 404)

        # 3. Verify student was NOT added to database
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM students WHERE student_id = ?", (unknown_id,))
            self.assertIsNone(cursor.fetchone())

    def test_6_import_does_not_overwrite_registration_timestamp(self):
        """Test that re-importing student roster never overwrites or wipes registration timestamps."""
        # 1. Register student
        self.client.post('/api/register', json={'student_id': 'ELIGIBLE01'})

        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT registered_at FROM registrations WHERE student_id = 'ELIGIBLE01'")
            orig_registered_at = cursor.fetchone()['registered_at']

        # 2. Simulate CSV import with updated name for ELIGIBLE01
        with self.client.session_transaction() as sess:
            sess['admin_logged_in'] = True

        csv_content = "student_id,name\nELIGIBLE01,Alice Green (Updated Name)\n".encode('utf-8')
        import_res = self.client.post('/admin/import-students', data={
            'file': (io.BytesIO(csv_content), 'roster.csv')
        }, content_type='multipart/form-data', follow_redirects=True)

        self.assertEqual(import_res.status_code, 200)

        # Verify student name was updated BUT registration timestamp was UNTOUCHED
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM students WHERE student_id = 'ELIGIBLE01'")
            self.assertEqual(cursor.fetchone()['name'], 'Alice Green (Updated Name)')

            cursor.execute("SELECT registered_at FROM registrations WHERE student_id = 'ELIGIBLE01'")
            curr_registered_at = cursor.fetchone()['registered_at']
            self.assertEqual(curr_registered_at, orig_registered_at)

    def test_7_concurrent_registrations_handled_safely(self):
        """
        Test concurrency: Simulate 10 simultaneous threads trying to register the same student ID.
        Verify that EXACTLY ONE request succeeds (201) and all others receive 409 Conflict.
        """
        student_id = 'ELIGIBLE02'
        num_threads = 10
        results = []
        barrier = threading.Barrier(num_threads)

        def worker(client_id):
            client = app.app.test_client()
            # Wait for all threads to align at the barrier
            barrier.wait()
            try:
                response = client.post('/api/register', json={
                    'student_id': student_id,
                    'registered_by': f'concurrent_scanner_{client_id}'
                })
                results.append((response.status_code, response.get_json()))
            except Exception as e:
                results.append((500, str(e)))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # Check results
        successes = [r for r in results if r[0] == 201]
        duplicates = [r for r in results if r[0] == 409]

        self.assertEqual(len(successes), 1, f"Expected exactly 1 success, got {len(successes)}")
        self.assertEqual(len(duplicates), num_threads - 1, f"Expected {num_threads - 1} duplicate rejections, got {len(duplicates)}")

        # Verify exactly one record in database
        with app.get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) AS cnt FROM registrations WHERE student_id = ?", (student_id,))
            self.assertEqual(cursor.fetchone()['cnt'], 1)


if __name__ == '__main__':
    unittest.main()
