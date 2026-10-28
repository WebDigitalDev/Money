package com.webdigital.money2.goals;

import java.util.List;
import java.time.LocalDate;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FinancialGoalRepository
        extends JpaRepository<FinancialGoalEntity, Long> {

    @Query("""
            select goal from FinancialGoalEntity goal
            where goal.regionId in (
                select access.regionId from UserRegion access
                where access.userId = :userId
            )
              and goal.endDate >= :oldestVisibleEndDate
            order by goal.endDate desc, goal.startDate desc, goal.id desc
            """)
    List<FinancialGoalEntity> findAccessibleVisibleSince(
            @Param("userId") Long userId,
            @Param("oldestVisibleEndDate") LocalDate oldestVisibleEndDate);

    @Query("""
            select goal from FinancialGoalEntity goal
            where goal.regionId in (
                select access.regionId from UserRegion access
                where access.userId = :userId
            )
              and goal.startDate <= :today
              and goal.endDate >= :today
            order by goal.endDate desc, goal.startDate desc, goal.id desc
            """)
    List<FinancialGoalEntity> findAccessibleActiveOn(
            @Param("userId") Long userId,
            @Param("today") LocalDate today);

    @Query("""
            select goal from FinancialGoalEntity goal
            where :regionId member of goal.regionIds
              and goal.type = :type
              and goal.endDate >= :today
              and (:excludedId is null or goal.id <> :excludedId)
            order by goal.startDate, goal.id
            """)
    List<FinancialGoalEntity> findCurrentOrFutureByType(
            @Param("regionId") Long regionId,
            @Param("type") FinancialGoalType type,
            @Param("today") LocalDate today,
            @Param("excludedId") Long excludedId);

    @Query("""
            select goal from FinancialGoalEntity goal
            where goal.repeatFrequency = true
              and goal.endDate < :today
              and not exists (
                  select successor.id from FinancialGoalEntity successor
                  where successor.previousGoalId = goal.id
              )
            order by goal.endDate, goal.id
            """)
    List<FinancialGoalEntity> findRecurringDue(@Param("today") LocalDate today);
}
