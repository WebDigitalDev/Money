package com.webdigital.money2.users;

import java.time.LocalDateTime;
import java.util.List;

public record UserDetailResponse(
        Long id,
        String firstName,
        String lastName,
        String name,
        String username,
        String email,
        boolean enabled,
        boolean locked,
        boolean expired,
        boolean credentialsExpired,
        boolean forcePasswordChange,
        boolean administrator,
        boolean canEdit,
        boolean collector,
        boolean tutorialCompleted,
        LocalDateTime lastAccess,
        List<RegionOptionResponse> regions) {
}
