package com.seorilabs.starlit.agesignals;

import com.google.android.play.agesignals.model.AgeSignalsStatus;

/** UI-thread-confined request lifetime. Stores only one active and one latest ID. */
final class AgeSignalsCoordinator {
    interface Callback<T> {
        void success(T value);
        void failure(int code);
    }
    interface Provider {
        void access(Callback<Integer> callback);
        void signals(Callback<AgeSignal> callback);
    }
    interface Sink { void result(int requestId, AgeSignal signal); }

    private final Provider provider;
    private final Sink sink;
    private int latestId;
    private Attempt active;
    private boolean closed;

    private static final class Attempt {
        final int id;
        boolean readingSignals;
        Attempt(int id) { this.id = id; }
    }

    AgeSignalsCoordinator(Provider provider, Sink sink) {
        this.provider = provider;
        this.sink = sink;
    }

    void request(int requestId) {
        if (closed || requestId <= latestId) return;
        latestId = requestId;
        if (active == null) start(requestId);
    }

    private void start(int id) {
        Attempt attempt = new Attempt(id);
        active = attempt;
        try {
            provider.access(new Callback<Integer>() {
                public void success(Integer status) { accessCompleted(attempt, status); }
                public void failure(int code) {
                    if (isActive(attempt) && !attempt.readingSignals) {
                        finish(attempt, AgeSignal.failure(code));
                    }
                }
            });
        } catch (RuntimeException ignored) {
            if (isActive(attempt) && !attempt.readingSignals) finish(attempt, AgeSignal.status("error"));
        }
    }

    private boolean isActive(Attempt attempt) { return !closed && active == attempt; }

    private void accessCompleted(Attempt attempt, Integer status) {
        if (!isActive(attempt) || attempt.readingSignals) return;
        if (attempt.id != latestId) {
            finish(attempt, null);
        } else if (status == null || status == AgeSignalsStatus.NOT_SHARED) {
            finish(attempt, AgeSignal.status("not_shared"));
        } else if (status == AgeSignalsStatus.VERIFICATION_REQUIRED) {
            // Provider explicitly describes this as an unknown age requiring verification.
            finish(attempt, AgeSignal.status("unknown"));
        } else if (status == AgeSignalsStatus.SHARED) {
            attempt.readingSignals = true;
            try {
                provider.signals(new Callback<AgeSignal>() {
                    public void success(AgeSignal signal) {
                        if (isActive(attempt)) finish(attempt,
                            signal == null ? AgeSignal.status("not_shared") : signal);
                    }
                    public void failure(int code) {
                        if (isActive(attempt)) finish(attempt, AgeSignal.failure(code));
                    }
                });
            } catch (RuntimeException ignored) {
                if (isActive(attempt)) finish(attempt, AgeSignal.status("error"));
            }
        } else {
            finish(attempt, AgeSignal.status("error"));
        }
    }

    private void finish(Attempt attempt, AgeSignal result) {
        if (!isActive(attempt)) return;
        active = null;
        if (attempt.id == latestId && result != null) sink.result(attempt.id, result);
        if (!closed && active == null && latestId > attempt.id) start(latestId);
    }

    void close() {
        closed = true;
        active = null;
        latestId = 0;
    }
}
