package com.webdigital.money2.clients;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ClientDocumentRepository extends JpaRepository<ClientDocumentEntity, Long> {
    @Query("select d from ClientDocumentEntity d where d.clientId = :clientId order by d.dtcad desc, d.id desc")
    List<ClientDocumentEntity> findAllByClientIdOrderByCreatedAtDescIdDesc(@Param("clientId") Long clientId);
    Optional<ClientDocumentEntity> findByIdAndClientId(Long id, Long clientId);
}
