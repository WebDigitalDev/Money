package com.webdigital.money2.regions;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/regions")
public class RegionController {

    private final RegionManagementService regionService;

    public RegionController(RegionManagementService regionService) {
        this.regionService = regionService;
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<RegionListResponse>> search(
            HttpServletRequest servletRequest,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {
        return ResponseEntity.ok(ApiEnvelope.of(regionService.search(
                currentUser(servletRequest), query, startDate, endDate, regionIds)));
    }

    @GetMapping("/options")
    public ResponseEntity<ApiEnvelope<List<RegionOptionResponse>>> options(
            HttpServletRequest servletRequest,
            @RequestParam(defaultValue = "false") boolean tutorial) {
        return ResponseEntity.ok(ApiEnvelope.of(
                regionService.options(currentUser(servletRequest), tutorial)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiEnvelope<RegionDetailResponse>> getById(
            HttpServletRequest servletRequest,
            @PathVariable Long id) {
        return ResponseEntity.ok(ApiEnvelope.of(
                regionService.getById(currentUser(servletRequest), id)));
    }

    @PostMapping
    public ResponseEntity<ApiEnvelope<RegionDetailResponse>> create(
            HttpServletRequest servletRequest,
            @Valid @RequestBody RegionRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                regionService.create(currentUser(servletRequest), request)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiEnvelope<RegionDetailResponse>> update(
            HttpServletRequest servletRequest,
            @PathVariable Long id,
            @Valid @RequestBody RegionRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(
                regionService.update(currentUser(servletRequest), id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
            HttpServletRequest servletRequest,
            @PathVariable Long id) {
        regionService.delete(currentUser(servletRequest), id);
        return ResponseEntity.noContent().build();
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) {
            return user;
        }
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
