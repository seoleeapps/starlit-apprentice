package com.seorilabs.starlit.agesignals;

import android.app.Activity;
import com.google.android.play.agesignals.AgeSignalsAccessRequest;
import com.google.android.play.agesignals.AgeSignalsException;
import com.google.android.play.agesignals.AgeSignalsManager;
import com.google.android.play.agesignals.AgeSignalsManagerFactory;
import com.google.android.play.agesignals.AgeSignalsRequest;
import com.google.android.play.agesignals.model.AgeSignalsErrorCode;
import java.util.Collections;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

/** Play Age Signals boundary. Does not store or send age information to other SDKs. */
public final class StarlitAgeSignals extends GodotPlugin {
    private static final String RESULT = "age_signals_result";
    private final AtomicInteger newestId = new AtomicInteger();
    private volatile boolean destroyed;
    private final Executor uiExecutor = this::runOnUiThread;
    private final AgeSignalsCoordinator coordinator;

    public StarlitAgeSignals(Godot godot) {
        super(godot);
        coordinator = new AgeSignalsCoordinator(new PlayProvider(), (id, signal) ->
            runOnRenderThread(() -> {
                if (!destroyed && id == newestId.get()) {
                    emitSignal(RESULT, id, signal.status, signal.lower, signal.upper);
                }
            }));
    }

    @Override public String getPluginName() { return "StarlitAgeSignals"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        return Collections.singleton(new SignalInfo(RESULT,
            Integer.class, String.class, Integer.class, Integer.class));
    }

    @UsedByGodot public void requestAgeSignals(int requestId) {
        if (destroyed || requestId <= 0) return;
        int previous;
        do {
            previous = newestId.get();
            if (requestId <= previous) return;
        } while (!newestId.compareAndSet(previous, requestId));
        runOnUiThread(() -> {
            if (!destroyed && requestId == newestId.get()) coordinator.request(requestId);
        });
    }

    @Override public void onMainDestroy() {
        destroyed = true;
        coordinator.close();
        super.onMainDestroy();
    }

    @Override public void onGodotTerminating() {
        destroyed = true;
        runOnUiThread(coordinator::close);
        super.onGodotTerminating();
    }

    private static int failureCode(Exception exception) {
        // Never stringify, retain, log or emit the exception or its message.
        return exception instanceof AgeSignalsException
            ? ((AgeSignalsException) exception).getErrorCode() : AgeSignalsErrorCode.INTERNAL_ERROR;
    }

    private final class PlayProvider implements AgeSignalsCoordinator.Provider {
        private AgeSignalsManager manager;

        public void access(AgeSignalsCoordinator.Callback<Integer> callback) {
            Activity activity = getActivity();
            if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                callback.failure(AgeSignalsErrorCode.API_NOT_AVAILABLE);
                return;
            }
            if (manager == null) manager = AgeSignalsManagerFactory.create(activity.getApplicationContext());
            manager.requestAgeSignalsAccess(AgeSignalsAccessRequest.builder().setActivity(activity).build())
                .addOnSuccessListener(uiExecutor, result -> callback.success(
                    result == null ? null : result.ageSignalsStatus()))
                .addOnFailureListener(uiExecutor, exception -> callback.failure(failureCode(exception)));
        }

        public void signals(AgeSignalsCoordinator.Callback<AgeSignal> callback) {
            manager.checkAgeSignals(AgeSignalsRequest.builder().build())
                .addOnSuccessListener(uiExecutor, result -> callback.success(result == null
                    ? AgeSignal.status("not_shared")
                    : AgeSignal.fields(result.ageLower(), result.ageUpper(), result.significantChangeStatus())))
                .addOnFailureListener(uiExecutor, exception -> callback.failure(failureCode(exception)));
        }
    }
}
