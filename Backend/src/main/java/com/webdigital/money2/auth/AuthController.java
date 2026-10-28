package com.webdigital.money2.auth;

import com.webdigital.money2.shared.ApiEnvelope;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/signin")
    public ResponseEntity<ApiEnvelope<TokenResponse>> signIn(
            @Valid @RequestBody SignInRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(authService.signIn(request)));
    }

    @GetMapping("/session")
    public ResponseEntity<ApiEnvelope<SessionResponse>> session(HttpServletRequest request) {
        UserAccount user = (UserAccount) request.getAttribute(
                AuthenticationInterceptor.USER_ATTRIBUTE);
        return ResponseEntity.ok(
                ApiEnvelope.of(new SessionResponse(
                        user.getId(),
                        user.getUsername(),
                        true,
                        user.isAdministrator(),
                        !user.isReadOnly(),
                        user.isCollector(),
                        user.isForcePasswordChange(),
                        authService.tutorialCompleted(user.getId()))));
    }

    @PutMapping("/password")
    public ResponseEntity<ApiEnvelope<TokenResponse>> changeRequiredPassword(
            HttpServletRequest request,
            @Valid @RequestBody PasswordChangeRequest passwordRequest) {
        UserAccount user = (UserAccount) request.getAttribute(
                AuthenticationInterceptor.USER_ATTRIBUTE);
        return ResponseEntity.ok(ApiEnvelope.of(
                authService.changeRequiredPassword(user.getId(), passwordRequest)));
    }

    @PutMapping("/tutorial")
    public ResponseEntity<ApiEnvelope<TokenResponse>> completeTutorial(
            HttpServletRequest request) {
        UserAccount user = (UserAccount) request.getAttribute(
                AuthenticationInterceptor.USER_ATTRIBUTE);
        return ResponseEntity.ok(ApiEnvelope.of(
                authService.completeTutorial(user.getId())));
    }

    @PostMapping("/tutorial/access")
    public ResponseEntity<Void> beginTutorial(HttpServletRequest request) {
        UserAccount user = (UserAccount) request.getAttribute(
                AuthenticationInterceptor.USER_ATTRIBUTE);
        authService.beginTutorial(user.getId());
        return ResponseEntity.noContent().build();
    }
}
