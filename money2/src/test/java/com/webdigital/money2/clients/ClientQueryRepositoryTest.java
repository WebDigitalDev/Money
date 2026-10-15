package com.webdigital.money2.clients;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.reflect.Field;
import org.junit.jupiter.api.Test;

class ClientQueryRepositoryTest {

    @Test
    void clientListingDoesNotExcludeDisabledClients() throws Exception {
        Field field = ClientQueryRepository.class.getDeclaredField("BASE_CTE");
        field.setAccessible(true);

        String query = (String) field.get(null);

        assertThat(query)
                .contains("FROM cliente c")
                .doesNotContain("c.ativo = true");
    }
}
