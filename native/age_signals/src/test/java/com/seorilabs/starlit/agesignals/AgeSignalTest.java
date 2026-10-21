package com.seorilabs.starlit.agesignals;

import static org.junit.Assert.*;
import com.google.android.play.agesignals.model.SignificantChangeStatus;
import org.junit.Test;

public final class AgeSignalTest {
    @Test public void preservesCustomInclusiveRangesAndOpenUpperBound() {
        AgeSignal child = AgeSignal.fields(0, 12, null);
        assertEquals("shared", child.status);
        assertEquals(0, child.lower);
        assertEquals(12, child.upper);
        assertEquals(16, AgeSignal.fields(13, 16, null).upper);
        AgeSignal adult = AgeSignal.fields(18, null, null);
        assertEquals("shared", adult.status);
        assertEquals(18, adult.lower);
        assertEquals(-1, adult.upper);
        AgeSignal upperOnly = AgeSignal.fields(null, 12, null);
        assertEquals("shared", upperOnly.status);
        assertEquals(-1, upperOnly.lower);
        assertEquals(12, upperOnly.upper);
    }
    @Test public void parentalSignificantChangeApprovalIsNotSharingConsent() {
        assertEquals("shared", AgeSignal.fields(13, 15, SignificantChangeStatus.APPROVED).status);
        assertEquals("approval_pending", AgeSignal.fields(13, 15, SignificantChangeStatus.PENDING).status);
        assertEquals("approval_denied", AgeSignal.fields(13, 15, SignificantChangeStatus.DECLINED).status);
        assertEquals("approval_pending", AgeSignal.fields(null, null, SignificantChangeStatus.PENDING).status);
        assertEquals("not_shared", AgeSignal.fields(null, null, null).status);
    }
    @Test public void malformedAndFutureValuesDoNotBecomeAdultOrNotApplicable() {
        assertEquals("error", AgeSignal.fields(null, 99, null).status);
        assertEquals("error", AgeSignal.fields(-1, 12, null).status);
        assertEquals("error", AgeSignal.fields(13, 12, null).status);
        assertEquals("error", AgeSignal.fields(19, null, null).status);
        assertEquals("error", AgeSignal.fields(13, 99, null).status);
        assertEquals("error", AgeSignal.fields(13, 15, 9876).status);
    }
    @Test public void parentalProtectionSurvivesMalformedRangeAndDropsAgeDetails() {
        AgeSignal pending = AgeSignal.fields(13, 12, SignificantChangeStatus.PENDING);
        assertEquals("approval_pending", pending.status);
        assertEquals(-1, pending.lower);
        assertEquals(-1, pending.upper);
        AgeSignal denied = AgeSignal.fields(-1, 12, SignificantChangeStatus.DECLINED);
        assertEquals("approval_denied", denied.status);
        assertEquals(-1, denied.lower);
        assertEquals(-1, denied.upper);
        AgeSignal validPending = AgeSignal.fields(13, 15, SignificantChangeStatus.PENDING);
        assertEquals(-1, validPending.lower);
        assertEquals(-1, validPending.upper);
    }
    @Test public void sdkFailuresHaveOnlyFixedStatusAndNoRange() {
        for (int code : new int[] {-1, -2, -4, -5, -6, -7, -9, -10}) {
            AgeSignal signal = AgeSignal.failure(code);
            assertEquals("unavailable", signal.status);
            assertEquals(-1, signal.lower);
            assertEquals(-1, signal.upper);
        }
        assertEquals("offline", AgeSignal.failure(-3).status);
        assertEquals("error", AgeSignal.failure(-8).status);
        assertEquals("error", AgeSignal.failure(-100).status);
        assertEquals("error", AgeSignal.failure(9876).status);
    }
}
