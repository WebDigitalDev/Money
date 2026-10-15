package com.webdigital.money2.auth;

public record SessionResponse(
        Long userId,
        String username,
        boolean active,
        boolean administrator,
        boolean canEdit,
        boolean collector,
        boolean forcePasswordChange,
        boolean tutorialCompleted) {
}
