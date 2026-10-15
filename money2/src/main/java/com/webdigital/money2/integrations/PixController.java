package com.webdigital.money2.integrations;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
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
@RequestMapping("/api/v2")
public class PixController {

    private final PixService service;

    public PixController(PixService service) {
        this.service = service;
    }

    @GetMapping("/loans/{loanId}/pix/current")
    public ResponseEntity<ApiEnvelope<PixChargeResponse>> current(
            HttpServletRequest request, @PathVariable long loanId,
            @RequestParam(required = false) Long installmentId) {
        return ResponseEntity.ok(ApiEnvelope.of(service.current(currentUser(request), loanId, installmentId)));
    }

    @PostMapping("/loans/{loanId}/pix")
    public ResponseEntity<ApiEnvelope<PixChargeResponse>> generate(
            HttpServletRequest request, @PathVariable long loanId,
            @RequestBody PixGenerateRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.generate(currentUser(request), loanId, body)));
    }

    @PostMapping("/loans/{loanId}/pix/cancel-pending")
    public ResponseEntity<ApiEnvelope<PixCancellationResult>> cancelPending(
            HttpServletRequest request, @PathVariable long loanId) {
        return ResponseEntity.ok(ApiEnvelope.of(service.cancelPending(currentUser(request), loanId)));
    }

    @PostMapping("/pix/{pixId}/refresh")
    public ResponseEntity<ApiEnvelope<PixChargeResponse>> refresh(
            HttpServletRequest request, @PathVariable long pixId) {
        return ResponseEntity.ok(ApiEnvelope.of(service.refresh(currentUser(request), pixId)));
    }

    @PostMapping("/pix/{pixId}/whatsapp")
    public ResponseEntity<ApiEnvelope<PixChargeResponse>> whatsapp(
            HttpServletRequest request, @PathVariable long pixId) {
        return ResponseEntity.ok(ApiEnvelope.of(service.sendWhatsapp(currentUser(request), pixId)));
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
