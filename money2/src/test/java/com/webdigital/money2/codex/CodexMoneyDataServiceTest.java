package com.webdigital.money2.codex;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.chat.ChatClientResponse;
import com.webdigital.money2.chat.ChatRepository;
import com.webdigital.money2.chat.ChatRegionOption;
import com.webdigital.money2.chat.ChatService;
import com.webdigital.money2.chat.FinancialSemanticContext;
import com.webdigital.money2.chat.QdrantFinancialService;
import com.webdigital.money2.chat.QdrantService;
import com.webdigital.money2.loans.LoanDetailService;
import com.webdigital.money2.regions.RegionListResponse;
import com.webdigital.money2.regions.RegionManagementService;
import com.webdigital.money2.regions.RegionSummaryResponse;
import com.webdigital.money2.regions.RegionTotalsResponse;
import com.webdigital.money2.routes.CollectionRouteService;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class CodexMoneyDataServiceTest {

    private final ObjectMapper mapper = new ObjectMapper();
    private final ChatRepository chatRepository = mock(ChatRepository.class);
    private final CodexMoneyRepository codexRepository = mock(CodexMoneyRepository.class);
    private final QdrantService clientQdrant = mock(QdrantService.class);
    private final QdrantFinancialService financialQdrant = mock(QdrantFinancialService.class);
    private final LoanDetailService loanDetailService = mock(LoanDetailService.class);
    private final ChatService chatService = mock(ChatService.class);
    private final CollectionRouteService routeService = mock(CollectionRouteService.class);
    private final RegionManagementService regionService = mock(RegionManagementService.class);
    private final UserAccount user = mock(UserAccount.class);
    private CodexMoneyDataService service;

    @BeforeEach
    void setUp() {
        when(user.getId()).thenReturn(42L);
        service = new CodexMoneyDataService(
                chatRepository,
                codexRepository,
                clientQdrant,
                financialQdrant,
                loanDetailService,
                chatService,
                routeService,
                regionService);
    }

    @Test
    void contextUsesQdrantToDiscoverCandidatesWithoutCreatingActions() throws Exception {
        when(chatRepository.accessibleRegionIds(42L)).thenReturn(List.of(7L, 9L));
        when(financialQdrant.context("compare a inadimplência", List.of(7L, 9L), 20))
                .thenReturn(new FinancialSemanticContext(
                        List.of(48132L), List.of("REGION_COMPARISON"), true));
        when(clientQdrant.search("compare a inadimplência", List.of(7L, 9L), 20))
                .thenReturn(List.of(91L));
        when(chatRepository.clientsByIds(42L, List.of(91L), 20))
                .thenReturn(List.of(mock(ChatClientResponse.class)));
        when(chatRepository.accessibleRegions(42L)).thenReturn(List.of());

        CodexMoneyToolResult result = service.query(
                user,
                mapper.readTree("""
                        {"fonte":"CONTEXTO","pergunta":"compare a inadimplência"}
                        """));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) result.data();
        assertEquals(List.of(48132L), data.get("contratosCandidatos"));
        assertEquals(List.of("REGION_COMPARISON"), data.get("intencoesProvaveis"));
        assertTrue((Boolean) data.get("qdrantUsado"));
        assertNull(result.presentation());
    }

    @Test
    void regionSourceListsAccessibleRegionsWithoutCalculatingFinancialIndicators() throws Exception {
        when(chatRepository.accessibleRegions(42L)).thenReturn(List.of(
                new ChatRegionOption(7L, "CASH"),
                new ChatRegionOption(9L, "ALPHACRED")));

        CodexMoneyToolResult result = service.query(
                user, mapper.readTree("{\"fonte\":\"REGIOES\"}"));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) result.data();
        assertEquals(2, data.get("quantidade"));
        assertNull(result.presentation());
        verifyNoInteractions(codexRepository);
    }

    @Test
    void financialRegionSummaryUsesTheSameSourceAsTheRegionsPage() throws Exception {
        RegionSummaryResponse region = new RegionSummaryResponse(
                7L,
                "CASH",
                "Daniel",
                13,
                1,
                10,
                2,
                BigDecimal.valueOf(80),
                BigDecimal.valueOf(800),
                BigDecimal.valueOf(30),
                BigDecimal.valueOf(400),
                BigDecimal.valueOf(10),
                BigDecimal.valueOf(200),
                BigDecimal.valueOf(1000));
        RegionTotalsResponse totals = new RegionTotalsResponse(
                1, 13, 1, 10, 2,
                BigDecimal.valueOf(80), BigDecimal.valueOf(800),
                BigDecimal.valueOf(30), BigDecimal.valueOf(400),
                BigDecimal.valueOf(10), BigDecimal.valueOf(200),
                BigDecimal.valueOf(1000));
        when(regionService.searchForAssistant(user, null, null, null, null))
                .thenReturn(new RegionListResponse(List.of(region), totals, null, null));
        when(chatRepository.activeFinancialGoals(42L, 7L)).thenReturn(List.of());

        CodexMoneyToolResult result = service.query(
                user, mapper.readTree("{\"fonte\":\"RESUMO_REGIOES\"}"));

        verify(regionService).searchForAssistant(user, null, null, null, null);
        assertEquals("RESUMO_REGIOES", ((Map<?, ?>) result.data()).get("fonte"));
        assertEquals(13, result.presentation().summary().openLoans());
    }

    @Test
    void rejectsARegionOutsideTheUsersAccess() throws Exception {
        when(chatRepository.accessibleRegionIds(42L)).thenReturn(List.of(7L));

        ApiException exception = assertThrows(
                ApiException.class,
                () -> service.query(
                        user,
                        mapper.readTree("{\"fonte\":\"REGIOES\",\"regiaoIds\":[9]}")));

        assertFalse(exception.getMessage().isBlank());
    }
}
