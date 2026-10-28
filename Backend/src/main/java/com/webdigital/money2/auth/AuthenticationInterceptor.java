package com.webdigital.money2.auth;

import io.jsonwebtoken.JwtException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class AuthenticationInterceptor implements HandlerInterceptor {

    public static final String USER_ID_ATTRIBUTE = "money.auth.userId";
    public static final String USERNAME_ATTRIBUTE = "money.auth.username";
    public static final String USER_ATTRIBUTE = "money.auth.user";

    private final JwtService jwtService;
    private final AuthService authService;

    public AuthenticationInterceptor(
            JwtService jwtService,
            AuthService authService) {
        this.jwtService = jwtService;
        this.authService = authService;
    }

    @Override
    public boolean preHandle(
            HttpServletRequest request,
            HttpServletResponse response,
            Object handler) throws IOException {
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }

        String authorization = request.getHeader("Authorization");
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            reject(response);
            return false;
        }

        try {
            JwtService.AuthenticatedUser authenticated =
                    jwtService.parse(authorization.substring(7));
            UserAccount currentUser = authService.requireActiveUser(authenticated.username());
            if (!currentUser.getId().equals(authenticated.userId())) {
                reject(response);
                return false;
            }

            request.setAttribute(USER_ID_ATTRIBUTE, currentUser.getId());
            request.setAttribute(USERNAME_ATTRIBUTE, currentUser.getUsername());
            request.setAttribute(USER_ATTRIBUTE, currentUser);
            return true;
        } catch (JwtException | IllegalArgumentException | InvalidSessionException exception) {
            reject(response);
            return false;
        }
    }

    private void reject(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(
                "{\"errorMessage\":\"Sessão inválida ou expirada. Faça login novamente.\"}");
    }
}
