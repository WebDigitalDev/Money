package com.webdigital.money2.users;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/profile")
public class ProfileController {

    private final UserManagementService userService;

    public ProfileController(UserManagementService userService) {
        this.userService = userService;
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<UserDetailResponse>> getProfile(
            HttpServletRequest request) {
        UserAccount user = (UserAccount) request.getAttribute(
                AuthenticationInterceptor.USER_ATTRIBUTE);
        return ResponseEntity.ok(ApiEnvelope.of(userService.getProfile(user.getId())));
    }
}
