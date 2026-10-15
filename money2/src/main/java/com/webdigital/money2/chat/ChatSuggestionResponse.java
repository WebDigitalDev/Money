package com.webdigital.money2.chat;

public record ChatSuggestionResponse(
        String label,
        String message,
        Long clientId,
        Long regionId,
        String action) {

    public ChatSuggestionResponse(String label, String message, Long clientId) {
        this(label, message, clientId, null, null);
    }

    public ChatSuggestionResponse(
            String label,
            String message,
            Long clientId,
            Long regionId) {
        this(label, message, clientId, regionId, null);
    }
}
