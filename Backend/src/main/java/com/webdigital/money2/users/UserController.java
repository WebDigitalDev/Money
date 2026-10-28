package com.webdigital.money2.users;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.shared.PageResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v2/users")
public class UserController {

    private final UserManagementService userService;

    public UserController(UserManagementService userService) {
        this.userService = userService;
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<PageResponse<UserSummaryResponse>>> search(
            HttpServletRequest servletRequest,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "30") int size) {
        requireAdministrator(servletRequest);
        return ResponseEntity.ok(ApiEnvelope.of(userService.search(query, page, size)));
    }

    @GetMapping("/options")
    public ResponseEntity<ApiEnvelope<List<RegionOptionResponse>>> options(
            HttpServletRequest servletRequest) {
        requireAdministrator(servletRequest);
        return ResponseEntity.ok(ApiEnvelope.of(userService.getRegionOptions()));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiEnvelope<UserDetailResponse>> getById(
            HttpServletRequest servletRequest,
            @PathVariable Long id) {
        requireAdministrator(servletRequest);
        return ResponseEntity.ok(ApiEnvelope.of(userService.getById(id)));
    }

    @PostMapping
    public ResponseEntity<ApiEnvelope<UserDetailResponse>> create(
            HttpServletRequest servletRequest,
            @Valid @RequestBody UserCreateRequest request) {
        requireAdministrator(servletRequest);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiEnvelope.of(userService.create(request)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiEnvelope<UserDetailResponse>> update(
            HttpServletRequest servletRequest,
            @PathVariable Long id,
            @Valid @RequestBody UserUpdateRequest request) {
        requireAdministrator(servletRequest);
        return ResponseEntity.ok(ApiEnvelope.of(userService.update(id, request)));
    }

    @PutMapping("/{id}/password")
    public ResponseEntity<Void> changePassword(
            HttpServletRequest servletRequest,
            @PathVariable Long id,
            @Valid @RequestBody ChangePasswordRequest request) {
        requireAdministrator(servletRequest);
        userService.changePassword(id, request);
        return ResponseEntity.noContent().build();
    }

    private void requireAdministrator(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (!(authenticated instanceof UserAccount user) || !user.isAdministrator()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Apenas administradores podem acessar usuários.");
        }
    }
}
