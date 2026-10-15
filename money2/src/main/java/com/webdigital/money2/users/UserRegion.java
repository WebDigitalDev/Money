package com.webdigital.money2.users;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "regiao_usuario")
public class UserRegion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "usuario_id", nullable = false)
    private Long userId;

    @Column(name = "regiao_id")
    private Long regionId;

    @Column(name = "dtcad")
    private LocalDateTime createdAt;

    @Column(name = "dtalter")
    private LocalDateTime updatedAt;

    protected UserRegion() {
    }

    public UserRegion(Long userId, Long regionId, LocalDateTime timestamp) {
        this.userId = userId;
        this.regionId = regionId;
        this.createdAt = timestamp;
        this.updatedAt = timestamp;
    }
}
