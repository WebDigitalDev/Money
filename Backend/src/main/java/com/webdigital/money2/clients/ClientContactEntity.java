package com.webdigital.money2.clients;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "contatos")
public class ClientContactEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id_contato")
    private Long id;
    @Column(name = "cliente_id")
    private Long clientId;
    private String nome;
    private String telefone;
    private String tipo;
    private String observacoes;
    private LocalDateTime dtalter;
    private LocalDateTime dtcad;

    public Long getId() { return id; }
    public Long getClientId() { return clientId; }
    public void setClientId(Long value) { clientId = value; }
    public String getName() { return nome; }
    public void setName(String value) { nome = value; }
    public String getPhone() { return telefone; }
    public void setPhone(String value) { telefone = value; }
    public String getType() { return tipo; }
    public void setType(String value) { tipo = value; }
    public String getNotes() { return observacoes; }
    public void setNotes(String value) { observacoes = value; }
    public LocalDateTime getUpdatedAt() { return dtalter; }
    public void setUpdatedAt(LocalDateTime value) { dtalter = value; }
    public LocalDateTime getCreatedAt() { return dtcad; }
    public void setCreatedAt(LocalDateTime value) { dtcad = value; }
}
