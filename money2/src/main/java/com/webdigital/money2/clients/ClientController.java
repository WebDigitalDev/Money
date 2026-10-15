package com.webdigital.money2.clients;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.RegionOptionResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v2/clients")
public class ClientController {

    private final ClientManagementService clientService;
    private final CompanyLookupService companyLookupService;

    public ClientController(
            ClientManagementService clientService,
            CompanyLookupService companyLookupService) {
        this.clientService = clientService;
        this.companyLookupService = companyLookupService;
    }

    @GetMapping
    public ResponseEntity<ApiEnvelope<ClientListResponse>> search(
            HttpServletRequest request,
            @RequestParam(defaultValue = "ACTIVE") String status,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(defaultValue = "false") boolean tutorial,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.search(
                currentUser(request), status, query, regionIds, tutorial, page, size)));
    }

    @GetMapping("/export-data")
    public ResponseEntity<ApiEnvelope<ClientListResponse>> exportData(
            HttpServletRequest request,
            @RequestParam(defaultValue = "ALL") String status,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(defaultValue = "false") boolean tutorial) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.export(
                currentUser(request), status, query, regionIds, tutorial)));
    }

    @GetMapping("/cities")
    public ResponseEntity<ApiEnvelope<List<CityOptionResponse>>> cities(
            @RequestParam(defaultValue = "") String query,
            @RequestParam(required = false) Long ibgeCode) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.cities(query, ibgeCode)));
    }

    @GetMapping("/company/{document}")
    public ResponseEntity<ApiEnvelope<CompanyLookupResponse>> company(
            HttpServletRequest request,
            @PathVariable String document) {
        currentUser(request);
        return ResponseEntity.ok(ApiEnvelope.of(companyLookupService.lookup(document)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiEnvelope<ClientDetailResponse>> getById(
            HttpServletRequest request,
            @PathVariable Long id) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.getById(currentUser(request), id)));
    }

    @PostMapping
    public ResponseEntity<ApiEnvelope<ClientDetailResponse>> create(
            HttpServletRequest request,
            @Valid @RequestBody ClientRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                clientService.create(currentUser(request), body)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiEnvelope<ClientDetailResponse>> update(
            HttpServletRequest request,
            @PathVariable Long id,
            @Valid @RequestBody ClientRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(
                clientService.update(currentUser(request), id, body)));
    }

    @GetMapping("/{id}/duplicate-regions")
    public ResponseEntity<ApiEnvelope<List<RegionOptionResponse>>> duplicateRegions(
            HttpServletRequest request,
            @PathVariable Long id) {
        return ResponseEntity.ok(ApiEnvelope.of(
                clientService.duplicateRegions(currentUser(request), id)));
    }

    @PostMapping("/{id}/duplicate")
    public ResponseEntity<ApiEnvelope<ClientDetailResponse>> duplicate(
            HttpServletRequest request,
            @PathVariable Long id,
            @Valid @RequestBody ClientDuplicateRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                clientService.duplicate(currentUser(request), id, body)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deactivate(
            HttpServletRequest request,
            @PathVariable Long id) {
        clientService.deactivate(currentUser(request), id);
        return ResponseEntity.noContent().build();
    }

    @PatchMapping("/{id}/enabled")
    public ResponseEntity<ApiEnvelope<ClientDetailResponse>> setEnabled(
            HttpServletRequest request,
            @PathVariable Long id,
            @Valid @RequestBody ClientEnabledRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.setEnabled(
                currentUser(request), id, body.enabled())));
    }

    @GetMapping("/{clientId}/contacts")
    public ResponseEntity<ApiEnvelope<List<ClientContactResponse>>> contacts(
            HttpServletRequest request,
            @PathVariable Long clientId) {
        return ResponseEntity.ok(ApiEnvelope.of(
                clientService.contacts(currentUser(request), clientId)));
    }

    @PostMapping("/{clientId}/contacts")
    public ResponseEntity<ApiEnvelope<ClientContactResponse>> createContact(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @Valid @RequestBody ClientContactRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                clientService.saveContact(currentUser(request), clientId, null, body)));
    }

    @PutMapping("/{clientId}/contacts/{contactId}")
    public ResponseEntity<ApiEnvelope<ClientContactResponse>> updateContact(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @PathVariable Long contactId,
            @Valid @RequestBody ClientContactRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.saveContact(
                currentUser(request), clientId, contactId, body)));
    }

    @DeleteMapping("/{clientId}/contacts/{contactId}")
    public ResponseEntity<Void> deleteContact(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @PathVariable Long contactId) {
        clientService.deleteContact(currentUser(request), clientId, contactId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{clientId}/documents")
    public ResponseEntity<ApiEnvelope<List<ClientDocumentResponse>>> documents(
            HttpServletRequest request,
            @PathVariable Long clientId) {
        return ResponseEntity.ok(ApiEnvelope.of(
                clientService.documents(currentUser(request), clientId)));
    }

    @PostMapping(value = "/{clientId}/documents", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<ApiEnvelope<ClientDocumentResponse>> uploadDocument(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @RequestPart("file") MultipartFile file,
            @RequestPart(value = "description", required = false) String description) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                clientService.uploadDocument(
                        currentUser(request), clientId, file, description)));
    }

    @GetMapping("/{clientId}/documents/{documentId}/file")
    public ResponseEntity<byte[]> downloadDocument(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @PathVariable Long documentId) {
        ClientDocumentFile file = clientService.downloadDocument(
                currentUser(request), clientId, documentId);
        MediaType contentType;
        try {
            contentType = file.contentType() == null
                    ? MediaType.APPLICATION_OCTET_STREAM
                    : MediaType.parseMediaType(file.contentType());
        } catch (IllegalArgumentException exception) {
            contentType = MediaType.APPLICATION_OCTET_STREAM;
        }
        return ResponseEntity.ok()
                .contentType(contentType)
                .header(
                        HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment()
                                .filename(file.fileName(), StandardCharsets.UTF_8)
                                .build().toString())
                .body(file.data());
    }

    @PatchMapping("/{clientId}/documents/{documentId}")
    public ResponseEntity<ApiEnvelope<ClientDocumentResponse>> updateDocument(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @PathVariable Long documentId,
            @RequestBody ClientDocumentUpdateRequest body) {
        return ResponseEntity.ok(ApiEnvelope.of(clientService.updateDocument(
                currentUser(request), clientId, documentId, body)));
    }

    @DeleteMapping("/{clientId}/documents/{documentId}")
    public ResponseEntity<Void> deleteDocument(
            HttpServletRequest request,
            @PathVariable Long clientId,
            @PathVariable Long documentId) {
        clientService.deleteDocument(currentUser(request), clientId, documentId);
        return ResponseEntity.noContent().build();
    }

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
