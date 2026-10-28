package com.webdigital.money2.auth;

import com.webdigital.money2.shared.ApiException;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Locale;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final UserAccountRepository userRepository;
    private final UserTutorialStatusRepository tutorialStatusRepository;
    private final JwtService jwtService;
    private final TutorialRegionAccessService tutorialRegionAccessService;
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

    public AuthService(
            UserAccountRepository userRepository,
            UserTutorialStatusRepository tutorialStatusRepository,
            JwtService jwtService,
            TutorialRegionAccessService tutorialRegionAccessService) {
        this.userRepository = userRepository;
        this.tutorialStatusRepository = tutorialStatusRepository;
        this.jwtService = jwtService;
        this.tutorialRegionAccessService = tutorialRegionAccessService;
    }

    @Transactional
    public TokenResponse signIn(SignInRequest request) {
        String username = normalize(request.username());
        UserAccount user = userRepository.findByNormalizedUsername(username)
                .orElseThrow(this::invalidCredentials);

        if (!passwordMatches(request.password(), user.getPasswordHash())) {
            throw invalidCredentials();
        }

        validateAccess(user);
        user.setLastAccess(LocalDateTime.now(BUSINESS_ZONE));
        userRepository.save(user);
        tutorialRegionAccessService.synchronize(user);
        return jwtService.issue(user, tutorialCompleted(user.getId()));
    }

    @Transactional(readOnly = true)
    public UserAccount requireActiveUser(String username) {
        UserAccount user = userRepository.findByNormalizedUsername(normalize(username))
                .orElseThrow(InvalidSessionException::new);
        validateAccess(user);
        return user;
    }

    @Transactional
    public TokenResponse changeRequiredPassword(
            Long userId,
            PasswordChangeRequest request) {
        UserAccount user = userRepository.findById(userId)
                .orElseThrow(InvalidSessionException::new);
        if (passwordMatches(request.password(), user.getPasswordHash())) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A nova senha deve ser diferente da senha atual.");
        }

        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setCredentialsExpired(false);
        user.setForcePasswordChange(false);
        userRepository.saveAndFlush(user);
        return jwtService.issue(user, tutorialCompleted(user.getId()));
    }

    @Transactional
    public TokenResponse completeTutorial(Long userId) {
        UserAccount user = userRepository.findById(userId)
                .orElseThrow(InvalidSessionException::new);
        if (!tutorialStatusRepository.existsById(userId)) {
            tutorialStatusRepository.saveAndFlush(new UserTutorialStatus(
                    userId,
                    LocalDateTime.now(BUSINESS_ZONE)));
        }
        tutorialRegionAccessService.synchronize(user);
        return jwtService.issue(user, true);
    }

    @Transactional
    public void beginTutorial(Long userId) {
        UserAccount user = userRepository.findById(userId)
                .orElseThrow(InvalidSessionException::new);
        tutorialRegionAccessService.grantTemporaryAccess(user);
    }

    @Transactional(readOnly = true)
    public boolean tutorialCompleted(Long userId) {
        return tutorialStatusRepository.existsById(userId);
    }

    private boolean passwordMatches(String password, String hash) {
        try {
            return hash != null && passwordEncoder.matches(password, hash);
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }

    private void validateAccess(UserAccount user) {
        if (!user.isEnabled()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Usuário desativado. Entre em contato com o administrador.");
        }
        if (user.isLocked()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Usuário bloqueado. Entre em contato com o administrador.");
        }
        if (user.isExpired()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Usuário expirado. Entre em contato com o administrador.");
        }
        if (user.isCredentialsExpired()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Credenciais expiradas. Altere a senha para continuar.");
        }
    }

    private ApiException invalidCredentials() {
        return new ApiException(
                HttpStatus.UNAUTHORIZED,
                "Usuário/Senha inválido.");
    }

    private String normalize(String username) {
        return username == null ? "" : username.trim().toUpperCase(Locale.ROOT);
    }
}
