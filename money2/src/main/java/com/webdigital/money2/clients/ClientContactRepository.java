package com.webdigital.money2.clients;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ClientContactRepository extends JpaRepository<ClientContactEntity, Long> {
    @Query("select c from ClientContactEntity c where c.clientId = :clientId order by lower(coalesce(c.nome, '')), c.id")
    List<ClientContactEntity> findAllByClientIdOrderByNameAscIdAsc(@Param("clientId") Long clientId);
    Optional<ClientContactEntity> findByIdAndClientId(Long id, Long clientId);
}
