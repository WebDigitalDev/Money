package com.webdigital.money2.clients;

import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CityRepository extends JpaRepository<CityEntity, Long> {

    @Query("""
            SELECT c FROM CityEntity c
            WHERE :query = ''
               OR lower(coalesce(c.searchDescription, '')) LIKE concat('%', :query, '%')
               OR lower(coalesce(c.descricao, '')) LIKE concat('%', :query, '%')
               OR lower(coalesce(c.uf, '')) LIKE concat('%', :query, '%')
            ORDER BY lower(coalesce(c.descricao, '')), lower(coalesce(c.uf, '')), c.codigo
            """)
    List<CityEntity> search(@Param("query") String query, Pageable pageable);

    Optional<CityEntity> findFirstByCodibge(Long ibgeCode);
}
