package com.webdigital.money2.chat;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * Contexto curto de uma conversa. Dados financeiros nunca são armazenados
 * aqui: somente os identificadores necessários para interpretar referências
 * como "esse cliente" e "o último pagamento dele".
 */
@Component
public class ChatConversationStore {

    private static final Duration TTL = Duration.ofMinutes(45);
    private static final int CLEANUP_THRESHOLD = 2_000;

    private final Map<Key, StoredContext> contexts = new ConcurrentHashMap<>();

    public ChatConversationContext get(long userId, String conversationId) {
        Key key = key(userId, conversationId);
        if (key == null) return ChatConversationContext.empty();
        StoredContext stored = contexts.get(key);
        if (stored == null) return ChatConversationContext.empty();
        if (stored.expiresAt().isBefore(Instant.now())) {
            contexts.remove(key, stored);
            return ChatConversationContext.empty();
        }
        return stored.context();
    }

    public void selectClient(long userId, String conversationId, Long clientId) {
        update(userId, conversationId, current ->
                new ChatConversationContext(clientId, null, current.regionId(), "CLIENT"));
    }

    public void selectContract(long userId, String conversationId, Long loanId, Long regionId) {
        update(userId, conversationId, current ->
                new ChatConversationContext(null, loanId, regionId, "CONTRACT"));
    }

    public void selectRegion(long userId, String conversationId, Long regionId, String intent) {
        update(userId, conversationId, current ->
                new ChatConversationContext(current.clientId(), current.loanId(), regionId, intent));
    }

    public void clearClient(long userId, String conversationId) {
        update(userId, conversationId, current ->
                new ChatConversationContext(null, current.loanId(), current.regionId(), current.lastIntent()));
    }

    public void clearContract(long userId, String conversationId) {
        update(userId, conversationId, current ->
                new ChatConversationContext(current.clientId(), null, current.regionId(), current.lastIntent()));
    }

    public void clear(long userId, String conversationId) {
        Key key = key(userId, conversationId);
        if (key != null) contexts.remove(key);
    }

    public void rememberIntent(long userId, String conversationId, String intent) {
        update(userId, conversationId, current ->
                new ChatConversationContext(current.clientId(), current.loanId(), current.regionId(), intent));
    }

    private void update(
            long userId,
            String conversationId,
            java.util.function.UnaryOperator<ChatConversationContext> updater) {
        Key key = key(userId, conversationId);
        if (key == null) return;
        Instant expiresAt = Instant.now().plus(TTL);
        contexts.compute(key, (ignored, previous) -> {
            ChatConversationContext current = previous == null
                    ? ChatConversationContext.empty()
                    : previous.context();
            return new StoredContext(updater.apply(current), expiresAt);
        });
        if (contexts.size() > CLEANUP_THRESHOLD) cleanupExpired();
    }

    private void cleanupExpired() {
        Instant now = Instant.now();
        contexts.entrySet().removeIf(entry -> entry.getValue().expiresAt().isBefore(now));
    }

    private static Key key(long userId, String conversationId) {
        String clean = conversationId == null ? "" : conversationId.trim();
        return clean.isEmpty() ? null : new Key(userId, clean);
    }

    private record Key(long userId, String conversationId) {}

    private record StoredContext(ChatConversationContext context, Instant expiresAt) {}
}
