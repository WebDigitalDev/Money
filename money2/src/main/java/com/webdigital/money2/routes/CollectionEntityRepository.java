package com.webdigital.money2.routes;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CollectionEntityRepository extends JpaRepository<CollectionEntity, Long> {
    Optional<CollectionEntity> findByIdAndClientId(Long id, Long clientId);
}
