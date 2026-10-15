package com.webdigital.money2.auth;

import java.time.Instant;

public record TokenResponse(
        String token,
        String name,
        Long userId,
        boolean administrator,
        boolean canEdit,
        boolean collector,
        boolean forcePasswordChange,
        boolean tutorialCompleted,
        Instant expires) {
}
