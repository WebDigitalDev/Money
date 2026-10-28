package com.webdigital.money2.regions;

import java.time.LocalDateTime;

public record RegionDetailResponse(
        Long id,
        String description,
        String responsiblePeople,
        String parentDescription,
        LocalDateTime createdAt,
        LocalDateTime updatedAt,
        String loanMessage,
        String refinancedLoanMessage,
        String collectionMessage,
        String collectionLinkMessage,
        String overdueMessage,
        boolean clientOwnerRequired) {
}
