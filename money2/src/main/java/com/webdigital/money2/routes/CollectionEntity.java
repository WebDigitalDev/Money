package com.webdigital.money2.routes;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "money2_cobrancas")
public class CollectionEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "cliente_id", nullable = false)
    private Long clientId;

    @Column(name = "regiao_id", nullable = false)
    private Long regionId;

    @Column(name = "usuario_id", nullable = false)
    private Long userId;

    @Column(name = "observacao", nullable = false, length = 4000)
    private String observation;

    @Column(name = "valor_divida", nullable = false, precision = 19, scale = 2)
    private BigDecimal debtAmount;

    @Column(name = "dias_atraso", nullable = false)
    private int overdueDays;

    @Column(name = "arquivo_nome", length = 512)
    private String attachmentName;

    @Column(name = "arquivo_disco")
    private String attachmentDiskName;

    @Column(name = "arquivo_tipo")
    private String attachmentContentType;

    @Column(name = "arquivo_tamanho")
    private Long attachmentSize;

    @Column(name = "dtcad", nullable = false)
    private LocalDateTime createdAt;

    public Long getId() { return id; }
    public Long getClientId() { return clientId; }
    public void setClientId(Long value) { clientId = value; }
    public Long getRegionId() { return regionId; }
    public void setRegionId(Long value) { regionId = value; }
    public Long getUserId() { return userId; }
    public void setUserId(Long value) { userId = value; }
    public String getObservation() { return observation; }
    public void setObservation(String value) { observation = value; }
    public BigDecimal getDebtAmount() { return debtAmount; }
    public void setDebtAmount(BigDecimal value) { debtAmount = value; }
    public int getOverdueDays() { return overdueDays; }
    public void setOverdueDays(int value) { overdueDays = value; }
    public String getAttachmentName() { return attachmentName; }
    public void setAttachmentName(String value) { attachmentName = value; }
    public String getAttachmentDiskName() { return attachmentDiskName; }
    public void setAttachmentDiskName(String value) { attachmentDiskName = value; }
    public String getAttachmentContentType() { return attachmentContentType; }
    public void setAttachmentContentType(String value) { attachmentContentType = value; }
    public Long getAttachmentSize() { return attachmentSize; }
    public void setAttachmentSize(Long value) { attachmentSize = value; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime value) { createdAt = value; }
}
