package com.webdigital.money2.clients;

import java.time.LocalDateTime;

public record ClientDocumentResponse(
        long id,
        long clientId,
        String description,
        String fileName,
        String contentType,
        boolean available,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {
}
