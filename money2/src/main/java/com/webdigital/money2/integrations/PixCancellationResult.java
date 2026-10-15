package com.webdigital.money2.integrations;

public record PixCancellationResult(int cancelledCount, int paidCount, int pendingCount) { }
