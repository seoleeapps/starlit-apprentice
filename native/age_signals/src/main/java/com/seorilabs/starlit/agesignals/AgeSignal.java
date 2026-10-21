package com.seorilabs.starlit.agesignals;

import com.google.android.play.agesignals.model.AgeSignalsErrorCode;
import com.google.android.play.agesignals.model.SignificantChangeStatus;

/** The only values allowed to leave the SDK boundary; never a raw SDK result. */
final class AgeSignal {
    final String status;
    final int lower;
    final int upper;

    AgeSignal(String status, int lower, int upper) {
        this.status = status;
        this.lower = lower;
        this.upper = upper;
    }

    static AgeSignal status(String status) { return new AgeSignal(status, -1, -1); }

    static AgeSignal fields(Integer lower, Integer upper, Integer approval) {
        // Known parental protection is independent of range validity or sharing.
        // Do not turn it into a permissive error fallback, or retain unneeded ages.
        if (approval != null && approval == SignificantChangeStatus.PENDING) return status("approval_pending");
        if (approval != null && approval == SignificantChangeStatus.DECLINED) return status("approval_denied");
        if (approval != null && approval != SignificantChangeStatus.APPROVED) return status("error");

        if (lower == null && upper == null) {
            return status("not_shared");
        }
        if ((lower != null && (lower < 0 || lower > 18))
            || (upper != null && (upper < 2 || upper > 18 || (lower != null && upper < lower)))) {
            return status("error");
        }
        return new AgeSignal("shared", lower == null ? -1 : lower, upper == null ? -1 : upper);
    }

    static AgeSignal failure(int code) {
        switch (code) {
            case AgeSignalsErrorCode.NETWORK_ERROR:
                return status("offline");
            case AgeSignalsErrorCode.API_NOT_AVAILABLE:
            case AgeSignalsErrorCode.PLAY_STORE_NOT_FOUND:
            case AgeSignalsErrorCode.PLAY_SERVICES_NOT_FOUND:
            case AgeSignalsErrorCode.CANNOT_BIND_TO_SERVICE:
            case AgeSignalsErrorCode.PLAY_STORE_VERSION_OUTDATED:
            case AgeSignalsErrorCode.PLAY_SERVICES_VERSION_OUTDATED:
            case AgeSignalsErrorCode.APP_NOT_OWNED:
            case AgeSignalsErrorCode.SDK_VERSION_OUTDATED:
                return status("unavailable");
            default:
                return status("error");
        }
    }
}
