import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _database;
  String? _documentsDirPath;

  Future<String> _getPhotosDirectoryPath() async {
    if (_documentsDirPath == null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        _documentsDirPath = dir.path;
      } catch (_) {
        final dbDirPath = await getDatabasesPath();
        _documentsDirPath = dbDirPath;
      }
    }
    final photosDir = Directory(p.join(_documentsDirPath!, 'student_photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir.path;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbDirPath = await getDatabasesPath();
    final dbPath = p.join(dbDirPath, 'campus_scan_students.db');

    final exists = await databaseExists(dbPath);
    if (!exists) {
      try {
        await Directory(dbDirPath).create(recursive: true);
        // Copy pre-populated database from bundled APK assets
        ByteData data = await rootBundle.load('assets/database/students.db');
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(dbPath).writeAsBytes(bytes, flush: true);
      } catch (e) {
        // If asset loading fails, SQLite will create a fresh database below
      }
    }

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS students (
            student_id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            photo_filename TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS registrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT NOT NULL UNIQUE REFERENCES students(student_id) ON DELETE CASCADE,
            registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            registered_by TEXT DEFAULT 'scanner',
            notes TEXT
          );
        ''');

        // Seed default sample students
        final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        final sampleStudents = [
          ['23CS001', 'Aarav Sharma'],
          ['23CS002', 'Diya Patel'],
          ['23CS003', 'Rohan Verma'],
          ['23CS004', 'Sneha Reddy'],
          ['23CS005', 'Vikram Singh'],
          ['23CS006', 'Ananya Joshi'],
          ['23CS007', 'Karthik Nair'],
          ['23CS008', 'Meera Iyer'],
          ['23CS009', 'Devendra Rao'],
          ['23CS010', 'Pooja Hegde'],
          ['732925CSR131', 'Sadhana R'],
        ];

        for (final s in sampleStudents) {
          await db.insert(
            'students',
            {
              'student_id': s[0],
              'name': s[1],
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      },
    );

    return db;
  }

  /// Resolve student photo from disk file, bundled assets, or known filenames
  String? resolveStudentPhotoAsset(String studentId, String? photoFilename) {
    final cleanId = studentId.trim().toUpperCase();

    // 1. Direct file on disk
    if (photoFilename != null && photoFilename.isNotEmpty) {
      if (File(photoFilename).existsSync()) {
        return photoFilename;
      }
      if (photoFilename.startsWith('assets/')) {
        return photoFilename;
      }
    }

    // 2. Check local student_photos directory
    if (_documentsDirPath != null) {
      for (final ext in ['.jpg', '.jpeg', '.png', '.webp']) {
        final localFile = File(p.join(_documentsDirPath!, 'student_photos', '$cleanId$ext'));
        if (localFile.existsSync()) {
          return localFile.path;
        }
      }
    }

    // 3. Known bundled assets
    final knownPhotos = {
      '23CS001': 'assets/students/23CS001.jpg',
      '23CS002': 'assets/students/23CS002.jpg',
      '23CS003': 'assets/students/23CS003.jpg',
      '23CS004': 'assets/students/23CS004.jpg',
      '23CS005': 'assets/students/23CS005.jpg',
      '732925CSR131': 'assets/students/732925CSR131.webp',
    };

    if (knownPhotos.containsKey(cleanId)) {
      return knownPhotos[cleanId];
    }
    if (photoFilename != null && photoFilename.isNotEmpty) {
      return 'assets/students/$photoFilename';
    }
    return null;
  }

  /// Lookup a student by ID, matching Flask GET /api/students/<student_id>
  Future<Map<String, dynamic>> lookupStudent(String rawId) async {
    final cleanId = rawId.trim().toUpperCase();
    if (cleanId.isEmpty) {
      return {
        'success': false,
        'status': 'error',
        'message': 'Student ID cannot be empty.',
      };
    }

    final db = await database;

    final studentRows = await db.query(
      'students',
      where: 'UPPER(student_id) = ?',
      whereArgs: [cleanId],
      limit: 1,
    );

    if (studentRows.isEmpty) {
      return {
        'success': false,
        'status': 'not_found',
        'message': 'Student not found. Please add the student record before registering.',
      };
    }

    final student = studentRows.first;
    final photoAsset = resolveStudentPhotoAsset(
      student['student_id'] as String,
      student['photo_filename'] as String?,
    );

    final regRows = await db.query(
      'registrations',
      where: 'UPPER(student_id) = ?',
      whereArgs: [cleanId],
      limit: 1,
    );

    if (regRows.isNotEmpty) {
      final reg = regRows.first;
      return {
        'success': true,
        'status': 'already_registered',
        'message': 'You have already registered!',
        'student': {
          'student_id': student['student_id'],
          'name': student['name'],
          'photo_asset': photoAsset,
          'has_photo': photoAsset != null,
        },
        'registration': {
          'registered_at': reg['registered_at'],
          'registered_by': reg['registered_by'],
          'notes': reg['notes'],
        },
      };
    }

    return {
      'success': true,
      'status': 'eligible',
      'message': 'Student found and eligible for registration.',
      'student': {
        'student_id': student['student_id'],
        'name': student['name'],
        'photo_asset': photoAsset,
        'has_photo': photoAsset != null,
      },
    };
  }

  /// Register student, matching Flask POST /api/register
  Future<Map<String, dynamic>> registerStudent(
    String rawId, {
    String registeredBy = 'mobile_app',
    String? notes,
  }) async {
    final cleanId = rawId.trim().toUpperCase();
    if (cleanId.isEmpty) {
      return {
        'success': false,
        'status': 'error',
        'message': 'Student ID is required.',
      };
    }

    final db = await database;

    final studentRows = await db.query(
      'students',
      where: 'UPPER(student_id) = ?',
      whereArgs: [cleanId],
      limit: 1,
    );

    if (studentRows.isEmpty) {
      return {
        'success': false,
        'status': 'not_found',
        'message': 'Student not found. Please add the student record before registering.',
      };
    }

    final student = studentRows.first;
    final photoAsset = resolveStudentPhotoAsset(
      student['student_id'] as String,
      student['photo_filename'] as String?,
    );

    // Enforce duplicate check
    final existingReg = await db.query(
      'registrations',
      where: 'UPPER(student_id) = ?',
      whereArgs: [cleanId],
      limit: 1,
    );

    if (existingReg.isNotEmpty) {
      final reg = existingReg.first;
      return {
        'success': false,
        'status': 'already_registered',
        'message': 'You have already registered!',
        'student': {
          'student_id': student['student_id'],
          'name': student['name'],
          'photo_asset': photoAsset,
        },
        'registration': {
          'registered_at': reg['registered_at'],
          'registered_by': reg['registered_by'],
          'notes': reg['notes'],
        },
      };
    }

    final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    try {
      await db.insert('registrations', {
        'student_id': student['student_id'],
        'registered_at': nowStr,
        'registered_by': registeredBy,
        'notes': notes,
      });

      return {
        'success': true,
        'status': 'registered',
        'message': 'Student registered successfully!',
        'student': {
          'student_id': student['student_id'],
          'name': student['name'],
          'photo_asset': photoAsset,
        },
        'registration': {
          'registered_at': nowStr,
          'registered_by': registeredBy,
          'notes': notes,
        },
      };
    } catch (e) {
      // Caught UNIQUE constraint violation
      final reg = (await db.query(
        'registrations',
        where: 'UPPER(student_id) = ?',
        whereArgs: [cleanId],
        limit: 1,
      )).firstOrNull;

      return {
        'success': false,
        'status': 'already_registered',
        'message': 'You have already registered!',
        'student': {
          'student_id': student['student_id'],
          'name': student['name'],
          'photo_asset': photoAsset,
        },
        'registration': {
          'registered_at': reg != null ? reg['registered_at'] : nowStr,
          'registered_by': reg != null ? reg['registered_by'] : registeredBy,
        },
      };
    }
  }

  /// Get stats: total students, registered, pending
  Future<Map<String, int>> getStats() async {
    final db = await database;
    final totalStudentsResult = await db.rawQuery('SELECT COUNT(*) as count FROM students');
    final totalRegisteredResult = await db.rawQuery('SELECT COUNT(*) as count FROM registrations');

    final total = Sqflite.firstIntValue(totalStudentsResult) ?? 0;
    final registered = Sqflite.firstIntValue(totalRegisteredResult) ?? 0;
    final pending = total - registered;

    return {
      'total': total,
      'registered': registered,
      'pending': pending > 0 ? pending : 0,
    };
  }

  /// Get list of all registrations with student names
  Future<List<Map<String, dynamic>>> getRegistrations() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT 
        r.id,
        r.student_id,
        r.registered_at,
        r.registered_by,
        s.name,
        s.photo_filename
      FROM registrations r
      JOIN students s ON UPPER(r.student_id) = UPPER(s.student_id)
      ORDER BY r.registered_at DESC
    ''');

    return results.map((row) {
      final map = Map<String, dynamic>.from(row);
      map['photo_asset'] = resolveStudentPhotoAsset(
        row['student_id'] as String,
        row['photo_filename'] as String?,
      );
      return map;
    }).toList();
  }

  /// Add a student directly on the device with optional profile photo
  Future<bool> addStudent(
    String studentId,
    String name, {
    String? photoPath,
  }) async {
    final cleanId = studentId.trim().toUpperCase();
    final cleanName = name.trim();
    if (cleanId.isEmpty || cleanName.isEmpty) return false;

    final db = await database;
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    String? savedPhotoPath;
    if (photoPath != null && photoPath.isNotEmpty) {
      final srcFile = File(photoPath);
      if (await srcFile.exists()) {
        try {
          final photosDirPath = await _getPhotosDirectoryPath();
          final ext = p.extension(photoPath).isNotEmpty ? p.extension(photoPath).toLowerCase() : '.jpg';
          final destPath = p.join(photosDirPath, '$cleanId$ext');
          final destFile = File(destPath);
          if (await destFile.exists()) {
            await destFile.delete();
          }
          await srcFile.copy(destPath);
          savedPhotoPath = destPath;
        } catch (_) {
          savedPhotoPath = photoPath;
        }
      }
    }

    final id = await db.insert(
      'students',
      {
        'student_id': cleanId,
        'name': cleanName,
        'photo_filename': savedPhotoPath,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return id > 0;
  }

  /// Reset registration for a specific student
  Future<bool> resetRegistration(String studentId) async {
    final cleanId = studentId.trim().toUpperCase();
    final db = await database;
    final count = await db.delete(
      'registrations',
      where: 'UPPER(student_id) = ?',
      whereArgs: [cleanId],
    );
    return count > 0;
  }

  /// Reset all registrations
  Future<int> resetAllRegistrations() async {
    final db = await database;
    return await db.delete('registrations');
  }

  /// Export registrations as CSV string
  Future<String> exportRegistrationsCsv() async {
    final list = await getRegistrations();
    final buffer = StringBuffer();
    buffer.writeln('Student ID,Name,Registered At,Registered By');
    for (final r in list) {
      final id = r['student_id'] ?? '';
      final name = (r['name'] ?? '').replaceAll('"', '""');
      final time = r['registered_at'] ?? '';
      final by = r['registered_by'] ?? '';
      buffer.writeln('"$id","$name","$time","$by"');
    }
    return buffer.toString();
  }
}
