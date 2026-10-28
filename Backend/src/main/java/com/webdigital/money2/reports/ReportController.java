package com.webdigital.money2.reports;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/reports")
public class ReportController {

    private final ReportService reportService;

    public ReportController(ReportService reportService) {
        this.reportService = reportService;
    }

    @GetMapping("/history")
    public ResponseEntity<ApiEnvelope<AuditHistoryPageResponse>> history(
            HttpServletRequest request,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
            @RequestParam(defaultValue = "") String usernames,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "250") int size) {
        return ResponseEntity.ok(ApiEnvelope.of(reportService.history(
                currentUser(request), startDate, endDate,
                usernames, regionIds, page, size)));
    }

    @GetMapping("/history/export-data")
    public ResponseEntity<ApiEnvelope<AuditHistoryPageResponse>> exportHistory(
            HttpServletRequest request,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
            @RequestParam(defaultValue = "") String usernames,
            @RequestParam(defaultValue = "") String regionIds) {
        return ResponseEntity.ok(ApiEnvelope.of(reportService.exportHistory(
                currentUser(request), startDate, endDate, usernames, regionIds)));
    }

    @GetMapping("/history/users")
    public ResponseEntity<ApiEnvelope<List<String>>> users(
            HttpServletRequest request) {
        currentUser(request);
        return ResponseEntity.ok(ApiEnvelope.of(reportService.users()));
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
