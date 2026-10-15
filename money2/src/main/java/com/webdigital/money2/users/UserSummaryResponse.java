package com.webdigital.money2.users;

import java.time.LocalDateTime;

public record UserSummaryResponse(
        Long id,
        String name,
        String username,
        String email,
        boolean enabled,
        boolean administrator,
        boolean canEdit,
        boolean collector,
        LocalDateTime lastAccess) {
}
