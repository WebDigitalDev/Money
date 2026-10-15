package com.webdigital.money2.integrations;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.integrations.IntegrationModels.ActionResult;
import com.webdigital.money2.integrations.IntegrationModels.BankAccount;
import com.webdigital.money2.integrations.IntegrationModels.BankAccountRequest;
import com.webdigital.money2.integrations.IntegrationModels.DispatchRequest;
import com.webdigital.money2.integrations.IntegrationModels.PhoneRequest;
import com.webdigital.money2.integrations.IntegrationModels.RegionSelectionRequest;
import com.webdigital.money2.integrations.IntegrationModels.SicrediConfigRequest;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappConfig;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappConfigRequest;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappDevice;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappLog;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
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
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v2/integrations")
public class IntegrationController {

    private final IntegrationService service;

    public IntegrationController(IntegrationService service) {
        this.service = service;
    }

    @GetMapping("/banking/accounts")
    public ResponseEntity<ApiEnvelope<List<BankAccount>>> bankAccounts(HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.bankAccounts(currentUser(request))));
    }

    @PostMapping("/banking/accounts")
    public ResponseEntity<ApiEnvelope<BankAccount>> createBank(
            HttpServletRequest request, @RequestBody BankAccountRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.createBank(currentUser(request), body)));
    }

    @GetMapping("/banking/accounts/{id}")
    public ResponseEntity<ApiEnvelope<BankAccount>> bank(
            HttpServletRequest request, @PathVariable long id) {
        return ResponseEntity.ok(ApiEnvelope.of(service.bank(currentUser(request), id)));
    }

    @PutMapping("/banking/accounts/{id}")
    public ResponseEntity<ApiEnvelope<BankAccount>> updateBank(
            HttpServletRequest request, @PathVariable long id, @RequestBody BankAccountRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.updateBank(currentUser(request), id, body)));
    }

    @PutMapping("/banking/accounts/{id}/sicredi")
    public ResponseEntity<ApiEnvelope<BankAccount>> saveSicredi(
            HttpServletRequest request, @PathVariable long id, @RequestBody SicrediConfigRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.saveSicredi(currentUser(request), id, body)));
    }

    @PostMapping(value = "/banking/accounts/{id}/certificates", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<ApiEnvelope<BankAccount>> uploadSicredi(
            HttpServletRequest request,
            @PathVariable long id,
            @RequestParam(required = false) MultipartFile certificate,
            @RequestParam(required = false) MultipartFile privateKey,
            @RequestParam(required = false) MultipartFile certificateChain) {
        return ResponseEntity.ok(ApiEnvelope.of(service.uploadSicrediFiles(
                currentUser(request), id, certificate, privateKey, certificateChain)));
    }

    @GetMapping("/whatsapp/config")
    public ResponseEntity<ApiEnvelope<WhatsappConfig>> whatsappConfig(HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.whatsappConfig(currentUser(request))));
    }

    @PutMapping("/whatsapp/config")
    public ResponseEntity<ApiEnvelope<WhatsappConfig>> saveWhatsappConfig(
            HttpServletRequest request, @RequestBody WhatsappConfigRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.saveWhatsappConfig(currentUser(request), body)));
    }

    @GetMapping("/whatsapp/devices")
    public ResponseEntity<ApiEnvelope<List<WhatsappDevice>>> devices(HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.devices(currentUser(request))));
    }

    @GetMapping("/whatsapp/devices/progress")
    public ResponseEntity<ApiEnvelope<List<WhatsappDevice>>> deviceProgress(HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.deviceProgress(currentUser(request))));
    }

    @PostMapping("/whatsapp/devices/{id}/refresh")
    public ResponseEntity<ApiEnvelope<WhatsappDevice>> refreshDevice(
            HttpServletRequest request, @PathVariable long id) {
        return ResponseEntity.ok(ApiEnvelope.of(service.refreshDevice(currentUser(request), id)));
    }

    @PutMapping("/whatsapp/devices/{id}/regions")
    public ResponseEntity<ApiEnvelope<WhatsappDevice>> deviceRegions(
            HttpServletRequest request, @PathVariable long id,
            @RequestBody RegionSelectionRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.updateDeviceRegions(
                currentUser(request), id, body == null ? List.of() : body.regionIds())));
    }

    @PostMapping("/whatsapp/devices/{id}/test")
    public ResponseEntity<ApiEnvelope<WhatsappLog>> test(
            HttpServletRequest request, @PathVariable long id, @RequestBody PhoneRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.sendTest(
                currentUser(request), id, body == null ? null : body.phone())));
    }

    @PostMapping("/whatsapp/devices/{id}/dispatch")
    public ResponseEntity<ApiEnvelope<ActionResult>> dispatch(
            HttpServletRequest request, @PathVariable long id, @RequestBody DispatchRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.startDispatch(
                currentUser(request), id, body == null ? null : body.type())));
    }

    @PostMapping("/whatsapp/devices/{id}/dispatch/test")
    public ResponseEntity<ApiEnvelope<ActionResult>> dispatchTest(
            HttpServletRequest request, @PathVariable long id, @RequestBody PhoneRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.startDispatchTest(
                currentUser(request), id, body == null ? null : body.phone())));
    }

    @PostMapping("/whatsapp/devices/{id}/stop")
    public ResponseEntity<ApiEnvelope<WhatsappDevice>> stop(
            HttpServletRequest request, @PathVariable long id) {
        return ResponseEntity.ok(ApiEnvelope.of(service.stopDispatch(currentUser(request), id)));
    }

    @GetMapping("/whatsapp/logs")
    public ResponseEntity<ApiEnvelope<List<WhatsappLog>>> logs(HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.logs(currentUser(request))));
    }

    @DeleteMapping("/whatsapp/logs")
    public ResponseEntity<ApiEnvelope<ActionResult>> clearLogs(HttpServletRequest request) {
        service.clearLogs(currentUser(request));
        return ResponseEntity.ok(ApiEnvelope.of(new ActionResult("Logs removidos.")));
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
