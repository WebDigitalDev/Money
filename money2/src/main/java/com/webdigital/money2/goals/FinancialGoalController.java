package com.webdigital.money2.goals;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/financial-goals")
public class FinancialGoalController {

    private final FinancialGoalService goalService;

    public FinancialGoalController(FinancialGoalService goalService) {
        this.goalService = goalService;
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<List<FinancialGoalResponse>>> list(
            HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(goalService.list(currentUser(request))));
    }

    @PostMapping
    public ResponseEntity<ApiEnvelope<FinancialGoalResponse>> create(
            HttpServletRequest request,
            @Valid @RequestBody FinancialGoalRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiEnvelope.of(goalService.create(currentUser(request), body)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiEnvelope<FinancialGoalResponse>> update(
            HttpServletRequest request,
            @PathVariable long id,
            @Valid @RequestBody FinancialGoalRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(
                goalService.update(currentUser(request), id, body)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
            HttpServletRequest request,
            @PathVariable long id) {
        goalService.delete(currentUser(request), id);
        return ResponseEntity.noContent().build();
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
