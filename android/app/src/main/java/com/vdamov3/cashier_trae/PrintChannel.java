package com.vdamov3.cashier_trae;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.util.Log;

import com.caysn.autoreplyprint.AutoReplyPrint;
import com.sun.jna.Pointer;
import com.sunmi.peripheral.printer.InnerPrinterCallback;
import com.sunmi.peripheral.printer.InnerPrinterManager;
import com.sunmi.peripheral.printer.InnerResultCallback;
import com.sunmi.peripheral.printer.SunmiPrinterService;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * 打印通道 — 商米内置打印机或 autoreplyprint AAR 的 USB 打印机。
 * 泰文通过 Android Canvas 渲染成 Bitmap 再打印，绕过编码限制。
 * MethodChannel: "cashier/print"
 */
public class PrintChannel implements MethodChannel.MethodCallHandler {

    private static final String TAG = "PrintChannel";
    private static final int PAPER_WIDTH = 384;   // 58mm 热敏打印机标准宽度(点)
    private static final int FONT_SIZE_NORMAL = 28;
    private static final int FONT_SIZE_TITLE = 36;
    private static final int FONT_SIZE_TOTAL = 40;

    private Pointer hPrinter = Pointer.NULL;
    private final Context context;
    private final boolean isSunmi = "SUNMI".equalsIgnoreCase(Build.MANUFACTURER);
    private volatile SunmiPrinterService sunmiPrinter;
    private volatile CountDownLatch sunmiReady = new CountDownLatch(1);
    private boolean sunmiBound = false;
    private final InnerPrinterCallback sunmiCallback = new InnerPrinterCallback() {
        @Override
        protected void onConnected(SunmiPrinterService service) {
            sunmiPrinter = service;
            sunmiReady.countDown();
            Log.i(TAG, "SUNMI printer service connected");
        }

        @Override
        protected void onDisconnected() {
            sunmiPrinter = null;
            Log.w(TAG, "SUNMI printer service disconnected");
        }
    };

    public PrintChannel(Context context) {
        this.context = context;
    }

    public void shutdown() {
        // Do not block Activity teardown while a physical ticket finishes.
        new Thread(this::closePort, "PrinterShutdown").start();
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "openPort":
                new Thread(() -> {
                    boolean ok = openPort();
                    new Handler(Looper.getMainLooper()).post(() -> result.success(ok));
                }, "PrinterConnect").start();
                break;

            case "closePort":
                closePort();
                result.success(true);
                break;

            case "isConnected":
                result.success(isSunmi
                        ? sunmiPrinter != null && sunmiPrinter.asBinder().isBinderAlive()
                        : AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter));
                break;

            case "printTicket":
                // 在子线程执行打印，避免阻塞 UI
                new Thread(() -> {
                    boolean ok = false;
                    try {
                        ok = executePrint(call);
                    } catch (Throwable e) {
                        Log.e(TAG, "Print exception", e);
                    }
                    final boolean finalOk = ok;
                    new Handler(Looper.getMainLooper()).post(() -> result.success(finalOk));
                }).start();
                break;

