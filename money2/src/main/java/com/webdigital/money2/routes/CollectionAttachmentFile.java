package com.webdigital.money2.routes;

public record CollectionAttachmentFile(
        byte[] data,
        String fileName,
        String contentType) {
}
