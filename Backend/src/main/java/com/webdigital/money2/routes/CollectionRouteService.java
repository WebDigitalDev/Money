package com.webdigital.money2.routes;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.clients.CityOptionResponse;
import com.webdigital.money2.clients.ClientDocumentTypeResolver;
import com.webdigital.money2.shared.ApiException;
import java.io.IOException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
public class CollectionRouteService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final long MAX_ATTACHMENT_BYTES = 15L * 1024L * 1024L;

    private final CollectionRouteRepository routeRepository;
    private final CollectionEntityRepository collectionRepository;
    private final Path attachmentStorage;

    public CollectionRouteService(
            CollectionRouteRepository routeRepository,
            CollectionEntityRepository collectionRepository,
            @Value("${money.collections.storage-path:/home/money/money2/data/cobrancas/anexos}")
            String attachmentStorage) {
        this.routeRepository = routeRepository;
        this.collectionRepository = collectionRepository;
        this.attachmentStorage = Path.of(attachmentStorage).toAbsolutePath().normalize();
    }

    @Transactional(readOnly = true)
    public CollectionRoutePageResponse search(
            UserAccount user,
            String rawRegionIds,
            Long collectorId,
            Long cityId,
            String city,
            String sort,
            String query,
            int page,
            int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.max(10, Math.min(size, 100));
        Long owner = collectorRouteOwner(user);
        return routeRepository.search(
                user.getId(), owner == null ? positiveId(collectorId) : owner,
                parseRegionIds(rawRegionIds),
                positiveId(cityId), normalizeQuery(city),
                CollectionRouteSort.from(sort), normalizeQuery(query), true,
                safePage, safeSize);
    }

    @Transactional(readOnly = true)
    public CollectionRoutePageResponse candidates(
            UserAccount user,
            String rawRegionIds,
            Long cityId,
            String city,
            String sort,
            String query,
            int page,
            int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.max(10, Math.min(size, 100));
        return routeRepository.search(
                user.getId(), null, parseRegionIds(rawRegionIds),
                positiveId(cityId), normalizeQuery(city),
                CollectionRouteSort.from(sort), normalizeQuery(query), false,
                safePage, safeSize);
    }

    @Transactional(readOnly = true)
    public List<CollectionRouteCollectorResponse> collectors(UserAccount user) {
        return routeRepository.collectors();
    }

    @Transactional(readOnly = true)
    public List<CityOptionResponse> cities(
            UserAccount user,
            String rawRegionIds,
            Long collectorId,
            String query,
            boolean assignedOnly) {
        Long owner = assignedOnly ? collectorRouteOwner(user) : null;
        return routeRepository.cities(
                user.getId(), owner == null ? positiveId(collectorId) : owner,
                parseRegionIds(rawRegionIds), normalizeQuery(query), assignedOnly);
    }

    @Transactional(readOnly = true)
    public List<CollectionRouteCollectorResponse> assignedCollectors(
            UserAccount user,
            String rawRegionIds,
            Long cityId,
            String query) {
        return routeRepository.assignedCollectors(
                user.getId(), collectorRouteOwner(user), parseRegionIds(rawRegionIds),
                positiveId(cityId), normalizeQuery(query));
    }

    private Long positiveId(Long value) {
        return value != null && value > 0 ? value : null;
    }

    @Transactional
    public CollectionRouteAssignmentResponse assign(
            UserAccount user,
            CollectionRouteAssignmentRequest request) {
        requireRouteCreation(user);
        if (!routeRepository.collectorAvailable(request.collectorId())) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "O cobrador selecionado está inativo ou não está disponível.");
        }
        Set<Long> clientIds = new LinkedHashSet<>(request.clientIds());
        int assigned = routeRepository.assign(user.getId(), request.collectorId(), clientIds);
        if (assigned != clientIds.size()) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Um ou mais clientes não possuem dívida atrasada ou não pertencem às regiões do cobrador.");
        }
        return new CollectionRouteAssignmentResponse(assigned);
    }

    @Transactional
    public void removeAssignment(UserAccount user, long clientId) {
        requireRouteEditing(user);
        CollectionRouteItemResponse debt = routeRepository.requireAssignedDebt(
                user.getId(), clientId);
        requireVisibleRoute(user, debt);
        if (!routeRepository.removeAssignment(user.getId(), clientId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Rota não encontrada.");
        }
    }

    @Transactional(readOnly = true)
    public CollectionRouteDetailResponse detail(UserAccount user, long clientId) {
        CollectionRouteItemResponse debt = routeRepository.requireAssignedDebt(
                user.getId(), clientId);
        if (debt == null) {
            throw new ApiException(
                    HttpStatus.NOT_FOUND,
                    "O cliente não possui dívida atrasada nas regiões permitidas.");
        }
        requireVisibleRoute(user, debt);
        return new CollectionRouteDetailResponse(
                debt,
                routeRepository.contracts(user.getId(), clientId),
                withAvailability(routeRepository.history(clientId)),
                canRegister(user, debt));
    }

    @Transactional(readOnly = true)
    public List<CollectionHistoryResponse> clientHistory(UserAccount user, long clientId) {
        requireAccessibleClient(user, clientId);
        return withAvailability(routeRepository.history(clientId));
    }

    @Transactional
    public CollectionHistoryResponse register(
            UserAccount user,
            long clientId,
            String rawObservation,
            MultipartFile attachment) {
        CollectionRouteItemResponse debt = routeRepository.requireAssignedDebt(
                user.getId(), clientId);
        if (debt == null) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "A dívida não está mais atrasada e saiu da rota de cobrança.");
        }
        requireAssignedCollector(user, debt);

        String observation = clean(rawObservation);
        if (observation.isEmpty()) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Informe a observação da cobrança realizada.");
        }
        if (observation.length() > 4000) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A observação deve ter no máximo 4.000 caracteres.");
        }
        byte[] attachmentBytes = null;
        ClientDocumentTypeResolver.ResolvedFile resolved = null;
        if (attachment != null && !attachment.isEmpty()) {
            if (attachment.getSize() > MAX_ATTACHMENT_BYTES) {
                throw new ApiException(
                        HttpStatus.PAYLOAD_TOO_LARGE,
                        "O anexo deve ter no máximo 15 MB.");
            }
            try {
                attachmentBytes = attachment.getBytes();
            } catch (IOException exception) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Não foi possível ler o arquivo enviado.");
            }
            resolved = ClientDocumentTypeResolver.resolve(
                    attachment.getOriginalFilename(),
                    attachment.getContentType(),
                    attachmentBytes);
        }

        String storedName = attachmentBytes == null
                ? null
                : UUID.randomUUID() + "_" + clientId;
        Path storedPath = storedName == null ? null : safeResolve(storedName);
        if (storedPath != null) {
            try {
                Files.createDirectories(attachmentStorage);
                Files.write(storedPath, attachmentBytes);
            } catch (IOException exception) {
                throw new ApiException(
                        HttpStatus.INTERNAL_SERVER_ERROR,
                        "Não foi possível armazenar o anexo da cobrança.");
            }
        }

        CollectionEntity collection = new CollectionEntity();
        collection.setClientId(clientId);
        collection.setRegionId(debt.regionId());
        collection.setUserId(user.getId());
        collection.setObservation(observation);
        collection.setDebtAmount(money(debt.totalDebt()));
        collection.setOverdueDays(Math.max(debt.overdueDays(), 0));
        collection.setCreatedAt(LocalDateTime.now(BUSINESS_ZONE));
        if (resolved != null) {
            collection.setAttachmentName(resolved.fileName());
            collection.setAttachmentContentType(resolved.contentType());
            collection.setAttachmentDiskName(storedName);
            collection.setAttachmentSize((long) attachmentBytes.length);
        }

        try {
            CollectionEntity saved = collectionRepository.saveAndFlush(collection);
            return withAvailability(routeRepository.history(clientId)).stream()
                    .filter(item -> item.id() == saved.getId())
                    .findFirst()
                    .orElseThrow(() -> new ApiException(
                            HttpStatus.INTERNAL_SERVER_ERROR,
                            "A cobrança foi salva, mas não pôde ser recarregada."));
        } catch (RuntimeException exception) {
            deleteQuietly(storedPath);
            throw exception;
        }
    }

    @Transactional(readOnly = true)
    public CollectionAttachmentFile downloadAttachment(
            UserAccount user,
            long collectionId) {
        CollectionEntity collection = collectionRepository.findById(collectionId)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND, "Cobrança não encontrada."));
        requireAccessibleClient(user, collection.getClientId());
        Path path = existingPath(collection.getAttachmentDiskName());
        if (path == null) {
            throw new ApiException(
                    HttpStatus.NOT_FOUND,
                    "Esta cobrança não possui um anexo disponível.");
        }
        try {
            byte[] bytes = Files.readAllBytes(path);
            ClientDocumentTypeResolver.ResolvedFile resolved =
                    ClientDocumentTypeResolver.resolve(
                            collection.getAttachmentName(),
                            collection.getAttachmentContentType(),
                            bytes);
            return new CollectionAttachmentFile(
                    bytes, resolved.fileName(), resolved.contentType());
        } catch (IOException exception) {
            throw new ApiException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "Não foi possível ler o anexo da cobrança.");
        }
    }

    private boolean canRegister(UserAccount user, CollectionRouteItemResponse debt) {
        return user.isCollector()
                && debt.collectorId() != null
                && debt.collectorId().equals(user.getId());
    }

    private Long collectorRouteOwner(UserAccount user) {
        return user.isCollector() ? user.getId() : null;
    }

    private void requireRouteCreation(UserAccount user) {
        if (user.isCollector() && !user.isAdministrator() && user.isReadOnly()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Ative a permissão 'Permitir edições nas rotinas' para criar rotas.");
        }
    }

    private void requireVisibleRoute(
            UserAccount user,
            CollectionRouteItemResponse debt) {
        if (debt == null) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Rota não encontrada.");
        }
        if (user.isCollector()
                && (debt.collectorId() == null || !debt.collectorId().equals(user.getId()))) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Rota não encontrada.");
        }
    }

    private void requireRouteEditing(UserAccount user) {
        if (user.isCollector() && !user.isAdministrator() && user.isReadOnly()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Ative a permissão 'Permitir edições nas rotinas' para remover rotas.");
        }
    }

    private void requireAssignedCollector(
            UserAccount user,
            CollectionRouteItemResponse debt) {
        if (!canRegister(user, debt)) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Somente o cobrador responsável por esta rota pode registrar cobranças.");
        }
    }

    private void requireAccessibleClient(UserAccount user, long clientId) {
        if (!routeRepository.clientAccessible(user.getId(), clientId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Cliente não encontrado.");
        }
    }

    private Set<Long> parseRegionIds(String value) {
        Set<Long> result = new HashSet<>();
        if (value == null || value.isBlank()) return result;
        for (String part : value.split(",")) {
            try {
                long id = Long.parseLong(part.trim());
                if (id > 0) result.add(id);
            } catch (NumberFormatException exception) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Uma ou mais regiões informadas são inválidas.");
            }
        }
        return result;
    }

    private String normalizeQuery(String value) {
        String cleaned = clean(value);
        return cleaned.length() > 100 ? cleaned.substring(0, 100) : cleaned;
    }

    private List<CollectionHistoryResponse> withAvailability(
            List<CollectionHistoryResponse> items) {
        // A listagem usa o metadado persistido e não toca o disco item a item.
        // A existência física é validada somente quando o usuário abre o anexo.
        return List.copyOf(items);
    }

    private Path existingPath(String storedName) {
        if (storedName == null || storedName.isBlank()) return null;
        Path path = safeResolve(storedName);
        return Files.isRegularFile(path) ? path : null;
    }

    private Path safeResolve(String storedName) {
        Path path = attachmentStorage.resolve(storedName).normalize();
        if (!path.startsWith(attachmentStorage)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Nome de arquivo inválido.");
        }
        return path;
    }

    private void deleteQuietly(Path path) {
        if (path == null) return;
        try {
            Files.deleteIfExists(path);
        } catch (IOException ignored) { }
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
