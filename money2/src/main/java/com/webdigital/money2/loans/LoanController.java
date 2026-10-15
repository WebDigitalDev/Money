package com.webdigital.money2.loans;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/loans")
public class LoanController {

    private final LoanManagementService loanService;
    private final LoanDetailService detailService;
    private final LoanFeedbackService feedbackService;

    public LoanController(
            LoanManagementService loanService,
            LoanDetailService detailService,
            LoanFeedbackService feedbackService) {
        this.loanService = loanService;
        this.detailService = detailService;
        this.feedbackService = feedbackService;
    }

    @PostMapping
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> create(
            HttpServletRequest request, @RequestBody LoanCreateRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiEnvelope.of(detailService.create(currentUser(request), body)));
    }

    @GetMapping("/{loanId}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> detail(
            HttpServletRequest request, @PathVariable long loanId,
            @RequestParam(defaultValue = "false") boolean compact) {
        return ResponseEntity.ok(ApiEnvelope.of(
                detailService.get(currentUser(request), loanId, compact)));
    }

    @GetMapping("/{loanId}/feedbacks")
    public ResponseEntity<ApiEnvelope<java.util.List<LoanFeedbackResponse>>> feedbacks(
            HttpServletRequest request, @PathVariable long loanId) {
        return ResponseEntity.ok(ApiEnvelope.of(
                feedbackService.list(currentUser(request), loanId)));
    }

    @PostMapping("/{loanId}/feedbacks")
    public ResponseEntity<ApiEnvelope<LoanFeedbackResponse>> addFeedback(
            HttpServletRequest request, @PathVariable long loanId,
            @Valid @RequestBody LoanFeedbackRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                feedbackService.add(currentUser(request), loanId, body)));
    }

    @DeleteMapping("/{loanId}/feedbacks/{feedbackId}")
    public ResponseEntity<Void> deleteFeedback(
            HttpServletRequest request, @PathVariable long loanId,
            @PathVariable long feedbackId) {
        feedbackService.delete(currentUser(request), loanId, feedbackId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{loanId}/message/{type}")
    public ResponseEntity<ApiEnvelope<LoanMessageResponse>> message(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable String type) {
        return ResponseEntity.ok(ApiEnvelope.of(
                detailService.message(currentUser(request), loanId, type)));
    }

    @GetMapping("/{loanId}/installments/{installmentId}/message/{type}")
    public ResponseEntity<ApiEnvelope<LoanMessageResponse>> installmentMessage(
            HttpServletRequest request, @PathVariable long loanId,
            @PathVariable long installmentId, @PathVariable String type) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.installmentMessage(
                currentUser(request), loanId, installmentId, type)));
    }

    @PutMapping("/{loanId}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> update(
            HttpServletRequest request, @PathVariable long loanId,
            @RequestBody LoanUpdateRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.update(currentUser(request), loanId, body)));
    }

    @PutMapping("/{loanId}/installments/{installmentId}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> updateInstallment(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable long installmentId,
            @RequestBody InstallmentUpdateRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.updateInstallment(
                currentUser(request), loanId, installmentId, body)));
    }

    @PostMapping("/{loanId}/installments/{installmentId}/payments")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> addPayment(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable long installmentId,
            @RequestBody PaymentRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.addPayment(
                currentUser(request), loanId, installmentId, body)));
    }

    @PutMapping("/{loanId}/installments/{installmentId}/payments/{paymentId}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> updatePayment(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable long installmentId,
            @PathVariable long paymentId, @RequestBody PaymentRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.updatePayment(
                currentUser(request), loanId, installmentId, paymentId, body)));
    }

    @DeleteMapping("/{loanId}/installments/{installmentId}/payments/{paymentId}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> deletePayment(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable long installmentId,
            @PathVariable long paymentId) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.deletePayment(
                currentUser(request), loanId, installmentId, paymentId)));
    }

    @PostMapping("/{loanId}/payments")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> distributePayment(
            HttpServletRequest request, @PathVariable long loanId, @RequestBody PaymentRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.distributePayment(currentUser(request), loanId, body)));
    }

    @PostMapping("/{loanId}/interest-roll")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> interestOnlyPayment(
            HttpServletRequest request, @PathVariable long loanId,
            @RequestBody InterestOnlyPaymentRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(
                detailService.interestOnlyPayment(currentUser(request), loanId, body)));
    }

    @PostMapping("/{loanId}/closure/{action}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> requestClosure(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable String action) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.requestClosure(currentUser(request), loanId, action)));
    }

    @PostMapping("/{loanId}/negotiations/{mode}")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> negotiate(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable String mode,
            @RequestBody LoanNegotiationRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.negotiate(currentUser(request), loanId, mode, body)));
    }

    @PostMapping("/{loanId}/approvals/{approvalId}/approve")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> approve(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable long approvalId,
            @RequestBody(required = false) LoanDecisionRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.decideApproval(
                currentUser(request), loanId, approvalId, true, body)));
    }

    @PostMapping("/{loanId}/approvals/{approvalId}/reject")
    public ResponseEntity<ApiEnvelope<LoanDetailResponse>> reject(
            HttpServletRequest request, @PathVariable long loanId, @PathVariable long approvalId,
            @RequestBody LoanDecisionRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(detailService.decideApproval(
                currentUser(request), loanId, approvalId, false, body)));
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<LoanListResponse>> search(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "") String statuses,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(defaultValue = "false") boolean tutorial,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return ResponseEntity.ok(ApiEnvelope.of(loanService.search(
                currentUser(request), query, statuses, regionIds, tutorial,
                startDate, endDate, page, size)));
    }

    @GetMapping("/export-data")
    public ResponseEntity<ApiEnvelope<LoanListResponse>> exportData(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "") String statuses,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(defaultValue = "false") boolean tutorial,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {
        return ResponseEntity.ok(ApiEnvelope.of(loanService.export(
                currentUser(request), query, statuses, regionIds, tutorial,
                startDate, endDate)));
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
