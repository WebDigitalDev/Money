package com.webdigital.money2.clients;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.auth.TutorialRegionAccessService;
import com.webdigital.money2.chat.ClientIndexRequested;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionOptionResponse;
import com.webdigital.money2.users.RegionRepository;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
public class ClientManagementService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final long MAX_DOCUMENT_BYTES = 15L * 1024 * 1024;
    private static final int EXPORT_PAGE_SIZE = 500_000;

    private final ClientRepository clientRepository;
    private final ClientQueryRepository clientQueryRepository;
    private final ClientScoreRepository clientScoreRepository;
    private final TutorialRegionAccessService tutorialRegionAccessService;
    private final CityRepository cityRepository;
    private final RegionRepository regionRepository;
    private final ClientContactRepository contactRepository;
    private final ClientDocumentRepository documentRepository;
    private final ApplicationEventPublisher eventPublisher;
    private final Path documentStorage;
    private final Path legacyDocumentStorage;

    public ClientManagementService(
            ClientRepository clientRepository,
            ClientQueryRepository clientQueryRepository,
            ClientScoreRepository clientScoreRepository,
            TutorialRegionAccessService tutorialRegionAccessService,
            CityRepository cityRepository,
            RegionRepository regionRepository,
            ClientContactRepository contactRepository,
            ClientDocumentRepository documentRepository,
            ApplicationEventPublisher eventPublisher,
            @Value("${money.documents.storage-path:/home/money/money2/data/clientes/documentos}")
            String documentStorage,
            @Value("${money.documents.legacy-storage-path:/home/money/moneyapp/data/clientes/documentos}")
            String legacyDocumentStorage) {
        this.clientRepository = clientRepository;
        this.clientQueryRepository = clientQueryRepository;
        this.clientScoreRepository = clientScoreRepository;
        this.tutorialRegionAccessService = tutorialRegionAccessService;
        this.cityRepository = cityRepository;
        this.regionRepository = regionRepository;
        this.contactRepository = contactRepository;
        this.documentRepository = documentRepository;
        this.eventPublisher = eventPublisher;
        this.documentStorage = Path.of(documentStorage).toAbsolutePath().normalize();
        this.legacyDocumentStorage = Path.of(legacyDocumentStorage).toAbsolutePath().normalize();
    }

    @Transactional(readOnly = true)
    public ClientListResponse search(
            UserAccount user,
            String rawStatus,
            String query,
            String rawRegionIds,
            boolean tutorial,
            int page,
            int size) {
        int safePage = Math.max(0, page);
        int safeSize = Math.max(10, Math.min(size, 100));
        Long tutorialRegionId = tutorial
                ? requireTutorialRegionId()
                : null;
        return clientQueryRepository.search(
                user.getId(),
                parseStatus(rawStatus),
                query,
                tutorial ? Set.of(tutorialRegionId) : parseRegionIds(rawRegionIds),
                tutorial,
                tutorialRegionId,
                safePage,
                safeSize);
    }

    @Transactional(readOnly = true)
    public ClientListResponse export(
            UserAccount user,
            String rawStatus,
            String query,
            String rawRegionIds,
            boolean tutorial) {
        Long tutorialRegionId = tutorial
                ? requireTutorialRegionId()
                : null;
        return clientQueryRepository.search(
                user.getId(),
                parseStatus(rawStatus),
                query,
                tutorial ? Set.of(tutorialRegionId) : parseRegionIds(rawRegionIds),
                tutorial,
                tutorialRegionId,
                0,
                EXPORT_PAGE_SIZE);
    }

    private Long requireTutorialRegionId() {
        Long id = tutorialRegionAccessService.tutorialRegionId();
        if (id == null) {
            throw new ApiException(
                    HttpStatus.NOT_FOUND,
                    "A região TUTORIAL não foi encontrada.");
        }
        return id;
    }

    private ClientStatus parseStatus(String rawStatus) {
        return "ALL".equalsIgnoreCase(clean(rawStatus))
                ? null
                : ClientStatus.parse(rawStatus);
    }

    @Transactional(readOnly = true)
    public ClientDetailResponse getById(UserAccount user, Long id) {
        return toDetail(requireAccessible(user, id), user);
    }

    @Transactional
    public ClientDetailResponse create(UserAccount user, ClientRequest request) {
        requireEditable(user);
        validateRequiredCreateFields(request);
        LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
        ClientEntity client = new ClientEntity();
        client.setEnabled(true);
        client.setCreatedAt(now);
        apply(client, request, user);
        client.setUpdatedAt(now);
        ClientEntity saved = clientRepository.saveAndFlush(client);
        eventPublisher.publishEvent(new ClientIndexRequested(saved.getId()));
        return toDetail(saved, user);
    }

    @Transactional
    public ClientDetailResponse update(
            UserAccount user,
            Long id,
            ClientRequest request) {
        requireEditable(user);
        ClientEntity client = requireAccessible(user, id);
        apply(client, request, user);
        client.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
        ClientEntity saved = clientRepository.saveAndFlush(client);
        eventPublisher.publishEvent(new ClientIndexRequested(saved.getId()));
        return toDetail(saved, user);
    }

    @Transactional(readOnly = true)
    public List<RegionOptionResponse> duplicateRegions(UserAccount user, Long id) {
        requireEditable(user);
        ClientEntity source = requireAccessible(user, id);
        String document = requiredDuplicateDocument(source);
        Set<Long> occupiedRegionIds = Set.copyOf(
                clientRepository.findRegionIdsByNormalizedDocument(document));
        return regionRepository.findAccessibleByUserId(user.getId()).stream()
                .filter(region -> !occupiedRegionIds.contains(region.getId()))
                .map(region -> new RegionOptionResponse(
                        region.getId(), displayName(region), false))
                .toList();
    }

    @Transactional
    public ClientDetailResponse duplicate(
            UserAccount user,
            Long id,
            ClientDuplicateRequest request) {
        requireEditable(user);
        ClientEntity source = requireAccessible(user, id);
        String document = requiredDuplicateDocument(source);
        Region target = regionRepository.findById(request.regionId())
                .filter(region -> regionRepository.isAccessible(
                        region.getId(), user.getId()))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Selecione uma região de destino permitida."));
        if (clientRepository.findRegionIdsByNormalizedDocument(document)
                .contains(target.getId())) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Já existe um cliente com este CPF/CNPJ na região selecionada.");
        }

        LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
        ClientEntity copy = copyForRegion(source, target, now);
        ClientEntity saved = clientRepository.saveAndFlush(copy);
        eventPublisher.publishEvent(new ClientIndexRequested(saved.getId()));
        return toDetail(saved, user);
    }

    private void validateRequiredCreateFields(ClientRequest request) {
        if (nullableDigits(request.phone()) == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Informe o Telefone/WhatsApp do cliente.");
        }
        if (request.postalCode() == null || request.postalCode() <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o CEP do cliente.");
        }
        if (request.cityId() == null || request.cityId() <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe a cidade do cliente.");
        }
        if (clean(request.neighborhood()).isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o bairro do cliente.");
        }
        if (clean(request.address()).isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o endereço do cliente.");
        }
        if (clean(request.number()).isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o número do endereço.");
        }
        if (clean(request.complement()).isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o complemento do endereço.");
        }
    }

    @Transactional
    public void deactivate(UserAccount user, Long id) {
        setEnabled(user, id, false);
    }

    @Transactional
    public ClientDetailResponse setEnabled(UserAccount user, Long id, boolean enabled) {
        requireEditable(user);
        ClientEntity client = requireAccessible(user, id);
        client.setEnabled(enabled);
        client.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
        ClientEntity saved = clientRepository.saveAndFlush(client);
        eventPublisher.publishEvent(new ClientIndexRequested(saved.getId()));
        return toDetail(saved, user);
    }

    @Transactional(readOnly = true)
    public List<CityOptionResponse> cities(String rawQuery, Long ibgeCode) {
        if (ibgeCode != null) {
            return cityRepository.findFirstByCodibge(ibgeCode)
                    .map(city -> List.of(toCity(city)))
                    .orElseGet(List::of);
        }
        String query = clean(rawQuery).toLowerCase(Locale.ROOT);
        return cityRepository.search(query, PageRequest.of(0, 40)).stream()
                .map(this::toCity)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<ClientContactResponse> contacts(UserAccount user, Long clientId) {
        requireAccessible(user, clientId);
        return contactRepository.findAllByClientIdOrderByNameAscIdAsc(clientId)
                .stream().map(this::toContact).toList();
    }

    @Transactional
    public ClientContactResponse saveContact(
            UserAccount user,
            Long clientId,
            Long contactId,
            ClientContactRequest request) {
        requireEditable(user);
        requireAccessible(user, clientId);
        LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
        ClientContactEntity contact = contactId == null
                ? new ClientContactEntity()
                : contactRepository.findByIdAndClientId(contactId, clientId)
                        .orElseThrow(() -> new ApiException(
                                HttpStatus.NOT_FOUND, "Contato não encontrado."));
        if (contactId == null) {
            contact.setClientId(clientId);
            contact.setCreatedAt(now);
        }
        contact.setName(clean(request.name()));
        contact.setPhone(nullable(request.phone()));
        contact.setType(nullable(request.type()));
        contact.setNotes(nullable(request.notes()));
        contact.setUpdatedAt(now);
        return toContact(contactRepository.saveAndFlush(contact));
    }

    @Transactional
    public void deleteContact(UserAccount user, Long clientId, Long contactId) {
        requireEditable(user);
        requireAccessible(user, clientId);
        ClientContactEntity contact = contactRepository.findByIdAndClientId(contactId, clientId)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND, "Contato não encontrado."));
        contactRepository.delete(contact);
        contactRepository.flush();
    }

    @Transactional(readOnly = true)
    public List<ClientDocumentResponse> documents(UserAccount user, Long clientId) {
        requireAccessible(user, clientId);
        return documentRepository.findAllByClientIdOrderByCreatedAtDescIdDesc(clientId)
                .stream().map(this::toDocument).toList();
    }

    @Transactional
    public ClientDocumentResponse uploadDocument(
            UserAccount user,
            Long clientId,
            MultipartFile file,
            String description) {
        requireEditable(user);
        requireAccessible(user, clientId);
        if (file == null || file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Selecione um arquivo.");
        }
        if (file.getSize() > MAX_DOCUMENT_BYTES) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "O arquivo deve ter no máximo 15 MB.");
        }

        byte[] fileBytes;
        try {
            fileBytes = file.getBytes();
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Não foi possível ler o arquivo enviado.");
        }
        ClientDocumentTypeResolver.ResolvedFile resolved = ClientDocumentTypeResolver.resolve(
                file.getOriginalFilename(), file.getContentType(), fileBytes);

        String storedName = UUID.randomUUID() + "_" + clientId;
        Path target = safeResolve(documentStorage, storedName);
        try {
            Files.createDirectories(documentStorage);
            Files.write(target, fileBytes);
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Não foi possível armazenar o arquivo.");
        }

        LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
        ClientDocumentEntity document = new ClientDocumentEntity();
        document.setClientId(clientId);
        document.setDescription(nullable(description));
        document.setFileName(resolved.fileName());
        document.setContentType(resolved.contentType());
        document.setDiskFile(storedName);
        document.setCreatedAt(now);
        document.setUpdatedAt(now);
        try {
            return toDocument(documentRepository.saveAndFlush(document));
        } catch (RuntimeException exception) {
            try { Files.deleteIfExists(target); } catch (IOException ignored) { }
            throw exception;
        }
    }

    @Transactional(readOnly = true)
    public ClientDocumentFile downloadDocument(
            UserAccount user,
            Long clientId,
            Long documentId) {
        requireAccessible(user, clientId);
        ClientDocumentEntity document = requireDocument(clientId, documentId);
        Path path = documentPath(document);
        if (path == null) {
            throw new ApiException(
                    HttpStatus.NOT_FOUND,
                    "O arquivo deste documento não está disponível na cópia atual.");
        }
        try {
            byte[] data = Files.readAllBytes(path);
            ClientDocumentTypeResolver.ResolvedFile resolved = ClientDocumentTypeResolver.resolve(
                    document.getFileName(), document.getContentType(), data);
            return new ClientDocumentFile(
                    data,
                    resolved.fileName(),
                    resolved.contentType());
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Não foi possível ler o arquivo.");
        }
    }

    @Transactional
    public ClientDocumentResponse updateDocument(
            UserAccount user,
            Long clientId,
            Long documentId,
            ClientDocumentUpdateRequest request) {
        requireEditable(user);
        requireAccessible(user, clientId);
        ClientDocumentEntity document = requireDocument(clientId, documentId);
        document.setDescription(nullable(request.description()));
        document.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
        return toDocument(documentRepository.saveAndFlush(document));
    }

    @Transactional
    public void deleteDocument(UserAccount user, Long clientId, Long documentId) {
        requireEditable(user);
        requireAccessible(user, clientId);
        ClientDocumentEntity document = requireDocument(clientId, documentId);
        Path newFile = existingPath(documentStorage, document.getDiskFile());
        documentRepository.delete(document);
        documentRepository.flush();
        if (newFile != null) {
            try { Files.deleteIfExists(newFile); } catch (IOException ignored) { }
        }
    }

    private void apply(ClientEntity client, ClientRequest request, UserAccount user) {
        Region region = regionRepository.findById(request.regionId())
                .filter(item -> regionRepository.isAccessible(item.getId(), user.getId()))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.BAD_REQUEST, "Selecione uma região permitida."));
        if (request.cityId() != null && !cityRepository.existsById(request.cityId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A cidade informada não existe.");
        }

        client.setName(clean(request.name()));
        client.setLegalName(nullable(request.legalName()));
        client.setDocument(nullableDigits(request.document()));
        client.setEmail(nullable(request.email()));
        client.setType(personTypeStorageValue(request.type(), request.document()));
        client.setStateRegistration(nullable(request.stateRegistration()));
        client.setBirthDate(request.birthDate() == null
                ? null : request.birthDate().atStartOfDay());
        client.setPhone(nullableDigits(request.phone()));
        client.setSecondaryPhone(nullableDigits(request.secondaryPhone()));
        client.setHomepage(nullable(request.homepage()));
        client.setPostalCode(request.postalCode() == null ? 0 : request.postalCode());
        client.setCityId(request.cityId());
        client.setAddress(nullable(request.address()));
        client.setNumber(nullable(request.number()));
        client.setComplement(nullable(request.complement()));
        client.setNeighborhood(nullable(request.neighborhood()));
        client.setCollector(nullable(request.collector()));
        client.setGoogleMapsLink(nullable(request.googleMapsLink()));
        client.setLatitude(request.latitude());
        client.setLongitude(request.longitude());
        client.setBusinessLatitude(request.businessLatitude());
        client.setBusinessLongitude(request.businessLongitude());
        client.setRegion(region);
        client.setNotes(nullable(request.notes()));
        client.setBusiness(nullable(request.business()));
        client.setFacebook(nullable(request.facebook()));
        client.setInstagram(nullable(request.instagram()));
    }

    private ClientEntity copyForRegion(
            ClientEntity source,
            Region target,
            LocalDateTime now) {
        ClientEntity copy = new ClientEntity();
        copy.setName(source.getName());
        copy.setLegalName(source.getLegalName());
        copy.setDocument(source.getDocument());
        copy.setEmail(source.getEmail());
        copy.setPostalCode(source.getPostalCode());
        copy.setCityId(source.getCityId());
        copy.setAddress(source.getAddress());
        copy.setNumber(source.getNumber());
        copy.setComplement(source.getComplement());
        copy.setCollector(source.getCollector());
        copy.setType(source.getType());
        copy.setBirthDate(source.getBirthDate());
        copy.setMobilePhone(source.getMobilePhone());
        copy.setNeighborhood(source.getNeighborhood());
        copy.setEnabled(true);
        copy.setCreatedAt(now);
        copy.setUpdatedAt(now);
        copy.setStateRegistration(source.getStateRegistration());
        copy.setPhone(source.getPhone());
        copy.setSecondaryPhone(source.getSecondaryPhone());
        copy.setHomepage(source.getHomepage());
        copy.setNotes(source.getNotes());
        copy.setBusiness(source.getBusiness());
        copy.setFacebook(source.getFacebook());
        copy.setInstagram(source.getInstagram());
        copy.setGoogleMapsLink(source.getGoogleMapsLink());
        copy.setLatitude(source.getLatitude());
        copy.setLongitude(source.getLongitude());
        copy.setBusinessLatitude(source.getBusinessLatitude());
        copy.setBusinessLongitude(source.getBusinessLongitude());
        copy.setRegion(target);
        return copy;
    }

    private String requiredDuplicateDocument(ClientEntity source) {
        String document = nullableDigits(source.getDocument());
        if (document == null) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Cadastre o CPF/CNPJ do cliente antes de duplicá-lo.");
        }
        return document;
    }

    private ClientEntity requireAccessible(UserAccount user, Long id) {
        if (!clientRepository.isAccessible(id, user.getId())) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Cliente não encontrado.");
        }
        return clientRepository.findById(id).orElseThrow(() ->
                new ApiException(HttpStatus.NOT_FOUND, "Cliente não encontrado."));
    }

    private ClientDocumentEntity requireDocument(Long clientId, Long documentId) {
        return documentRepository.findByIdAndClientId(documentId, clientId)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND, "Documento não encontrado."));
    }

    private void requireEditable(UserAccount user) {
        if (!user.isAdministrator() && user.isReadOnly()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Seu usuário não possui permissão para alterar clientes.");
        }
    }

    private ClientDetailResponse toDetail(ClientEntity client, UserAccount user) {
        CityEntity city = client.getCityId() == null
                ? null : cityRepository.findById(client.getCityId()).orElse(null);
        Region region = client.getRegion();
        ClientStatus clientStatus = clientQueryRepository.status(client.getId(), user.getId());
        ClientScoreResponse clientScore = clientScoreRepository.profile(client.getId());
        if (clientStatus == ClientStatus.MISSING && clientScore.points() != 0) {
            clientScore = new ClientScoreResponse(
                    0, clientScore.overdueDays(), clientScore.totalDebt());
        }
        return new ClientDetailResponse(
                client.getId(), clean(client.getName()), nullable(client.getLegalName()),
                nullable(client.getDocument()), nullable(client.getEmail()),
                personTypeCode(client.getType(), client.getDocument()),
                nullable(client.getStateRegistration()), client.getBirthDate(), nullable(client.getMobilePhone()),
                nullable(client.getPhone()), nullable(client.getSecondaryPhone()), nullable(client.getHomepage()),
                client.isEnabled(), client.getCreatedAt(), client.getUpdatedAt(), client.getPostalCode(),
                city == null ? null : city.getId(), city == null ? null : clean(city.getName()),
                city == null ? null : nullable(city.getState()), nullable(client.getAddress()),
                nullable(client.getNumber()), nullable(client.getComplement()), nullable(client.getNeighborhood()),
                nullable(client.getCollector()), nullable(client.getGoogleMapsLink()),
                client.getLatitude(), client.getLongitude(),
                client.getBusinessLatitude(), client.getBusinessLongitude(), region.getId(),
                clean(region.getDescription()), nullable(client.getNotes()), nullable(client.getBusiness()),
                nullable(client.getFacebook()), nullable(client.getInstagram()),
                clientStatus, clientScore);
    }

    private CityOptionResponse toCity(CityEntity city) {
        String name = clean(city.getName());
        String state = clean(city.getState());
        return new CityOptionResponse(
                city.getId(), city.getIbgeCode(), name, state,
                state.isEmpty() ? name : name + " - " + state);
    }

    private ClientContactResponse toContact(ClientContactEntity contact) {
        return new ClientContactResponse(
                contact.getId(), contact.getClientId(), clean(contact.getName()),
                nullable(contact.getPhone()), nullable(contact.getType()), nullable(contact.getNotes()),
                contact.getCreatedAt(), contact.getUpdatedAt());
    }

    private ClientDocumentResponse toDocument(ClientDocumentEntity document) {
        ClientDocumentTypeResolver.ResolvedFile resolved = resolveDocumentMetadata(document);
        return new ClientDocumentResponse(
                document.getId(), document.getClientId(), nullable(document.getDescription()),
                resolved.fileName(), resolved.contentType(),
                documentPath(document) != null, document.getCreatedAt(), document.getUpdatedAt());
    }

    private ClientDocumentTypeResolver.ResolvedFile resolveDocumentMetadata(
            ClientDocumentEntity document) {
        Path path = documentPath(document);
        byte[] signature = null;
        if (path != null) {
            try (InputStream input = Files.newInputStream(path)) {
                signature = input.readNBytes(64);
            } catch (IOException ignored) { }
        }
        return ClientDocumentTypeResolver.resolve(
                document.getFileName(), document.getContentType(), signature);
    }

    private Path documentPath(ClientDocumentEntity document) {
        Path current = existingPath(documentStorage, document.getDiskFile());
        return current != null ? current : existingPath(legacyDocumentStorage, document.getDiskFile());
    }

    private Path existingPath(Path root, String name) {
        if (name == null || name.isBlank()) return null;
        Path candidate = safeResolve(root, name);
        return Files.isRegularFile(candidate) ? candidate : null;
    }

    private Path safeResolve(Path root, String name) {
        Path candidate = root.resolve(name).normalize();
        if (!candidate.startsWith(root)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Nome de arquivo inválido.");
        }
        return candidate;
    }

    private String safeFileName(String name) {
        String value = clean(name).replace('\\', '_').replace('/', '_');
        return value.isEmpty() ? "documento" : value;
    }

    private Set<Long> parseRegionIds(String value) {
        Set<Long> result = new HashSet<>();
        if (value == null || value.isBlank()) return result;
        for (String part : value.split(",")) {
            try {
                long id = Long.parseLong(part.trim());
                if (id > 0) result.add(id);
            } catch (NumberFormatException exception) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "Filtro de regiões inválido.");
            }
        }
        return result;
    }

    private String nullableDigits(String value) {
        String digits = clean(value).replaceAll("[^0-9]", "");
        return digits.isEmpty() ? null : digits;
    }

    private String personTypeStorageValue(String value, String document) {
        return "JURIDICA".equals(personTypeCode(value, document)) ? "Juridica" : "Fisica";
    }

    private String personTypeCode(String value, String document) {
        String normalized = clean(value).toUpperCase(Locale.ROOT);
        if (normalized.startsWith("J") || normalized.contains("JURID")) return "JURIDICA";
        if (normalized.startsWith("F") || normalized.contains("FISIC")) return "FISICA";
        String digits = clean(document).replaceAll("[^0-9]", "");
        return digits.length() == 14 ? "JURIDICA" : "FISICA";
    }

    private String nullable(String value) {
        String result = clean(value);
        return result.isEmpty() ? null : result;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private String displayName(Region region) {
        String description = clean(region.getDescription());
        String responsible = clean(region.getResponsiblePeople());
        String base = description.isEmpty()
                ? "Região #" + region.getId()
                : description;
        return responsible.isEmpty() ? base : base + " - " + responsible;
    }
}
