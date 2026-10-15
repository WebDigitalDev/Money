package com.webdigital.money2.codex;

import java.util.List;

public record CodexConnectionResponse(
        boolean enabled,
        boolean available,
        boolean connected,
        boolean connecting,
        String email,
        String planType,
        CodexUsageLimitResponse usage,
        List<CodexModelResponse> models,
        String defaultModel,
        String defaultServiceTier,
        String error) {
}
