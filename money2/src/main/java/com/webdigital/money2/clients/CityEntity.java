package com.webdigital.money2.clients;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "cidade")
public class CityEntity {
    @Id
    private Long codigo;
    private Long codibge;
    private String descricao;
    private String uf;
    @Column(name = "descricao_pesquisa")
    private String searchDescription;

    public Long getId() { return codigo; }
    public Long getIbgeCode() { return codibge; }
    public String getName() { return descricao; }
    public String getState() { return uf; }
    public String getSearchDescription() { return searchDescription; }
}
