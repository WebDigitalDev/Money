package com.webdigital.money2.clients;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "documentos")
public class ClientDocumentEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "cliente_id")
    private Long clientId;
    private String descricao;
    @Column(name = "nome_arquivo")
    private String fileName;
    @Column(name = "arquivo_disco")
    private String diskFile;
    private String tipo;
    private LocalDateTime dtalter;
    private LocalDateTime dtcad;

    public Long getId() { return id; }
    public Long getClientId() { return clientId; }
    public void setClientId(Long value) { clientId = value; }
    public String getDescription() { return descricao; }
    public void setDescription(String value) { descricao = value; }
    public String getFileName() { return fileName; }
    public void setFileName(String value) { fileName = value; }
    public String getDiskFile() { return diskFile; }
    public void setDiskFile(String value) { diskFile = value; }
    public String getContentType() { return tipo; }
    public void setContentType(String value) { tipo = value; }
    public LocalDateTime getUpdatedAt() { return dtalter; }
    public void setUpdatedAt(LocalDateTime value) { dtalter = value; }
    public LocalDateTime getCreatedAt() { return dtcad; }
    public void setCreatedAt(LocalDateTime value) { dtcad = value; }
}
