package com.webdigital.money2.integrations;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class IntegrationServiceTest {
    private final IntegrationRepository repository = mock(IntegrationRepository.class);
    private final WebDigitalWhatsappClient whatsapp = mock(WebDigitalWhatsappClient.class);
    private final PixService pix = mock(PixService.class);
    private final IntegrationService service = new IntegrationService(repository, whatsapp,
            mock(SicrediMtlsClientFactory.class), pix, "/tmp/money2-test-certificates");
    private final IntegrationRepository.DispatchTarget target = new IntegrationRepository.DispatchTarget(
            10, "CLIENTE", "65999999999", 700, 30L, "1", LocalDateTime.now().minusDays(2), BigDecimal.TEN);

    @BeforeEach
    void setUp() {
        when(repository.whatsappSecret()).thenReturn(new IntegrationModels.WhatsappSecret(
                true, "token", "https://webdigital.dev/api/v1", null, null, null, null, null, null));
        var device = mock(IntegrationModels.WhatsappDevice.class);
        when(device.remoteId()).thenReturn("device");
        when(repository.requireDevice(1)).thenReturn(device);
        when(repository.isDispatching(1)).thenReturn(true);
        when(pix.prepareCollection(700)).thenReturn(true);
        when(repository.isDispatchTargetEligible(any(), any())).thenReturn(true);
        when(repository.pendingAmount(30)).thenReturn(BigDecimal.TEN);
    }

    @AfterEach
    void shutdown() { service.shutdown(); }

    @Test
    void skipsCollectionWhenPixCannotBeSafelyReconciled() {
        when(pix.prepareCollection(700)).thenReturn(false);

        dispatch("ATRASADAS");

        verifyNoInteractions(whatsapp);
        verify(repository).recordDispatchProgress(1, "AVISO");
    }

    @Test
    void skipsCustomerWhoPaidDuringMessageGeneration() {
        when(repository.isDispatchTargetEligible("VENCE_HOJE", target)).thenReturn(true, false);

        dispatch("VENCE_HOJE");

        verifyNoInteractions(whatsapp);
        verify(repository).recordDispatchProgress(1, "AVISO");
    }

    @Test
    void skipsZeroBalanceForDueTodayCollections() {
        when(repository.pendingAmount(30)).thenReturn(BigDecimal.ZERO);

        dispatch("VENCE_HOJE");

        verifyNoInteractions(whatsapp);
    }

    private void dispatch(String type) {
        ReflectionTestUtils.invokeMethod(service, "executeDispatch", 1L, type, List.of(target));
    }
}
