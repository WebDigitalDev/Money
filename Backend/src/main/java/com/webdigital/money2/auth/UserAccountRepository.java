package com.webdigital.money2.auth;

import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserAccountRepository extends JpaRepository<UserAccount, Long> {

    @Query("select u from UserAccount u where upper(u.username) = upper(:username)")
    Optional<UserAccount> findByNormalizedUsername(@Param("username") String username);

    @Query("""
            select u from UserAccount u
            where :query = ''
               or lower(coalesce(u.firstName, '')) like lower(concat('%', :query, '%'))
               or lower(coalesce(u.lastName, '')) like lower(concat('%', :query, '%'))
               or lower(u.username) like lower(concat('%', :query, '%'))
               or lower(coalesce(u.email, '')) like lower(concat('%', :query, '%'))
            order by lower(coalesce(
                         nullif(trim(concat(
                             trim(coalesce(u.firstName, '')),
                             concat(' ', trim(coalesce(u.lastName, '')))
                         )), ''),
                         u.username
                     )),
                     u.id
            """)
    Page<UserAccount> search(@Param("query") String query, Pageable pageable);

    boolean existsByUsernameIgnoreCase(String username);

    boolean existsByUsernameIgnoreCaseAndIdNot(String username, Long id);

    boolean existsByEmailIgnoreCase(String email);

    boolean existsByEmailIgnoreCaseAndIdNot(String email, Long id);
}
