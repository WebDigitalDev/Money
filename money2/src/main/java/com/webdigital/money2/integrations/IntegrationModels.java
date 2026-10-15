package com.webdigital.money2.integrations;

import java.time.LocalDateTime;
import java.util.List;

public final class IntegrationModels {

    private IntegrationModels() {
    }

    public record BankAccount(
            long id,
            String name,
            String bank,
            boolean active,
            boolean clientIdConfigured,
            boolean clientSecretConfigured,
            String pixKey,
            List<Long> regionIds,
            List<String> regionNames,
            String certificateName,
            String privateKeyName,
            String certificateChainName,
            LocalDateTime updatedAt) {
    }

    public record BankAccountRequest(String name, List<Long> regionIds) {
    }

    public record SicrediConfigRequest(
            boolean active,
            String clientId,
            String clientSecret,
            String pixKey) {
    }

    public record WhatsappStatus(boolean active, boolean tokenConfigured) {
    }

    public record WhatsappConfig(
            boolean active,
            boolean tokenConfigured,
            String baseUrl,
            String overdueMessage,
            String dueTodayMessage,
            String missingMessage,
            String acquisitionMessage,
            String pixMessage,
            String pixReceivedMessage) {
    }

    public record WhatsappConfigRequest(
            boolean active,
            String apiToken,
            String overdueMessage,
            String dueTodayMessage,
            String missingMessage,
            String acquisitionMessage,
            String pixMessage,
            String pixReceivedMessage) {
    }

    public record WhatsappDevice(
            long id,
            String remoteId,
            String name,
            String phone,
            String status,
            String provider,
            boolean connected,
            boolean pixCopySupported,
            boolean dispatching,
            String dispatchType,
            int dispatchTotal,
            int dispatchProcessed,
            int dispatchSucceeded,
            int dispatchErrors,
            int dispatchIgnored,
            List<Long> regionIds,
            List<String> regionNames,
            LocalDateTime dispatchStartedAt,
            LocalDateTime updatedAt) {
    }

    public record WhatsappLog(
            long id,
            Long deviceId,
            String deviceName,
            Long clientId,
            Long loanId,
            Long installmentId,
            String type,
            String phone,
            String clientName,
            String regionName,
            String status,
            String message,
            String error,
            LocalDateTime createdAt) {
    }

    public record RegionSelectionRequest(List<Long> regionIds) {
    }

    public record PhoneRequest(String phone) {
    }

    public record DispatchRequest(String type) {
    }

    public record ActionResult(String message) {
    }

    record WhatsappSecret(
            boolean active,
            String token,
            String baseUrl,
            String overdueMessage,
            String dueTodayMessage,
            String missingMessage,
            String acquisitionMessage,
            String pixMessage,
            String pixReceivedMessage) {
    }
}
