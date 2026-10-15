package com.webdigital.money2.clients;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.TutorialRegionAccessService;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.chat.ClientIndexRequested;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;

class ClientManagementServiceEnabledTest {

    @Test
    void reactivatesAccessibleClientAndReturnsUpdatedState() {
        ClientRepository clients = mock(ClientRepository.class);
        ClientQueryRepository queries = mock(ClientQueryRepository.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);
        ClientEntity client = mock(ClientEntity.class);
        Region region = mock(Region.class);
        UserAccount user = mock(UserAccount.class);
        AtomicBoolean enabled = new AtomicBoolean(false);

        when(user.getId()).thenReturn(9L);
        when(clients.isAccessible(6307L, 9L)).thenReturn(true);
        when(clients.findById(6307L)).thenReturn(Optional.of(client));
        when(clients.saveAndFlush(client)).thenReturn(client);
        when(client.getId()).thenReturn(6307L);
        when(client.getRegion()).thenReturn(region);
        when(client.isEnabled()).thenAnswer(ignored -> enabled.get());
        doAnswer(invocation -> {
            enabled.set(invocation.getArgument(0));
            return null;
        }).when(client).setEnabled(anyBoolean());
        when(region.getId()).thenReturn(33L);
        when(region.getDescription()).thenReturn("ALPHACRED");
        when(queries.status(6307L, 9L)).thenReturn(ClientStatus.INACTIVE);

        ClientManagementService service = new ClientManagementService(
                clients,
                queries,
                mock(ClientScoreRepository.class),
                mock(TutorialRegionAccessService.class),
                mock(CityRepository.class),
                mock(RegionRepository.class),
                mock(ClientContactRepository.class),
                mock(ClientDocumentRepository.class),
                events,
                "target/test-documents",
                "target/test-legacy-documents");

        ClientDetailResponse response = service.setEnabled(user, 6307L, true);

        assertThat(response.enabled()).isTrue();
        verify(client).setEnabled(true);
        verify(events).publishEvent(new ClientIndexRequested(6307L));
    }
}
