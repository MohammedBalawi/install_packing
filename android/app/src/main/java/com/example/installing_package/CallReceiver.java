package com.example.installing_package;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.telephony.TelephonyManager;
import android.util.Log;

public class CallReceiver extends BroadcastReceiver {

    private static boolean isRecording = false;

    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);

            if (TelephonyManager.EXTRA_STATE_OFFHOOK.equals(state)) {
                Log.d("CallReceiver", "📞 Call started");
                if (!isRecording) {
                    isRecording = true;
                    Intent serviceIntent = new Intent(context, CallRecordingService.class);
                    context.startForegroundService(serviceIntent);
                }

            } else if (TelephonyManager.EXTRA_STATE_IDLE.equals(state)) {
                Log.d("CallReceiver", "📞 Call ended");
                if (isRecording) {
                    isRecording = false;
                    Intent stopIntent = new Intent(context, CallRecordingService.class);
                    context.stopService(stopIntent);
                }
            }

        } catch (Exception e) {
            Log.e("CallReceiver", "Error: " + e.getMessage());
        }
    }
}
