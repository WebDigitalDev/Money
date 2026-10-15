package com.webdigital.money2.clients;

import com.webdigital.money2.shared.ApiException;
import java.util.Locale;
import org.springframework.http.HttpStatus;

public enum ClientStatus {
    ACTIVE,
    INACTIVE,
    MISSING;

    public static ClientStatus parse(String value) {
        try {
            return ClientStatus.valueOf(value == null
                    ? ACTIVE.name()
                    : value.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Situação de cliente inválida.");
        }
    }
}
