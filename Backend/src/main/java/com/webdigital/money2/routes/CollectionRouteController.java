package com.webdigital.money2.routes;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.clients.CityOptionResponse;
import com.webdigital.money2.shared.ApiEnvelope;
import com.webdigital.money2.shared.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class CollectionRouteController {

    private final CollectionRouteService routeService;

    public CollectionRouteController(CollectionRouteService routeService) {
        this.routeService = routeService;
    }

    @GetMapping("/api/v2/routes")
    public ResponseEntity<ApiEnvelope<CollectionRoutePageResponse>> search(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(required = false) Long collectorId,
            @RequestParam(required = false) Long cityId,
            @RequestParam(defaultValue = "") String city,
            @RequestParam(defaultValue = "OVERDUE_DAYS") String sort,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return ResponseEntity.ok(ApiEnvelope.of(routeService.search(
                currentUser(request), regionIds, collectorId, cityId, city, sort, query, page, size)));
    }

    @GetMapping("/api/v2/routes/candidates")
    public ResponseEntity<ApiEnvelope<CollectionRoutePageResponse>> candidates(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(required = false) Long cityId,
            @RequestParam(defaultValue = "") String city,
            @RequestParam(defaultValue = "OVERDUE_DAYS") String sort,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return ResponseEntity.ok(ApiEnvelope.of(routeService.candidates(
                currentUser(request), regionIds, cityId, city, sort, query, page, size)));
    }

    @GetMapping("/api/v2/routes/collectors")
    public ResponseEntity<ApiEnvelope<List<CollectionRouteCollectorResponse>>> collectors(
            HttpServletRequest request) {
        return ResponseEntity.ok(ApiEnvelope.of(
                routeService.collectors(currentUser(request))));
    }

    @GetMapping("/api/v2/routes/assigned-collectors")
    public ResponseEntity<ApiEnvelope<List<CollectionRouteCollectorResponse>>> assignedCollectors(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(required = false) Long cityId,
            @RequestParam(defaultValue = "") String query) {
        return ResponseEntity.ok(ApiEnvelope.of(routeService.assignedCollectors(
                currentUser(request), regionIds, cityId, query)));
    }

    @GetMapping("/api/v2/routes/cities")
    public ResponseEntity<ApiEnvelope<List<CityOptionResponse>>> cities(
            HttpServletRequest request,
            @RequestParam(defaultValue = "") String regionIds,
            @RequestParam(required = false) Long collectorId,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "true") boolean assignedOnly) {
        return ResponseEntity.ok(ApiEnvelope.of(routeService.cities(
                currentUser(request), regionIds, collectorId, query, assignedOnly)));
    }

    @PostMapping("/api/v2/routes/assignments")
    public ResponseEntity<ApiEnvelope<CollectionRouteAssignmentResponse>> assign(
            HttpServletRequest request,
            @Valid @RequestBody CollectionRouteAssignmentRequest body) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                routeService.assign(currentUser(request), body)));
    }

    @DeleteMapping("/api/v2/routes/{clientId}/assignment")
    public ResponseEntity<ApiEnvelope<Boolean>> removeAssignment(
            HttpServletRequest request,
            @PathVariable long clientId) {
        routeService.removeAssignment(currentUser(request), clientId);
        return ResponseEntity.ok(ApiEnvelope.of(true));
    }

    @GetMapping("/api/v2/routes/{clientId}")
    public ResponseEntity<ApiEnvelope<CollectionRouteDetailResponse>> detail(
            HttpServletRequest request,
            @PathVariable long clientId) {
        return ResponseEntity.ok(ApiEnvelope.of(
                routeService.detail(currentUser(request), clientId)));
    }

    @PostMapping(
            value = "/api/v2/routes/{clientId}/collections",
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<ApiEnvelope<CollectionHistoryResponse>> register(
            HttpServletRequest request,
            @PathVariable long clientId,
            @RequestPart(value = "observation", required = false) String observation,
            @RequestPart(value = "file", required = false) MultipartFile file) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiEnvelope.of(
                routeService.register(
                        currentUser(request), clientId, observation, file)));
    }

    @GetMapping("/api/v2/clients/{clientId}/collections")
    public ResponseEntity<ApiEnvelope<List<CollectionHistoryResponse>>> clientHistory(
            HttpServletRequest request,
            @PathVariable long clientId) {
        return ResponseEntity.ok(ApiEnvelope.of(
                routeService.clientHistory(currentUser(request), clientId)));
    }

    @GetMapping("/api/v2/collections/{collectionId}/file")
    public ResponseEntity<byte[]> downloadAttachment(
            HttpServletRequest request,
            @PathVariable long collectionId) {
        CollectionAttachmentFile file = routeService.downloadAttachment(
                currentUser(request), collectionId);
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

    private UserAccount currentUser(HttpServletRequest request) {
        Object authenticated = request.getAttribute(
                AuthenticationInterceptor.USER_ATTRIBUTE);
        if (authenticated instanceof UserAccount user) return user;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
    }
}
