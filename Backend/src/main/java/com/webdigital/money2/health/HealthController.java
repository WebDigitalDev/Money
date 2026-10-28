package com.webdigital.money2.health;

import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/health")
public class HealthController {

    private final JdbcTemplate jdbcTemplate;

    public HealthController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping
    public Map<String, String> health() {
        Integer databaseStatus = jdbcTemplate.queryForObject("select 1", Integer.class);
        String readOnlyStatus = jdbcTemplate.queryForObject(
                "select current_setting('transaction_read_only')",
                String.class);
        String databaseVersion = jdbcTemplate.queryForObject(
                "select current_setting('server_version')",
                String.class);
        return Map.of(
                "status", databaseStatus != null && databaseStatus == 1 ? "UP" : "DOWN",
                "service", "money2",
                "database", "UP",
                "databaseVersion", databaseVersion,
                "databaseMode", "on".equalsIgnoreCase(readOnlyStatus) ? "READ_ONLY" : "READ_WRITE");
    }
}
