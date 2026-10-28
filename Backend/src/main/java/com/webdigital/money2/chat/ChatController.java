package com.webdigital.money2.chat;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/chat")
public class ChatController {

    private final ChatService service;
    private final ChatSummaryPdfService pdfService;

    public ChatController(ChatService service, ChatSummaryPdfService pdfService) {
        this.service = service;
        this.pdfService = pdfService;
    }

    @PostMapping("/query")
    public ResponseEntity<ApiEnvelope<ChatResponse>> query(
            HttpServletRequest request,
            @Valid @RequestBody ChatRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(service.answer(currentUser(request), body)));
    }

    @GetMapping(value = "/summary-pdf", produces = MediaType.APPLICATION_PDF_VALUE)
    public ResponseEntity<byte[]> summaryPdf(
            HttpServletRequest request,
            @RequestParam long regionId,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {
        ChatSummaryPdfResult result = pdfService.generate(
                currentUser(request), regionId, startDate, endDate);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_PDF);
        headers.setContentDisposition(ContentDisposition.attachment()
                .filename(result.fileName(), StandardCharsets.UTF_8)
                .build());
        headers.setContentLength(result.bytes().length);
        return ResponseEntity.ok().headers(headers).body(result.bytes());
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
