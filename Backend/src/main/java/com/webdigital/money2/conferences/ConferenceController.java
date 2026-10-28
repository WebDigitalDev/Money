package com.webdigital.money2.conferences;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/conferences")
public class ConferenceController {

    private final ConferenceService service;

    public ConferenceController(ConferenceService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<ConferenceListResponse>> search(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "ALL") String category,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size,
            @RequestParam(defaultValue = "true") boolean includeDetails) {
        return ResponseEntity.ok(ApiEnvelope.of(service.search(
                currentUser(request), query, category, regionIds, page, size, includeDetails)));
    }

    @GetMapping("/{conferenceId}/details")
    public ResponseEntity<ApiEnvelope<ConferenceDetailsResponse>> details(
            HttpServletRequest request, @PathVariable long conferenceId) {
        List<ConferenceDetailResponse> details = service.details(currentUser(request), conferenceId);
        return ResponseEntity.ok(ApiEnvelope.of(new ConferenceDetailsResponse(details)));
    }

    @PostMapping("/{conferenceId}/approve")
    public ResponseEntity<ApiEnvelope<ConferenceDecisionResponse>> approve(
            HttpServletRequest request, @PathVariable long conferenceId,
            @RequestBody(required = false) ConferenceDecisionRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(
                service.decide(currentUser(request), conferenceId, true, body)));
    }

    @PostMapping("/{conferenceId}/reject")
    public ResponseEntity<ApiEnvelope<ConferenceDecisionResponse>> reject(
            HttpServletRequest request, @PathVariable long conferenceId,
            @RequestBody ConferenceDecisionRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(
                service.decide(currentUser(request), conferenceId, false, body)));
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
