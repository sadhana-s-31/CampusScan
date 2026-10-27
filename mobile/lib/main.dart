import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';
import 'services/local_database_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CampusScanApp());
}

class CampusScanApp extends StatelessWidget {
  const CampusScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusScan Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // CampusScan Navy
          primary: const Color(0xFF1E3A8A),
          secondary: const Color(0xFF0284C7),
          surface: const Color(0xFFF8FAFC),
        ),
        fontFamily: 'Roboto',
      ),
      home: const ScannerHomePage(),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  // Standalone Embedded Mode is ACTIVE by default
  bool _isOfflineMode = true;
  final LocalDatabaseService _localDb = LocalDatabaseService();

  // Optional external server URL (when offline mode is toggled off)
  String serverUrl = 'http://10.246.225.105:5000';

  final TextEditingController _manualIdController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _activeStudent;
  Map<String, dynamic>? _activeRegistration;

  @override
  void initState() {
    super.initState();
    // Warm up the embedded SQLite database
    _localDb.database.then((_) {}).catchError((_) {});
  }

  @override
  void dispose() {
    _manualIdController.dispose();
    super.dispose();
  }

  // --- Student Lookup & Registration Methods ---

  /// Search for student by ID (using embedded database or optional external server)
  Future<void> lookupStudent(String rawId) async {
    final studentId = rawId.trim().toUpperCase();
    if (studentId.isEmpty) {
      showSnackBar('Please enter or scan a valid Student ID', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _activeStudent = null;
      _activeRegistration = null;
    });

    if (_isOfflineMode) {
      // --- STANDALONE EMBEDDED ENGINE ---
      try {
        final data = await _localDb.lookupStudent(studentId);
        setState(() {
          _isLoading = false;
        });

        if (data['status'] == 'not_found' || data['success'] == false) {
          _showNotFoundDialog(studentId, data['message'] ?? 'Student not found.');
          return;
        }

        final student = data['student'];
        final status = data['status'];
        final registration = data['registration'];

        setState(() {
          _activeStudent = student;
          _activeRegistration = registration;
        });

        if (status == 'already_registered') {
          _showDuplicateDialog(student, registration);
        } else {
          showSnackBar('Student verified: ${student['name']}', isError: false);
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        showSnackBar('Local database error: $e', isError: true);
      }
      return;
    }

    // --- OPTIONAL EXTERNAL SERVER MODE ---
    try {
      final cleanBase = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
      final uri = Uri.parse('$cleanBase/api/students/${Uri.encodeComponent(studentId)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 404 || data['status'] == 'not_found') {
        _showNotFoundDialog(studentId, data['message'] ?? 'Student not found.');
        return;
      }

      if (response.statusCode == 200 && data['success'] == true) {
        final student = data['student'];
        final status = data['status'];
        final registration = data['registration'];

        setState(() {
          _activeStudent = student;
          _activeRegistration = registration;
        });

        if (status == 'already_registered') {
          _showDuplicateDialog(student, registration);
        } else {
          showSnackBar('Student verified: ${student['name']}', isError: false);
        }
      } else {
        showSnackBar(data['message'] ?? 'Error looking up student', isError: true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showConnectionErrorDialog(e.toString());
    }
  }

  /// Execute Registration
  Future<void> registerStudent() async {
    if (_activeStudent == null) return;
    final studentId = _activeStudent!['student_id'];

    setState(() {
      _isLoading = true;
    });

    if (_isOfflineMode) {
      // --- STANDALONE EMBEDDED ENGINE ---
      try {
        final data = await _localDb.registerStudent(studentId, registeredBy: 'mobile_standalone');
        setState(() {
          _isLoading = false;
        });

        if (data['success'] == true) {
          _showSuccessDialog(data['student'], data['registration']);
          setState(() {
            _activeStudent = data['student'];
            _activeRegistration = data['registration'];
          });
        } else if (data['status'] == 'already_registered') {
          _showDuplicateDialog(data['student'] ?? _activeStudent!, data['registration']);
        } else {
          showSnackBar(data['message'] ?? 'Registration failed', isError: true);
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        showSnackBar('Local database error: $e', isError: true);
      }
      return;
    }

    // --- OPTIONAL EXTERNAL SERVER MODE ---
    try {
      final cleanBase = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
      final uri = Uri.parse('$cleanBase/api/register');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': studentId,
          'registered_by': 'mobile_app',
        }),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 201 && data['success'] == true) {
        _showSuccessDialog(data['student'], data['registration']);
        setState(() {
          _activeStudent = data['student'];
          _activeRegistration = data['registration'];
        });
      } else if (response.statusCode == 409 || data['status'] == 'already_registered') {
        _showDuplicateDialog(data['student'] ?? _activeStudent!, data['registration']);
      } else {
        showSnackBar(data['message'] ?? 'Registration failed', isError: true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showConnectionErrorDialog(e.toString());
    }
  }

  // --- Barcode Scanner Action ---

  Future<void> startBarcodeScanner() async {
    try {
      final res = await SimpleBarcodeScanner.scanBarcode(
        context,
        isShowFlashIcon: true,
      );

      if (res != null && res != '-1' && res.trim().isNotEmpty) {
        _manualIdController.text = res.trim().toUpperCase();
        await lookupStudent(res);
      }
    } catch (e) {
      showSnackBar('Scanner error: $e', isError: true);
    }
  }

  // --- Dialogs ---

  /// Duplicate Registration Warning Dialog
  void _showDuplicateDialog(Map<String, dynamic> student, Map<String, dynamic>? reg) {
    final registeredAt = reg != null && reg['registered_at'] != null ? reg['registered_at'] : 'Previously recorded';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 32),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'You have already registered!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This student has already completed registration. Duplicate registrations are strictly prohibited.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  _buildStudentAvatar(student, radius: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['name'] ?? 'Student',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'ID: ${student['student_id']}',
                          style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registered: $registeredAt',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              resetView();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Another Student'),
          ),
        ],
      ),
    );
  }

  /// Registration Success Dialog
  void _showSuccessDialog(Map<String, dynamic> student, Map<String, dynamic> reg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 32),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Registration Successful!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildStudentAvatar(student, radius: 42),
            const SizedBox(height: 12),
            Text(
              student['name'] ?? 'Student',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${student['student_id']}',
              style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registered: ${reg['registered_at'] ?? 'Just now'}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context);
              resetView();
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Next Student'),
          ),
        ],
      ),
    );
  }

  /// Student Not Found Dialog
  void _showNotFoundDialog(String studentId, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red, size: 30),
            SizedBox(width: 10),
            Text('Student Not Found', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Scanned ID: $studentId',
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ),
            if (_isOfflineMode) ...[
              const SizedBox(height: 12),
              const Text(
                'Tip: You can add this student in "Records & Management" from the top menu.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_isOfflineMode)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showAddStudentDialog(initialId: studentId);
              },
              child: const Text('Add Student'),
            ),
        ],
      ),
    );
  }

  /// Connection Error Dialog (External Mode)
  void _showConnectionErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Server Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Could not communicate with the external backend server.'),
            const SizedBox(height: 8),
            Text('Target: $serverUrl', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Text('Details: $error', style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
            const SizedBox(height: 12),
            const Text(
              'Tip: Switch to "Standalone Offline Engine" in settings to run without any external server!',
              style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isOfflineMode = true;
              });
              showSnackBar('Switched to Standalone Offline Mode', isError: false);
            },
            child: const Text('Switch to Offline Mode'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Dialog to customize mode & server URL
  void _showServerConfigDialog() {
    final controller = TextEditingController(text: serverUrl);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.settings, color: Color(0xFF1E3A8A)),
              SizedBox(width: 8),
              Text('Application Mode'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Standalone Offline Engine', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  _isOfflineMode
                      ? 'No external server required. SQLite database is running inside this app.'
                      : 'Disabled (Connecting to external server)',
                  style: const TextStyle(fontSize: 12),
                ),
                value: _isOfflineMode,
                activeThumbColor: Colors.green,
                onChanged: (val) {
                  setDialogState(() {
                    _isOfflineMode = val;
                  });
                  setState(() {
                    _isOfflineMode = val;
                  });
                },
              ),
              const Divider(),
              if (!_isOfflineMode) ...[
                const Text('External Server URL:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.50:5000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Android Emulator: http://10.0.2.2:5000\n• Real Phone: Wi-Fi IPv4 address of laptop running python app.py.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'All student records, duplicate prevention, and verification run 100% locally on your phone without internet.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            if (!_isOfflineMode)
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    serverUrl = controller.text.trim();
                  });
                  Navigator.pop(context);
                  showSnackBar('Server URL updated to: $serverUrl', isError: false);
                },
                child: const Text('Save URL'),
              ),
          ],
        ),
      ),
    );
  }

  /// In-App Records & Management Sheet
  void _showRecordsManagementSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _localDb.getStats(),
          _localDb.getRegistrations(),
        ]).then((results) => {
              'stats': results[0] as Map<String, int>,
              'registrations': results[1] as List<Map<String, dynamic>>,
            }),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 350,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final stats = snapshot.data!['stats'] as Map<String, int>;
          final registrations = snapshot.data!['registrations'] as List<Map<String, dynamic>>;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Database & Records',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Stats Row
                  Row(
                    children: [
                      _buildStatBox('Total', '${stats['total']}', Colors.blue),
                      const SizedBox(width: 8),
                      _buildStatBox('Registered', '${stats['registered']}', Colors.green),
                      const SizedBox(width: 8),
                      _buildStatBox('Pending', '${stats['pending']}', Colors.amber.shade800),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddStudentDialog();
                        },
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Add Student'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final csv = await _localDb.exportRegistrationsCsv();
                          await Clipboard.setData(ClipboardData(text: csv));
                          if (context.mounted) {
                            showSnackBar('Registrations CSV copied to clipboard!', isError: false);
                          }
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy CSV'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () => _confirmResetRegistrations(context),
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('Reset All'),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  Text(
                    'Registered Students (${registrations.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),

                  if (registrations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No students registered yet.', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ...registrations.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: _buildStudentAvatar(r, radius: 22),
                            title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('ID: ${r['student_id']} • ${r['registered_at']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.redAccent, size: 20),
                              tooltip: 'Reset registration',
                              onPressed: () async {
                                await _localDb.resetRegistration(r['student_id']);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  showSnackBar('Registration reset for ${r['student_id']}', isError: false);
                                }
                                setState(() {
                                  _activeRegistration = null;
                                });
                              },
                            ),
                          ),
                        )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showAddStudentDialog({String initialId = ''}) {
    final idController = TextEditingController(text: initialId);
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Student Record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'e.g. 23CS011',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Student Name',
                hintText: 'e.g. Priya Sharma',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final id = idController.text.trim().toUpperCase();
              final name = nameController.text.trim();
              if (id.isEmpty || name.isEmpty) {
                showSnackBar('Please fill in both ID and Name', isError: true);
                return;
              }
              await _localDb.addStudent(id, name);
              if (context.mounted) {
                Navigator.pop(context);
                showSnackBar('Added student: $name ($id)', isError: false);
              }
              _manualIdController.text = id;
              lookupStudent(id);
            },
            child: const Text('Add & Lookup'),
          ),
        ],
      ),
    );
  }

  void _confirmResetRegistrations(BuildContext sheetContext) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Registrations?'),
        content: const Text(
          'This will clear all registration records from the local database. All students will become eligible to register again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await _localDb.resetAllRegistrations();
              if (context.mounted) {
                Navigator.pop(context);
              }
              if (sheetContext.mounted) {
                Navigator.pop(sheetContext);
              }
              resetView();
              showSnackBar('All registrations have been reset.', isError: false);
            },
            child: const Text('Reset All'),
          ),
        ],
      ),
    );
  }

  // --- Helper Methods ---

  Widget _buildStudentAvatar(Map<String, dynamic> student, {double radius = 28}) {
    final photoAsset = student['photo_asset'] as String?;
    final photoUrl = student['photo_url'] as String? ?? (_isOfflineMode ? null : _resolvePhotoUrl(student['student_id'] ?? ''));

    ImageProvider? imageProvider;
    if (photoAsset != null && photoAsset.isNotEmpty) {
      imageProvider = AssetImage(photoAsset);
    } else if (photoUrl != null && photoUrl.isNotEmpty && !_isOfflineMode) {
      imageProvider = NetworkImage(photoUrl);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE2E8F0),
      backgroundImage: imageProvider,
      onBackgroundImageError: imageProvider != null ? (_, __) {} : null,
      child: imageProvider == null
          ? Text(
              (student['name'] != null && (student['name'] as String).isNotEmpty)
                  ? (student['name'] as String).substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
                color: const Color(0xFF1E3A8A),
              ),
            )
          : null,
    );
  }

  String _resolvePhotoUrl(String studentId) {
    final cleanBase = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return '$cleanBase/students/photo/${Uri.encodeComponent(studentId)}';
  }

  void resetView() {
    setState(() {
      _activeStudent = null;
      _activeRegistration = null;
      _manualIdController.clear();
    });
  }

  void showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- Main Build UI ---

  @override
  Widget build(BuildContext context) {
    final isRegistered = _activeRegistration != null;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner, color: Colors.white),
            SizedBox(width: 8),
            Text('CampusScan Mobile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.white),
            tooltip: 'Database & Records',
            onPressed: _showRecordsManagementSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings & Mode',
            onPressed: _showServerConfigDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isOfflineMode ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isOfflineMode ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOfflineMode ? Icons.offline_bolt : Icons.wifi,
                    color: _isOfflineMode ? const Color(0xFF059669) : const Color(0xFF2563EB),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isOfflineMode
                          ? 'Standalone Offline Engine Active (No server needed)'
                          : 'Online Server Mode: $serverUrl',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _isOfflineMode ? const Color(0xFF065F46) : const Color(0xFF1E40AF),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _showServerConfigDialog,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isOfflineMode ? const Color(0xFF047857) : const Color(0xFF1D4ED8),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Top Scanner Banner Button
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.camera_alt_outlined, size: 48, color: Colors.white),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan Student ID Card',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Point camera at Code 128, Code 39 or QR Code',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E3A8A),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: startBarcodeScanner,
                      icon: const Icon(Icons.qr_code_scanner, size: 24),
                      label: const Text('Open Camera Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Manual Search Card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manual Lookup',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualIdController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'e.g. 23CS001',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onSubmitted: lookupStudent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => lookupStudent(_manualIdController.text),
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Quick Test Chips:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: ['23CS001', '23CS002', '23CS003', '732925CSR131', 'UNKNOWN99'].map((id) {
                        return ActionChip(
                          label: Text(id, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            _manualIdController.text = id;
                            lookupStudent(id);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Profile Verification Section
            if (_isLoading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_activeStudent != null) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildStudentAvatar(_activeStudent!, radius: 46),
                      const SizedBox(height: 12),
                      Text(
                        _activeStudent!['name'] ?? 'Unknown Name',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _activeStudent!['student_id'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isRegistered) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Already Registered at: ${_activeRegistration!['registered_at']}',
                                  style: const TextStyle(
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: resetView,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Scan Another Student'),
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: registerStudent,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text(
                            'Confirm & Register Student',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
