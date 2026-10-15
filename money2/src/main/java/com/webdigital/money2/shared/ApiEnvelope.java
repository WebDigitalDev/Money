package com.webdigital.money2.shared;

public record ApiEnvelope<T>(T responseBody) {

    public static <T> ApiEnvelope<T> of(T responseBody) {
        return new ApiEnvelope<>(responseBody);
    }
}

