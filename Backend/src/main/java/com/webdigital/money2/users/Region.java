package com.webdigital.money2.users;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "regioes")
public class Region {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "descricao")
    private String description;

    @Column(name = "descricao_pai")
    private String parentDescription;

    @Column(name = "responsaveis")
    private String responsiblePeople;

    @Column(name = "dtcad")
    private LocalDateTime createdAt;

    @Column(name = "dtalter")
    private LocalDateTime updatedAt;

    @Column(name = "mensagem_emprestimo", length = 4000)
    private String loanMessage;

    @Column(name = "mensagem_emprestimo_refinanciado", length = 4000)
    private String refinancedLoanMessage;

    @Column(name = "mensagem_cobranca", length = 4000)
    private String collectionMessage;

    @Column(name = "mensagem_cobranca_link", length = 4000)
    private String collectionLinkMessage;

    @Column(name = "mensagem_atraso", length = 4000)
    private String overdueMessage;

    @Column(name = "precisa_dono_cli")
    private boolean clientOwnerRequired;

    public Region() {
    }

    public Long getId() {
        return id;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getParentDescription() {
        return parentDescription;
    }

    public void setParentDescription(String parentDescription) {
        this.parentDescription = parentDescription;
    }

    public String getResponsiblePeople() {
        return responsiblePeople;
    }

    public void setResponsiblePeople(String responsiblePeople) {
        this.responsiblePeople = responsiblePeople;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public String getLoanMessage() {
        return loanMessage;
    }

    public void setLoanMessage(String loanMessage) {
        this.loanMessage = loanMessage;
    }

    public String getRefinancedLoanMessage() {
        return refinancedLoanMessage;
    }

    public void setRefinancedLoanMessage(String refinancedLoanMessage) {
        this.refinancedLoanMessage = refinancedLoanMessage;
    }

    public String getCollectionMessage() {
        return collectionMessage;
    }

    public void setCollectionMessage(String collectionMessage) {
        this.collectionMessage = collectionMessage;
    }

    public String getCollectionLinkMessage() {
        return collectionLinkMessage;
    }

    public void setCollectionLinkMessage(String collectionLinkMessage) {
        this.collectionLinkMessage = collectionLinkMessage;
    }

    public String getOverdueMessage() {
        return overdueMessage;
    }

    public void setOverdueMessage(String overdueMessage) {
        this.overdueMessage = overdueMessage;
    }

    public boolean isClientOwnerRequired() {
        return clientOwnerRequired;
    }

    public void setClientOwnerRequired(boolean clientOwnerRequired) {
        this.clientOwnerRequired = clientOwnerRequired;
    }
}
