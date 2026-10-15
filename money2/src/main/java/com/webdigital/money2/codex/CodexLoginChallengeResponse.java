package com.webdigital.money2.codex;

public record CodexLoginChallengeResponse(
        String loginId,
        String verificationUrl,
        String userCode) {
}
