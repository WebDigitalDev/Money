package com.webdigital.money2.codex;

import java.util.List;

public record CodexModelResponse(
        String id,
        String name,
        boolean defaultModel,
        boolean acceptsImages,
        String defaultServiceTier,
        List<CodexServiceTierResponse> serviceTiers) {
}
