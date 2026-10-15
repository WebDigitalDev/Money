package com.webdigital.money2.chat;

import java.math.BigDecimal;

record ChatRegionProfitSnapshot(
        long regionId,
        String regionName,
        BigDecimal profit) {
}
