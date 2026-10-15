package com.webdigital.money2.clients;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ClientRepository extends JpaRepository<ClientEntity, Long> {

    @Query(value = """
            SELECT COUNT(*) > 0
            FROM cliente c
            WHERE c.id = :clientId
              AND EXISTS (
                  SELECT 1
                  FROM regiao_usuario ur
                  WHERE ur.usuario_id = :userId
                    AND ur.regiao_id = c.regiao_id
              )
            """, nativeQuery = true)
    boolean isAccessible(
            @Param("clientId") Long clientId,
            @Param("userId") Long userId);

    @Query(value = """
            SELECT DISTINCT c.regiao_id
            FROM cliente c
            WHERE regexp_replace(COALESCE(c.cgc_cpf, ''), '[^0-9]', '', 'g') = :document
            """, nativeQuery = true)
    List<Long> findRegionIdsByNormalizedDocument(
            @Param("document") String document);
}
