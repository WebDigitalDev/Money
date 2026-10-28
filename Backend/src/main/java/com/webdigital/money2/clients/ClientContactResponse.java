package com.webdigital.money2.clients;

import java.time.LocalDateTime;

public record ClientContactResponse(
        long id,
        long clientId,
        String name,
        String phone,
        String type,
        String notes,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {
}
