package com.vdamov3.cashier_trae;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.vision.imageembedder.ImageEmbedder;
import com.google.mediapipe.tasks.vision.imageembedder.ImageEmbedderResult;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Runs a bundled image model locally. Product samples and matching stay in the app database. */
public class AiEmbeddingChannel implements MethodChannel.MethodCallHandler {
    private final Context context;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private ImageEmbedder embedder;

    public AiEmbeddingChannel(Context context) {
        this.context = context.getApplicationContext();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("diagnosticsPath".equals(call.method)) {
            boolean debug = (context.getApplicationInfo().flags
                    & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
            if (debug && context.getPackageName().endsWith(".visiondev")) {
                java.io.File directory = new java.io.File(context.getFilesDir(), "vision-diagnostics");
                if (directory.isDirectory() || directory.mkdirs()) {
                    result.success(directory.getAbsolutePath());
                } else {
                    result.error("DIAGNOSTICS_UNAVAILABLE", "Cannot open diagnostic directory", null);
                }
            } else {
                result.error("DIAGNOSTICS_DISABLED", "Diagnostics are only available in the isolated debug app", null);
            }
            return;
        }
        if (!"embedImage".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String path = call.argument("path");
        if (path == null || path.isEmpty()) {
            result.error("INVALID_IMAGE", "Missing image path", null);
            return;
        }
        worker.execute(() -> {
            try {
                if (embedder == null) {
                    BaseOptions base = BaseOptions.builder()
                            .setModelAssetPath("mobilenet_v3_small.tflite")
                            .build();
                    ImageEmbedder.ImageEmbedderOptions options =
                            ImageEmbedder.ImageEmbedderOptions.builder()
                                    .setBaseOptions(base)
                                    .build();
                    embedder = ImageEmbedder.createFromOptions(context, options);
                }
                BitmapFactory.Options decode = new BitmapFactory.Options();
                decode.inSampleSize = 2;
                Bitmap bitmap = BitmapFactory.decodeFile(path, decode);
                if (bitmap == null) {
                    throw new IllegalArgumentException("Could not decode camera image");
                }
                double brightness = averageBrightness(bitmap);
                Log.i("ScaleAiCamera", "Captured frame " + bitmap.getWidth() + "x"
                        + bitmap.getHeight() + ", average brightness " + brightness);
                if (brightness < 12) {
                    bitmap.recycle();
                    mainHandler.post(() -> result.error("IMAGE_TOO_DARK",
                            "Camera image is too dark", null));
                    return;
                }
                ImageEmbedderResult embedding = embedder.embed(
                        new BitmapImageBuilder(bitmap).build());
                float[] values = embedding.embeddingResult().embeddings().get(0)
                        .floatEmbedding();
                if (values == null || values.length == 0) {
                    throw new IllegalStateException("Model returned no float embedding");
                }
                List<Double> output = new ArrayList<>(values.length);
                for (float value : values) output.add((double) value);
                bitmap.recycle();
                mainHandler.post(() -> result.success(output));
            } catch (Throwable error) {
                mainHandler.post(() -> result.error(
                        "EMBED_FAILED", error.getMessage(), null));
            }
        });
    }

    private static double averageBrightness(Bitmap bitmap) {
        long total = 0;
        int count = 0;
        for (int y = 0; y < bitmap.getHeight(); y += Math.max(1, bitmap.getHeight() / 16)) {
            for (int x = 0; x < bitmap.getWidth(); x += Math.max(1, bitmap.getWidth() / 16)) {
                int pixel = bitmap.getPixel(x, y);
                total += ((pixel >> 16) & 255) * 299L;
                total += ((pixel >> 8) & 255) * 587L;
                total += (pixel & 255) * 114L;
                count++;
            }
        }
        return total / (count * 1000.0);
    }

    public void close() {
        worker.execute(() -> {
            if (embedder != null) embedder.close();
            embedder = null;
        });
        worker.shutdown();
    }
}
