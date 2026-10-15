package com.webdigital.money2.notifications;

import com.webdigital.money2.goals.*;
import java.time.*;
import java.util.*;
import java.math.BigDecimal;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;

@Service
public class NotificationCollector {
    private final NotificationRepository notifications;
    private final FinancialGoalRepository goals;
    private final FinancialGoalProgressRepository progress;
    public NotificationCollector(NotificationRepository notifications, FinancialGoalRepository goals,
            FinancialGoalProgressRepository progress) {
        this.notifications=notifications; this.goals=goals; this.progress=progress;
    }
    @Scheduled(initialDelay=45000,fixedDelay=30000)
    public void payments() { notifications.collectPayments(); }

    @Scheduled(initialDelay=60000,fixedDelay=120000)
    @Transactional
    public void goals() {
        LocalDate today=LocalDate.now(ZoneId.of("America/Cuiaba"));
        List<FinancialGoalEntity> current=goals.findAll().stream()
            .filter(g->!g.getStartDate().isAfter(today) &&
                (!g.getEndDate().isBefore(today) || g.getFinalizedAt()==null)).toList();
        Map<Long,BigDecimal> amounts=progress.achievedActive(current.stream()
            .filter(g->!g.getType().isClient()).map(FinancialGoalEntity::getId).toList());
        Map<Long,ClientGoalStats> clients=progress.clientStats(current.stream()
            .filter(g->g.getType().isClient()).map(FinancialGoalEntity::getId).toList());
        for (FinancialGoalEntity goal:current) {
            boolean client=goal.getType().isClient();
            ClientGoalStats stats=clients.getOrDefault(goal.getId(),ClientGoalStats.EMPTY);
            BigDecimal amount=client?stats.achieved(goal.getType()):amounts.getOrDefault(goal.getId(),BigDecimal.ZERO);
            if (goal.getEndDate().isBefore(today)) {
                if (client) goal.setFinalClientStats(stats);
                goal.setFinalAchievedAmount(amount);
                goal.setFinalizedAt(LocalDateTime.now(ZoneId.of("America/Cuiaba")));
            }
            boolean reached=client?stats.reached(goal.getType(),goal.getTargetAmount()):amount.compareTo(goal.getTargetAmount())>=0;
            if (reached && !goal.getEndDate().isBefore(today)) notifications.goal(goal.getId(),"Meta atingida",
                label(goal.getType())+" • "+goal.getStartDate()+" até "+goal.getEndDate()+" • Objetivo: "+
                goal.getTargetAmount().toPlainString()+(goal.getType().isPercentage()?"%":""),goal.getRegionIds());
        }
    }
    private String label(FinancialGoalType type) {
        return switch(type) {
            case EMPRESTADO -> "Valor emprestado"; case RECEBIDO -> "Valor recebido"; case LUCRO -> "Lucro";
            case CLIENTES_ATIVOS -> "Novos clientes ativos"; case CLIENTES_EM_DIA -> "Clientes em dia";
            case CLIENTES_ATRASO -> "Clientes em atraso";
        };
    }
}
