package com.webdigital.money2.codex;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.chat.ChatRequest;
import com.webdigital.money2.chat.ChatResponse;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v2/codex")
public class CodexController {

    private final CodexAppServerService service;

    public CodexController(CodexAppServerService service) {
        this.service = service;
    }

    @GetMapping("/status")
    public ResponseEntity<ApiEnvelope<CodexConnectionResponse>> status(
            HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.status(currentUser(request))));
    }

    @PostMapping("/connect")
    public ResponseEntity<ApiEnvelope<CodexLoginChallengeResponse>> connect(
            HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(service.connect(currentUser(request))));
    }

    @DeleteMapping("/connection")
    public ResponseEntity<Void> disconnect(HttpServletRequest request) {
        service.disconnect(currentUser(request));
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/query")
    public ResponseEntity<ApiEnvelope<ChatResponse>> query(
            HttpServletRequest request,
            @Valid @RequestBody ChatRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.answer(currentUser(request), body)));
    }

    @PostMapping(value = "/query-with-files", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<ApiEnvelope<ChatResponse>> queryWithFiles(
            HttpServletRequest request,
            @RequestParam String message,
            @RequestParam String conversationId,
            @RequestParam(defaultValue = "READY") String mode,
            @RequestParam(required = false) Long clientId,
            @RequestParam(required = false) Long regionId,
            @RequestParam(required = false) String model,
            @RequestParam(required = false) String serviceTier,
            @RequestParam(name = "files", required = false) List<MultipartFile> files) {
        String cleanMessage = message == null ? "" : message.trim();
        if (cleanMessage.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Digite uma mensagem.");
        }
        if (cleanMessage.length() > 200) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "A mensagem deve ter no máximo 200 caracteres.");
        }
        List<CodexAttachment> attachments = new ArrayList<>();
        if (files != null) {
            for (MultipartFile file : files) {
                if (file == null || file.isEmpty()) continue;
                try {
                    attachments.add(new CodexAttachment(
                            file.getOriginalFilename(), file.getContentType(), file.getBytes()));
                } catch (IOException exception) {
                    throw new ApiException(HttpStatus.BAD_REQUEST,
                            "Não foi possível ler um dos arquivos enviados.");
                }
            }
        }
        ChatRequest body = new ChatRequest(cleanMessage, mode, clientId, regionId,
                conversationId, model, serviceTier);
        return ResponseEntity.ok(ApiEnvelope.of(
                service.answer(currentUser(request), body, attachments)));
    }

    @PostMapping("/interrupt")
    public ResponseEntity<Void> interrupt(
            HttpServletRequest request,
            @RequestParam String conversationId) {
        service.interrupt(currentUser(request), conversationId);
        return ResponseEntity.noContent().build();
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
