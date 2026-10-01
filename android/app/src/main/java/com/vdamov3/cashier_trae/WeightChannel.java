package com.vdamov3.cashier_trae;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import com.weight.serialport.SerialPort;
import com.weight.serialport.SerialPortConfig;
import com.weight.serialport.SerialPortDevices;
import com.weight.serialport.sdk.until.SerialMessageUtil;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class WeightChannel implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private static final String TAG = "WeightChannel";
    private static final String PATCH_VER = "WCH_PATCH_20260303_C_RAW";
    private static final int FRAME_LEN = 16;
    private static final int MAX_BUFFER_BYTES = 4096;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink eventSink;

    private final ByteArrayOutputStream byteBuffer = new ByteArrayOutputStream();
    private SerialPort serialPort;
    private InputStream inputStream;
    private OutputStream outputStream;
    private Thread readThread;
    private volatile boolean reading = false;
    private volatile long readerGeneration = 0;
    private long frameCount = 0;

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "open": {
                String path = call.argument("path");
                Integer rate = call.argument("rate");
                if (path == null) path = "/dev/ttyS4";
                if (rate == null) rate = 9600;
                boolean ok = openSerial(path, rate);
                result.success(ok);
                break;
            }
            case "close":
                closeSerial();
                result.success(true);
                break;
            case "tare":
                result.success(sendCommand(SerialMessageUtil.getInstance().setting_remove_peel()));
                break;
            case "zero":
                result.success(sendCommand(SerialMessageUtil.getInstance().setting_zero()));
                break;
            case "requestWeight":
                result.success(sendCommand(SerialMessageUtil.getInstance().send_weight()));
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
    }

    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }

    private boolean openSerial(String path, int rate) {
        closeSerial();
        try {
            SerialPortConfig.initSerial(path, rate, 0, 8, 1);
            serialPort = SerialPortDevices.getInstance().getSerialPort();
            if (serialPort == null) {
                Log.e(TAG, PATCH_VER + " open failed: serialPort null");
                return false;
            }
            inputStream = serialPort.getInputStream();
            outputStream = serialPort.getOutputStream();
            byteBuffer.reset();
            frameCount = 0;
            startReadLoop();
            return true;
        } catch (Throwable t) {
            Log.e(TAG, PATCH_VER + " open exception", t);
            closeSerial();
            return false;
        }
    }

    private void closeSerial() {
        readerGeneration++;
        reading = false;
        if (readThread != null) {
            readThread.interrupt();
            readThread = null;
        }
        try {
            if (inputStream != null) inputStream.close();
        } catch (IOException ignored) {
        }
        try {
            if (outputStream != null) outputStream.close();
        } catch (IOException ignored) {
        }
        inputStream = null;
        outputStream = null;
        serialPort = null;
        try {
            SerialPortDevices.getInstance().closeSerialPort();
        } catch (Throwable ignored) {
        }
        byteBuffer.reset();
    }

    private boolean sendCommand(byte[] cmd) {
        if (cmd == null || outputStream == null) return false;
        try {
            outputStream.write(cmd);
            outputStream.flush();
            return true;
        } catch (IOException e) {
            Log.e(TAG, PATCH_VER + " send command failed", e);
            return false;
        }
    }

    private void startReadLoop() {
        if (inputStream == null) return;
        final InputStream readerInput = inputStream;
        final long generation = readerGeneration;
        reading = true;
        readThread = new Thread(() -> {
            byte[] buf = new byte[128];
            while (reading && generation == readerGeneration && !Thread.currentThread().isInterrupted()) {
                try {
                    int n = readerInput.read(buf);
                    if (n <= 0) continue;
                    if (generation != readerGeneration) break;
                    appendAndParse(buf, n);
                } catch (IOException e) {
                    if (reading) {
                        Log.e(TAG, PATCH_VER + " read failed", e);
                    }
                    break;
                } catch (Throwable t) {
                    Log.e(TAG, PATCH_VER + " parse failed", t);
                }
            }
        }, "WeightRawReader");
        readThread.start();
    }

    public void shutdown() {
        onCancel(null);
        closeSerial();
    }

    private synchronized void appendAndParse(byte[] chunk, int size) {
        byteBuffer.write(chunk, 0, size);
        byte[] accumulated = byteBuffer.toByteArray();
        byteBuffer.reset();

        if (accumulated.length > MAX_BUFFER_BYTES) {
            int keepFrom = Math.max(0, accumulated.length - 256);
            byteBuffer.write(accumulated, keepFrom, accumulated.length - keepFrom);
            Log.w(TAG, PATCH_VER + " buffer overflow guarded");
            return;
        }

        int i = 0;
        while (i <= accumulated.length - FRAME_LEN) {
            if ((accumulated[i] & 0xFF) == 0x01
                    && (accumulated[i + 1] & 0xFF) == 0x02
                    && (accumulated[i + 13] & 0xFF) == 0x03
                    && (accumulated[i + 14] & 0xFF) == 0x04) {
                byte[] frame = Arrays.copyOfRange(accumulated, i, i + FRAME_LEN);
                emitFrame(frame);
                frameCount++;
                i += FRAME_LEN;
            } else {
                i++;
            }
        }

        if (i < accumulated.length) {
            byteBuffer.write(accumulated, i, accumulated.length - i);
        }
    }

    private void emitFrame(byte[] frame) {
        char state1 = (char) (frame[2] & 0xFF);
        boolean isPlus = (frame[3] & 0xFF) != '-';
        String weightString = new String(frame, 4, 6, StandardCharsets.US_ASCII);
        String unit = new String(frame, 10, 2, StandardCharsets.US_ASCII);

        double netWeight = 0.0;
        try {
            netWeight = Double.parseDouble(weightString) * (isPlus ? 1.0 : -1.0);
        } catch (NumberFormatException e) {
            Log.w(TAG, PATCH_VER + " invalid weight string: " + weightString);
            return;
        }

        int state2 = frame[15] & 0xFF;
        boolean isZero = ((state2 >> 4) & 1) == 1;
        boolean isTare = ((state2 >> 5) & 1) == 1;
        boolean isOverWeight = (state1 == 'F') || (((state2 >> 6) & 1) == 1);
        boolean stable = state1 == 'S';
        // 价格按 kg 计算；其他单位不能直接当 kg 入单。
        boolean valid = (state1 != 'F') && !isOverWeight
                && "kg".equalsIgnoreCase(unit.trim());

        StringBuilder sb = new StringBuilder();
        for (byte b : frame) sb.append(String.format("%02X", b & 0xFF));
        final String rawHex = sb.toString();
        final double fKg = netWeight;
        final boolean fStable = stable;
        final boolean fValid = valid;
        final boolean fZero = isZero;
        final boolean fTare = isTare;
        final String fUnit = unit;
        // Per-frame logs are intentionally disabled to avoid logcat spam.

        mainHandler.post(() -> {
            if (eventSink == null) return;
            Map<String, Object> map = new HashMap<>();
            map.put("raw", rawHex);
            map.put("kg", fKg);
            map.put("netWeight", fKg);
            map.put("stable", fStable);
            map.put("isStable", fStable);
            map.put("valid", fValid);
            map.put("isZero", fZero);
            map.put("isTare", fTare);
            map.put("unit", fUnit);
            eventSink.success(map);
        });
    }
}
