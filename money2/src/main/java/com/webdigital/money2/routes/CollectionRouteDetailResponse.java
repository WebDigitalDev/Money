package com.webdigital.money2.routes;

import java.util.List;

public record CollectionRouteDetailResponse(
        CollectionRouteItemResponse debt,
        List<CollectionContractResponse> contracts,
        List<CollectionHistoryResponse> history,
        boolean canRegisterCollection) {
}
