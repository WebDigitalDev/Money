package com.webdigital.money2.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "money.security")
public record MoneySecurityProperties(
        @NotBlank String jwtSecret,
        @Positive long tokenValidityHours) {
}

