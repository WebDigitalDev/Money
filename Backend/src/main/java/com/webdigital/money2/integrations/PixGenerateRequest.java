package com.webdigital.money2.integrations;

import java.math.BigDecimal;

public record PixGenerateRequest(Long installmentId, BigDecimal amount) {
}
