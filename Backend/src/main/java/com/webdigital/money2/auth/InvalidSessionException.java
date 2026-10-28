package com.webdigital.money2.auth;

import com.webdigital.money2.shared.ApiException;
import org.springframework.http.HttpStatus;

public class InvalidSessionException extends ApiException {

    public InvalidSessionException() {
        super(HttpStatus.UNAUTHORIZED, "Sessão inválida ou expirada. Faça login novamente.");
    }
}

