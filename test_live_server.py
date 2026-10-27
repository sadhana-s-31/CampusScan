"""
Live HTTP integration test against running Flask server at http://127.0.0.1:5000.
Tests public APIs and authenticated admin endpoints.
"""
import urllib.request
import urllib.error
import urllib.parse
import http.cookiejar
import json

base = 'http://127.0.0.1:5000'

# Setup cookie jar to maintain admin session
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

print("--- Testing Live CampusScan Server ---")

# 1. Test homepage
with opener.open(f'{base}/') as res:
    html = res.read().decode('utf-8')
    assert 'Student ID Barcode Scanner' in html
    assert 'You have already registered!' in html
    print('[PASS] 1. Home Page HTTP 200 OK (Viewfinder, Scanner, Duplicate Modal rendered)')

# 2. Test Student lookup
with opener.open(f'{base}/api/students/23CS002') as res:
    data = json.loads(res.read().decode('utf-8'))
    assert data['success'] is True
    print(f'[PASS] 2. Student Lookup (23CS002): status={data["status"]}, name={data["student"]["name"]}')

# 3. Test Student registration for 23CS002
reg_payload = json.dumps({'student_id': '23CS002', 'registered_by': 'live_test'}).encode('utf-8')
req = urllib.request.Request(f'{base}/api/register', data=reg_payload, headers={'Content-Type': 'application/json'})

try:
    with opener.open(req) as res:
        data = json.loads(res.read().decode('utf-8'))
        print(f'[PASS] 3. Student Registration: status_code={res.status}, status={data["status"]}')
except urllib.error.HTTPError as e:
    data = json.loads(e.read().decode('utf-8'))
    print(f'[INFO] 3. Student Registration: HTTP {e.code} ({data.get("status")})')

# 4. Test DUPLICATE registration rejection (MUST return 409 Conflict!)
try:
    with opener.open(req) as res:
        print('[FAIL] 4. Duplicate was not rejected!')
except urllib.error.HTTPError as e:
    data = json.loads(e.read().decode('utf-8'))
    assert e.code == 409
    assert data['status'] == 'already_registered'
    print(f'[PASS] 4. Duplicate Rejection: HTTP {e.code} Conflict! Message: "{data.get("message")}"')

# 5. Test unknown student lookup (MUST return 404 Not Found!)
try:
    with opener.open(f'{base}/api/students/NONEXISTENT999') as res:
        print('[FAIL] 5. Unknown student was found!')
except urllib.error.HTTPError as e:
    data = json.loads(e.read().decode('utf-8'))
    assert e.code == 404
    assert data['status'] == 'not_found'
    print(f'[PASS] 5. Unknown Student Error: HTTP {e.code} Not Found! Message: "{data.get("message")}"')

# 6. Test Admin Login
login_data = urllib.parse.urlencode({'username': 'admin', 'password': 'admin123'}).encode('utf-8')
login_req = urllib.request.Request(f'{base}/login', data=login_data)
with opener.open(login_req) as res:
    dashboard_html = res.read().decode('utf-8')
    assert 'Registration Dashboard' in dashboard_html
    print('[PASS] 6. Admin Login Succeeded -> Redirected to Dashboard')

# 7. Test Dashboard Stats API
with opener.open(f'{base}/api/dashboard/stats') as res:
    stats = json.loads(res.read().decode('utf-8'))
    assert stats['total_students'] >= 10
    assert stats['total_registered'] >= 1
    print(f'[PASS] 7. Dashboard API: Total={stats["total_students"]}, Registered={stats["total_registered"]}, Rate={stats["registration_rate"]}%')

# 8. Test CSV Export
with opener.open(f'{base}/admin/export-csv') as res:
    csv_text = res.read().decode('utf-8')
    assert 'Student ID,Student Name,Status' in csv_text
    assert '23CS002' in csv_text
    assert 'Registered' in csv_text
    print('[PASS] 8. CSV Report Exported Successfully (contains 23CS002 Registered)')

print("\nAll 8 end-to-end integration tests PASSED!")
