package com.webdigital.money2.codex;

public record CodexAttachment(
        String fileName,
        String contentType,
        byte[] bytes) {
}
