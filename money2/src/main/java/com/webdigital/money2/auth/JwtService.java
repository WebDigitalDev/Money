package com.webdigital.money2.auth;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.stereotype.Service;

@Service
public class JwtService {

    private final SecretKey signingKey;
    private final Duration tokenValidity;

    public JwtService(MoneySecurityProperties properties) {
        this.signingKey = Keys.hmacShaKeyFor(
                Decoders.BASE64.decode(properties.jwtSecret()));
        this.tokenValidity = Duration.ofHours(properties.tokenValidityHours());
    }

    public TokenResponse issue(UserAccount user, boolean tutorialCompleted) {
        Instant issuedAt = Instant.now();
        Instant expiresAt = issuedAt.plus(tokenValidity);

        String token = Jwts.builder()
                .subject(user.getUsername())
                .claim("userName", user.getUsername())
                .claim("userId", user.getId())
                .issuedAt(Date.from(issuedAt))
                .expiration(Date.from(expiresAt))
                .signWith(signingKey)
                .compact();

        return new TokenResponse(
                token,
                user.getUsername(),
                user.getId(),
                user.isAdministrator(),
                !user.isReadOnly(),
                user.isCollector(),
                user.isForcePasswordChange(),
                tutorialCompleted,
                expiresAt);
    }

    public AuthenticatedUser parse(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(signingKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

        Number rawUserId = claims.get("userId", Number.class);
        if (claims.getSubject() == null || rawUserId == null) {
            throw new InvalidSessionException();
        }

        return new AuthenticatedUser(rawUserId.longValue(), claims.getSubject());
    }

    public record AuthenticatedUser(long userId, String username) {
    }
}
