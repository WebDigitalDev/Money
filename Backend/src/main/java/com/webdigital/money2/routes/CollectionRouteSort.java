package com.webdigital.money2.routes;

import com.webdigital.money2.shared.ApiException;
import org.springframework.http.HttpStatus;

public enum CollectionRouteSort {
    OVERDUE_DAYS,
    OVERDUE_AMOUNT;

    public static CollectionRouteSort from(String value) {
        if (value == null || value.isBlank()) return OVERDUE_DAYS;
        try {
            return valueOf(value.trim().toUpperCase());
        } catch (IllegalArgumentException exception) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A ordenação informada para as rotas é inválida.");
        }
    }
}
