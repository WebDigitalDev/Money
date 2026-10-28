package com.webdigital.money2.codex;

public record CodexUsageLimitResponse(
        double usedPercent,
        Integer windowDurationMinutes,
        Long resetsAtEpochSeconds,
        String limitName) {
}
