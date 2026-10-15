package com.webdigital.money2.clients;

import com.webdigital.money2.users.Region;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "cliente")
public class ClientEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String nome;
    private String razao;
    @Column(name = "cgc_cpf")
    private String document;
    private String email;
    private long cep;
    @Column(name = "cidade_id")
    private Long cityId;
    private String endereco;
    private String numero;
    private String complemento;
    private String cobrador;
    private String tipo;
    private LocalDateTime dtnasc;
    private String celular;
    private String bairro;
    private boolean ativo;
    private LocalDateTime dtalter;
    private LocalDateTime dtcad;
    private String inscricao;
    private String telefone;
    private String telefone2;
    private String homepage;
    private String observacao;
    private String comercio;
    private String facebook;
    private String instagram;
    @Column(name = "google_maps_link", length = 2048)
    private String googleMapsLink;
    private Double latitude;
    private Double longitude;
    @Column(name = "latitude_comercio")
    private Double businessLatitude;
    @Column(name = "longitude_comercio")
    private Double businessLongitude;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "regiao_id")
    private Region region;

    public Long getId() { return id; }
    public String getName() { return nome; }
    public void setName(String value) { nome = value; }
    public String getLegalName() { return razao; }
    public void setLegalName(String value) { razao = value; }
    public String getDocument() { return document; }
    public void setDocument(String value) { document = value; }
    public String getEmail() { return email; }
    public void setEmail(String value) { email = value; }
    public long getPostalCode() { return cep; }
    public void setPostalCode(long value) { cep = value; }
    public Long getCityId() { return cityId; }
    public void setCityId(Long value) { cityId = value; }
    public String getAddress() { return endereco; }
    public void setAddress(String value) { endereco = value; }
    public String getNumber() { return numero; }
    public void setNumber(String value) { numero = value; }
    public String getComplement() { return complemento; }
    public void setComplement(String value) { complemento = value; }
    public String getCollector() { return cobrador; }
    public void setCollector(String value) { cobrador = value; }
    public String getType() { return tipo; }
    public void setType(String value) { tipo = value; }
    public LocalDateTime getBirthDate() { return dtnasc; }
    public void setBirthDate(LocalDateTime value) { dtnasc = value; }
    public String getMobilePhone() { return celular; }
    public void setMobilePhone(String value) { celular = value; }
    public String getNeighborhood() { return bairro; }
    public void setNeighborhood(String value) { bairro = value; }
    public boolean isEnabled() { return ativo; }
    public void setEnabled(boolean value) { ativo = value; }
    public LocalDateTime getUpdatedAt() { return dtalter; }
    public void setUpdatedAt(LocalDateTime value) { dtalter = value; }
    public LocalDateTime getCreatedAt() { return dtcad; }
    public void setCreatedAt(LocalDateTime value) { dtcad = value; }
    public String getStateRegistration() { return inscricao; }
    public void setStateRegistration(String value) { inscricao = value; }
    public String getPhone() { return telefone; }
    public void setPhone(String value) { telefone = value; }
    public String getSecondaryPhone() { return telefone2; }
    public void setSecondaryPhone(String value) { telefone2 = value; }
    public String getHomepage() { return homepage; }
    public void setHomepage(String value) { homepage = value; }
    public String getNotes() { return observacao; }
    public void setNotes(String value) { observacao = value; }
    public String getBusiness() { return comercio; }
    public void setBusiness(String value) { comercio = value; }
    public String getFacebook() { return facebook; }
    public void setFacebook(String value) { facebook = value; }
    public String getInstagram() { return instagram; }
    public void setInstagram(String value) { instagram = value; }
    public String getGoogleMapsLink() { return googleMapsLink; }
    public void setGoogleMapsLink(String value) { googleMapsLink = value; }
    public Double getLatitude() { return latitude; }
    public void setLatitude(Double value) { latitude = value; }
    public Double getLongitude() { return longitude; }
    public void setLongitude(Double value) { longitude = value; }
    public Double getBusinessLatitude() { return businessLatitude; }
    public void setBusinessLatitude(Double value) { businessLatitude = value; }
    public Double getBusinessLongitude() { return businessLongitude; }
    public void setBusinessLongitude(Double value) { businessLongitude = value; }
    public Region getRegion() { return region; }
    public void setRegion(Region value) { region = value; }
}
