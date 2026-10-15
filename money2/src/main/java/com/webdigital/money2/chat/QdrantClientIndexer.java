package com.webdigital.money2.chat;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.boot.context.event.ApplicationReadyEvent;

@Component
public class QdrantClientIndexer {

    private static final Logger LOGGER = LoggerFactory.getLogger(QdrantClientIndexer.class);
    private static final int BATCH_SIZE = 250;

    private final ChatRepository repository;
    private final QdrantService qdrant;

    public QdrantClientIndexer(ChatRepository repository, QdrantService qdrant) {
        this.repository = repository;
        this.qdrant = qdrant;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        synchronizeAll();
    }

    @Scheduled(
            initialDelayString = "${money.qdrant.sync-delay-ms:300000}",
            fixedDelayString = "${money.qdrant.sync-delay-ms:300000}")
    public void synchronizeAll() {
        if (!qdrant.isEnabled()) return;
        List<IndexedClient> clients = repository.indexableClients();
        int indexed = 0;
        for (int start = 0; start < clients.size(); start += BATCH_SIZE) {
            int end = Math.min(start + BATCH_SIZE, clients.size());
            if (qdrant.upsert(clients.subList(start, end))) indexed += end - start;
        }
        LOGGER.info("Índice Qdrant sincronizado: {}/{} clientes.", indexed, clients.size());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onClientChanged(ClientIndexRequested event) {
        if (!qdrant.isEnabled() || event == null || event.clientId() == null) return;
        IndexedClient client = repository.indexableClient(event.clientId());
        if (client == null) {
            qdrant.delete(event.clientId());
        } else {
            qdrant.upsert(List.of(client));
        }
    }
}