            default:
                result.notImplemented();
        }
    }

    // ── 端口管理 ──────────────────────────────────────────────

    private synchronized boolean openPort() {
        if (isSunmi) return openSunmiPort();
        if (AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter)) {
            return true;
        }
        AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
        hPrinter = Pointer.NULL;

        String portName = findPrinterPort();
        if (portName == null) {
            Log.e(TAG, "No USB printer found");
            return false;
        }
        Log.d(TAG, "Opening printer: " + portName);
        hPrinter = AutoReplyPrint.INSTANCE.CP_Port_OpenUsb(portName, 1);
        boolean opened = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
        Log.d(TAG, "Printer opened: " + opened);
        return opened;
    }

    private boolean openSunmiPort() {
        if (sunmiPrinter != null && sunmiPrinter.asBinder().isBinderAlive()) return true;
        try {
            if (sunmiBound) {
                InnerPrinterManager.getInstance().unBindService(context, sunmiCallback);
                sunmiBound = false;
            }
            sunmiReady = new CountDownLatch(1);
            sunmiBound = InnerPrinterManager.getInstance().bindService(context, sunmiCallback);
            if (!sunmiBound) return false;
            return sunmiReady.await(5, TimeUnit.SECONDS)
                    && sunmiPrinter != null && sunmiPrinter.asBinder().isBinderAlive();
        } catch (Throwable e) {
            Log.e(TAG, "SUNMI printer bind failed", e);
            return false;
        }
    }

    private synchronized void closePort() {
        if (isSunmi) {
            if (sunmiBound) {
                try {
                    InnerPrinterManager.getInstance().unBindService(context, sunmiCallback);
                } catch (Throwable e) {
                    Log.w(TAG, "SUNMI printer unbind failed", e);
                }
            }
            sunmiBound = false;
            sunmiPrinter = null;
            return;
        }
        if (hPrinter != Pointer.NULL) {
            AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
            hPrinter = Pointer.NULL;
        }
    }

    /** 枚举 USB 设备，找到已知 VID 的打印机 */
    private String findPrinterPort() {
        UsbManager usbManager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
        if (usbManager == null) {
            Log.e(TAG, "findPrinterPort: UsbManager is null");
            return null;
        }
        HashMap<String, UsbDevice> devices = usbManager.getDeviceList();
        // ① 列出所有 USB 设备，方便排查 VID/PID
        if (devices.isEmpty()) {
            Log.w(TAG, "findPrinterPort: no USB devices found");
        } else {
            for (UsbDevice d : devices.values()) {
                Log.d(TAG, String.format("USB device: name=%s VID=0x%04X PID=0x%04X class=%d",
                        d.getDeviceName(), d.getVendorId(), d.getProductId(), d.getDeviceClass()));
            }
        }
        for (UsbDevice d : devices.values()) {
            int vid = d.getVendorId();
            if (vid == 0x4B43 || vid == 0x0fe6) {
                String port = String.format("VID:0x%04X,PID:0x%04X", vid, d.getProductId());
                Log.d(TAG, "findPrinterPort: matched printer " + port);
                return port;
            }
        }
        Log.w(TAG, "findPrinterPort: no matching printer VID found (want 0x4B43 or 0x0FE6)");
        return null;
    }

    // ── 打印逻辑 ──────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private synchronized boolean executePrint(MethodCall call) {
        if (!openPort()) {
            Log.e(TAG, "executePrint: openPort failed, abort");
            return false;
        }

        String shopName = call.argument("shopName");
        String totalLabel = call.argument("totalLabel");
        List<Map<String, Object>> items = call.argument("items");
        Object totalArg = call.argument("total");
        double total = totalArg instanceof Number ? ((Number) totalArg).doubleValue() : 0;

        Log.d(TAG, "executePrint: shopName=" + shopName
                + " items=" + (items != null ? items.size() : 0)
                + " total=" + total);

        Bitmap bmp = renderTicket(shopName, totalLabel, items, total);
        if (bmp == null) {
            Log.e(TAG, "executePrint: renderTicket returned null");
            return false;
        }
        if (isSunmi) {
            try {
                SunmiPrinterService service = sunmiPrinter;
                if (service == null) return false;
                int state = service.updatePrinterState();
                if (state != 1) {
                    Log.w(TAG, "SUNMI printer not ready, state=" + state);
                    return false;
                }
                CountDownLatch finished = new CountDownLatch(1);
                AtomicBoolean printed = new AtomicBoolean(false);
                InnerResultCallback callback = new InnerResultCallback() {
                    @Override
                    public void onRunResult(boolean success) {
                        if (!success) finished.countDown();
                    }

                    @Override
                    public void onReturnString(String value) {}

                    @Override
                    public void onRaiseException(int code, String message) {
                        Log.e(TAG, "SUNMI print exception code=" + code + " message=" + message);
                        finished.countDown();
                    }

                    @Override
                    public void onPrintResult(int code, String message) {
                        printed.set(code == 0);
                        Log.i(TAG, "SUNMI print result code=" + code + " message=" + message);
                        finished.countDown();
                    }
                };
                service.enterPrinterBuffer(true);
                service.printBitmap(bmp, null);
                service.lineWrap(3, null);
                service.exitPrinterBufferWithCallback(true, callback);
                boolean completed = finished.await(15, TimeUnit.SECONDS);
                Log.i(TAG, "SUNMI ticket completed=" + completed + " printed=" + printed.get()
                        + " width=" + bmp.getWidth() + " height=" + bmp.getHeight());
                return completed && printed.get();
            } catch (Throwable e) {
                Log.e(TAG, "SUNMI print failed", e);
                return false;
            } finally {
                bmp.recycle();
            }
        }
        // ② 打出位图尺寸，确认渲染结果
        Log.d(TAG, "executePrint: bitmap " + bmp.getWidth() + "x" + bmp.getHeight()
                + " config=" + bmp.getConfig());

        Log.d(TAG, "executePrint: calling PrintRasterImageFromBitmap...");
        boolean ok = AutoReplyPrint.CP_Pos_PrintRasterImageFromData_Helper.PrintRasterImageFromBitmap(
                hPrinter,
                bmp.getWidth(), bmp.getHeight(), bmp,
                AutoReplyPrint.CP_ImageBinarizationMethod_ErrorDiffusion,
                AutoReplyPrint.CP_ImageCompressionMethod_None);
        Log.d(TAG, "executePrint: PrintRasterImageFromBitmap result=" + ok);

        if (ok) {
            boolean cut = AutoReplyPrint.INSTANCE.CP_Pos_HalfCutPaper(hPrinter);
            Log.d(TAG, "executePrint: HalfCutPaper result=" + cut);
        }
        bmp.recycle();
        return ok;
    }

    /**
     * 将收据内容渲染为 Bitmap。
     * 使用 Android 系统字体渲染当前语言的 Unicode 文案。
     */
    @SuppressWarnings("unchecked")
    private Bitmap renderTicket(String shopName, String totalLabel,
                                List<Map<String, Object>> items, double total) {
        String dateTime = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
                .format(new Date());

        // ── 构建内容字符串 ─────────────────────────────────────
        String title = (shopName != null && !shopName.trim().isEmpty()) ? shopName.trim() : "Store";
        String receiptTotalLabel = (totalLabel != null && !totalLabel.trim().isEmpty())
                ? totalLabel.trim() : "Total";

        int totalDigits = 0;
        StringBuilder detail = new StringBuilder();
        detail.append(dateTime).append("\n");
        detail.append(line('-', 32)).append("\n");
        if (items != null) {
            for (Map<String, Object> item : items) {
                String name = str(item.get("name"));
                double weight = num(item.get("weight"));
                double price = num(item.get("price"));
                double subtotal = num(item.get("subtotal"));
                boolean byWeight = Boolean.TRUE.equals(item.get("byWeight"));
                int wd = item.containsKey("weightDigits") ? Math.max(0, Math.min(3, (int) num(item.get("weightDigits")))) : 3;
                int md = item.containsKey("moneyDigits") ? Math.max(0, Math.min(2, (int) num(item.get("moneyDigits")))) : 2;
                totalDigits = Math.max(totalDigits, md);

                detail.append(name).append("\n");
                if (byWeight) {
                    detail.append(String.format(Locale.US, "  %." + wd + "f kg × %." + md + "f฿ = %." + md + "f฿\n", weight, price, subtotal));
                } else {
                    detail.append(String.format(Locale.US, "  x%.0f × %." + md + "f฿ = %." + md + "f฿\n", weight, price, subtotal));
                }
            }
        }
        detail.append(line('-', 32)).append("\n");
        detail.append(String.format(Locale.US, "%s: %." + totalDigits + "f ฿\n\n", receiptTotalLabel, total));

        // ③ 打出即将渲染的完整票据内容，方便核对语言和金额
        Log.d(TAG, "renderTicket title=[" + title + "]");
        Log.d(TAG, "renderTicket detail=[\n" + detail + "]");

        // ── 渲染到 Canvas ──────────────────────────────────────
        TextPaint paintTitle = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        paintTitle.setColor(Color.BLACK);
        paintTitle.setTextSize(FONT_SIZE_TITLE);
        paintTitle.setTypeface(Typeface.DEFAULT_BOLD);
        paintTitle.setTextAlign(Paint.Align.LEFT);

        TextPaint paintNormal = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        paintNormal.setColor(Color.BLACK);
        paintNormal.setTextSize(FONT_SIZE_NORMAL);
        paintNormal.setTypeface(Typeface.DEFAULT);

        int w = PAPER_WIDTH - 20; // 左右各留 10px 边距

        StaticLayout titleLayout = StaticLayout.Builder
                .obtain(title, 0, title.length(), paintTitle, w)
                .setAlignment(Layout.Alignment.ALIGN_CENTER)
                .build();

        StaticLayout detailLayout = StaticLayout.Builder
                .obtain(detail, 0, detail.length(), paintNormal, w)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .build();

        int totalH = 16 + titleLayout.getHeight() + 12 + detailLayout.getHeight();
        Log.d(TAG, "renderTicket titleH=" + titleLayout.getHeight()
                + " detailH=" + detailLayout.getHeight()
                + " totalH=" + totalH + " w=" + PAPER_WIDTH);

        Bitmap bmp = Bitmap.createBitmap(PAPER_WIDTH, totalH, Bitmap.Config.RGB_565);
        Canvas canvas = new Canvas(bmp);
        canvas.drawColor(Color.WHITE);

        canvas.save();
        canvas.translate(10, 8);
        titleLayout.draw(canvas);
        canvas.restore();

        canvas.save();
        canvas.translate(10, 8 + titleLayout.getHeight() + 12);
        detailLayout.draw(canvas);
        canvas.restore();

        return bmp;
    }

    private static String line(char ch, int count) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < count; i++) sb.append(ch);
        return sb.toString();
    }

    private static String str(Object o) {
        return o != null ? o.toString() : "";
    }

    private static double num(Object o) {
        if (o instanceof Number) return ((Number) o).doubleValue();
        return 0.0;
    }
}
