package com.webdigital.money2.goals;

import jakarta.persistence.Column;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashSet;
import java.util.Set;

@Entity
@Table(name = "money2_metas_financeiras")
public class FinancialGoalEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "regiao_id", nullable = false)
    private Long regionId;

    @ElementCollection(fetch = FetchType.EAGER)
    @org.hibernate.annotations.BatchSize(size = 100)
    @CollectionTable(
            name = "money2_metas_financeiras_regioes",
            joinColumns = @JoinColumn(name = "meta_id"))
    @Column(name = "regiao_id", nullable = false)
    private Set<Long> regionIds = new LinkedHashSet<>();

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo", nullable = false, length = 20)
    private FinancialGoalType type;

    @Column(name = "valor_meta", nullable = false, precision = 19, scale = 2)
    private BigDecimal targetAmount;

    @Column(name = "data_inicio", nullable = false)
    private LocalDate startDate;

    @Column(name = "data_fim", nullable = false)
    private LocalDate endDate;

    @Column(name = "criado_por", nullable = false)
    private Long createdBy;

    @Column(name = "dtcad", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "dtalter", nullable = false)
    private LocalDateTime updatedAt;

    @Column(name = "valor_alcancado_final", precision = 19, scale = 2)
    private BigDecimal finalAchievedAmount;

    @Column(name = "finalizada_em")
    private LocalDateTime finalizedAt;

    @Column(name = "clientes_ativos_final")
    private Long finalActive;
    @Column(name = "clientes_em_dia_final")
    private Long finalOnTime;
    @Column(name = "clientes_atraso_final")
    private Long finalOverdue;
    @Column(name = "clientes_novos_final")
    private Long finalNew;

    @Column(name = "repetir_frequencia", nullable = false)
    private boolean repeatFrequency;

    @Column(name = "meta_anterior_id")
    private Long previousGoalId;

    public ClientGoalStats getFinalClientStats() {
        return finalActive == null ? null : new ClientGoalStats(finalActive, finalOnTime, finalOverdue, finalNew);
    }
    public void setFinalClientStats(ClientGoalStats stats) {
        finalActive = stats.active(); finalOnTime = stats.onTime();
        finalOverdue = stats.overdue(); finalNew = stats.newClients();
    }

    public Long getId() { return id; }
    public Long getRegionId() { return regionId; }
    public void setRegionId(Long value) { regionId = value; }
    public Set<Long> getRegionIds() {
        if (regionIds == null || regionIds.isEmpty()) {
            return regionId == null ? Set.of() : Set.of(regionId);
        }
        return Set.copyOf(regionIds);
    }
    public void setRegionIds(Set<Long> value) {
        regionIds = value == null ? new LinkedHashSet<>() : new LinkedHashSet<>(value);
        if (!regionIds.isEmpty()) regionId = regionIds.iterator().next();
    }
    public FinancialGoalType getType() { return type; }
    public void setType(FinancialGoalType value) { type = value; }
    public BigDecimal getTargetAmount() { return targetAmount; }
    public void setTargetAmount(BigDecimal value) { targetAmount = value; }
    public LocalDate getStartDate() { return startDate; }
    public void setStartDate(LocalDate value) { startDate = value; }
    public LocalDate getEndDate() { return endDate; }
    public void setEndDate(LocalDate value) { endDate = value; }
    public Long getCreatedBy() { return createdBy; }
    public void setCreatedBy(Long value) { createdBy = value; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime value) { createdAt = value; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime value) { updatedAt = value; }
    public BigDecimal getFinalAchievedAmount() { return finalAchievedAmount; }
    public void setFinalAchievedAmount(BigDecimal value) { finalAchievedAmount = value; }
    public LocalDateTime getFinalizedAt() { return finalizedAt; }
    public void setFinalizedAt(LocalDateTime value) { finalizedAt = value; }
    public boolean isRepeatFrequency() { return repeatFrequency; }
    public void setRepeatFrequency(boolean value) { repeatFrequency = value; }
    public Long getPreviousGoalId() { return previousGoalId; }
    public void setPreviousGoalId(Long value) { previousGoalId = value; }
}
