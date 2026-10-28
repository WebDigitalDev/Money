package com.webdigital.money2.chat;

import java.time.LocalDateTime;

public record ChatContractEventResponse(
        String category,
        String operation,
        String description,
        String username,
        LocalDateTime occurredAt) {
}
