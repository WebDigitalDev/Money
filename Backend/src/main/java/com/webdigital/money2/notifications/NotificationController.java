package com.webdigital.money2.notifications;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v2/notifications")
public class NotificationController {
    private final NotificationRepository repository;
    public NotificationController(NotificationRepository repository) { this.repository=repository; }
    private long user(HttpServletRequest request) {
        return ((UserAccount)request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE)).getId();
    }
    @GetMapping public Object list(HttpServletRequest request) { return ApiEnvelope.of(repository.list(user(request))); }
    @GetMapping("/preferences") public Object preferences(HttpServletRequest request) {
        return ApiEnvelope.of(repository.preferences(user(request)));
    }
    @PutMapping("/preferences") public Object preferences(HttpServletRequest request,
            @RequestBody NotificationRepository.Preferences body) {
        repository.preferences(user(request),body); return ApiEnvelope.of(repository.preferences(user(request)));
    }
}
