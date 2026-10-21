package com.seorilabs.starlit.agesignals;

import static org.junit.Assert.*;
import com.google.android.play.agesignals.model.AgeSignalsStatus;
import java.util.ArrayList;
import java.util.List;
import org.junit.Test;

public final class AgeSignalsCoordinatorTest {
    static final class FakeProvider implements AgeSignalsCoordinator.Provider {
        final List<AgeSignalsCoordinator.Callback<Integer>> access = new ArrayList<>();
        final List<AgeSignalsCoordinator.Callback<AgeSignal>> signals = new ArrayList<>();
        public void access(AgeSignalsCoordinator.Callback<Integer> callback) { access.add(callback); }
        public void signals(AgeSignalsCoordinator.Callback<AgeSignal> callback) { signals.add(callback); }
    }
    static final class Observed {
        final int id;
        final AgeSignal signal;
        Observed(int id, AgeSignal signal) { this.id = id; this.signal = signal; }
    }
    final FakeProvider provider = new FakeProvider();
    final List<Observed> seen = new ArrayList<>();
    final AgeSignalsCoordinator coordinator = new AgeSignalsCoordinator(provider,
        (id, signal) -> seen.add(new Observed(id, signal)));

    @Test public void sharingIsCheckedBeforeRangeAndCompletionIsOnce() {
        coordinator.request(1);
        assertEquals(1, provider.access.size());
        assertTrue(provider.signals.isEmpty());
        provider.access.get(0).success(AgeSignalsStatus.SHARED);
        provider.access.get(0).success(AgeSignalsStatus.SHARED);
        assertEquals(1, provider.signals.size());
        provider.signals.get(0).success(new AgeSignal("shared", 13, 15));
        provider.signals.get(0).failure(-3);
        assertEquals(1, seen.size());
        assertEquals("shared", seen.get(0).signal.status);
        assertEquals(13, seen.get(0).signal.lower);
    }

    @Test public void sharingRefusalNeverRequestsRangeOrBecomesParentalDenial() {
        coordinator.request(1);
        provider.access.get(0).success(AgeSignalsStatus.NOT_SHARED);
        assertEquals("not_shared", seen.get(0).signal.status);
        assertEquals(-1, seen.get(0).signal.lower);
        assertTrue(provider.signals.isEmpty());
    }

    @Test public void requestsAreSerializedAndOnlyLatestWaitingIdSurvives() {
        coordinator.request(1);
        coordinator.request(1);
        coordinator.request(2);
        coordinator.request(3);
        coordinator.request(2);
        assertEquals(1, provider.access.size());
        provider.access.get(0).success(AgeSignalsStatus.SHARED);
        assertTrue(provider.signals.isEmpty());
        assertEquals(2, provider.access.size());
        assertTrue(seen.isEmpty());
        provider.access.get(0).failure(-3);
        assertEquals(2, provider.access.size());
        provider.access.get(1).success(AgeSignalsStatus.SHARED);
        provider.signals.get(0).success(new AgeSignal("shared", 18, -1));
        assertEquals(1, seen.size());
        assertEquals(3, seen.get(0).id);
        coordinator.request(3);
        assertEquals(2, provider.access.size());
    }

    @Test public void oldRangeSuccessAndFailureCannotOverwriteNewRequest() {
        coordinator.request(1);
        provider.access.get(0).success(AgeSignalsStatus.SHARED);
        coordinator.request(2);
        provider.signals.get(0).success(new AgeSignal("shared", 0, 12));
        provider.signals.get(0).failure(-100);
        assertTrue(seen.isEmpty());
        assertEquals(2, provider.access.size());
        provider.access.get(1).failure(-3);
        assertEquals(1, seen.size());
        assertEquals(2, seen.get(0).id);
        assertEquals("offline", seen.get(0).signal.status);
    }

    @Test public void verificationRequiredIsUnknownRatherThanNotApplicable() {
        coordinator.request(1);
        provider.access.get(0).success(AgeSignalsStatus.VERIFICATION_REQUIRED);
        assertEquals("unknown", seen.get(0).signal.status);
        coordinator.request(2);
        provider.access.get(1).success(9876);
        assertEquals("error", seen.get(1).signal.status);
    }

    @Test public void closedCoordinatorDropsPendingCallbacksAndRequests() {
        coordinator.request(1);
        coordinator.request(2);
        coordinator.close();
        provider.access.get(0).success(AgeSignalsStatus.SHARED);
        provider.access.get(0).failure(-3);
        coordinator.request(3);
        assertEquals(1, provider.access.size());
        assertTrue(provider.signals.isEmpty());
        assertTrue(seen.isEmpty());
    }
}
