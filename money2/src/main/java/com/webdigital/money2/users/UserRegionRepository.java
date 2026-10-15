package com.webdigital.money2.users;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserRegionRepository extends JpaRepository<UserRegion, Long> {

    @Query("select ur.regionId from UserRegion ur where ur.userId = :userId")
    List<Long> findRegionIdsByUserId(@Param("userId") Long userId);

    boolean existsByUserIdAndRegionId(Long userId, Long regionId);

    @Modifying
    @Query("delete from UserRegion ur where ur.userId = :userId")
    void deleteByUserId(@Param("userId") Long userId);

    @Modifying
    @Query("delete from UserRegion ur where ur.regionId = :regionId")
    void deleteByRegionId(@Param("regionId") Long regionId);

    @Modifying
    @Query("delete from UserRegion ur where ur.userId = :userId and ur.regionId = :regionId")
    void deleteByUserIdAndRegionId(
            @Param("userId") Long userId,
            @Param("regionId") Long regionId);
}
