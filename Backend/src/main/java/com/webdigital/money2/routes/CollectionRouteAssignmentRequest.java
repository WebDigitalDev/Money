package com.webdigital.money2.routes;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;

public record CollectionRouteAssignmentRequest(
        @NotNull @Positive Long collectorId,
        @NotEmpty @Size(max = 100) List<@Valid @Positive Long> clientIds) {
}
