package com.webdigital.money2.chat;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class QdrantFinancialIndexer {

    private static final Logger LOGGER = LoggerFactory.getLogger(QdrantFinancialIndexer.class);
    private static final int BATCH_SIZE = 250;

    private final ChatRepository repository;
    private final QdrantFinancialService qdrant;

    public QdrantFinancialIndexer(ChatRepository repository, QdrantFinancialService qdrant) {
        this.repository = repository;
        this.qdrant = qdrant;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        synchronizeAll();
    }

    @Scheduled(
            initialDelayString = "${money.qdrant.financial-sync-delay-ms:300000}",
            fixedDelayString = "${money.qdrant.financial-sync-delay-ms:300000}")
    public void synchronizeAll() {
        if (!qdrant.isEnabled()) return;
        qdrant.synchronizeIntents();
        List<IndexedFinancialContract> contracts = repository.indexableFinancialContracts();
        int indexed = 0;
        for (int start = 0; start < contracts.size(); start += BATCH_SIZE) {
            int end = Math.min(start + BATCH_SIZE, contracts.size());
            if (qdrant.upsertContracts(contracts.subList(start, end))) indexed += end - start;
        }
        LOGGER.info("Índice financeiro Qdrant sincronizado: {}/{} contratos.", indexed, contracts.size());
    }
}
