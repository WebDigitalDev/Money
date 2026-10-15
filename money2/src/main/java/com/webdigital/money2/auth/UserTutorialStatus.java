package com.webdigital.money2.auth;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "money2_user_tutorial_status")
public class UserTutorialStatus {

    @Id
    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "completed_at", nullable = false)
    private LocalDateTime completedAt;

    public UserTutorialStatus() {
    }

    public UserTutorialStatus(Long userId, LocalDateTime completedAt) {
        this.userId = userId;
        this.completedAt = completedAt;
    }

    public Long getUserId() {
        return userId;
    }

    public LocalDateTime getCompletedAt() {
        return completedAt;
    }
}
