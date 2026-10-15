package com.webdigital.money2.codex;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.chat.ChatRequest;
import com.webdigital.money2.chat.ChatResponse;
import com.webdigital.money2.chat.ChatSuggestionResponse;
import com.webdigital.money2.shared.ApiException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.http.HttpStatus;

class CodexAppServerServiceTest {

    @TempDir
    Path temporaryDirectory;

    private CodexAppServerService service;

    @AfterEach
    void closeService() {
        if (service != null) service.close();
    }

    @Test
    void reportsDisabledWithoutStartingAProcess() {
        service = new CodexAppServerService(
                mock(CodexMoneyDataService.class),
                new ObjectMapper(),
                false,
                temporaryDirectory.resolve("missing-codex").toString(),
                temporaryDirectory.resolve("data").toString(),
                30,
                2,
                5);
        UserAccount user = user(7L);

        CodexConnectionResponse response = service.status(user);

        assertFalse(response.enabled());
        assertFalse(response.available());
        assertFalse(response.connected());
    }

    @Test
    void executesTheFinancialToolAndKeepsStructuredCards() throws Exception {
        Path executable = fakeCodexExecutable();
        CodexMoneyDataService moneyData = mock(CodexMoneyDataService.class);
        ChatResponse structured = new ChatResponse(
                "Dados consultados.",
                "READY",
                List.of(new ChatSuggestionResponse("Não exibir", "legado", null)),
                List.of(),
                null,
                false);
        UserAccount user = user(42L);
        ChatRequest request = new ChatRequest(
                "Quanto venceu hoje?", "READY", null, 9L, "conversation-1");
        when(moneyData.query(any(UserAccount.class), any(JsonNode.class)))
                .thenReturn(new CodexMoneyToolResult(
                        Map.of("fonte", "CONTEXTO"), structured));
        service = new CodexAppServerService(
                moneyData,
                new ObjectMapper(),
                true,
                executable.toString(),
                temporaryDirectory.resolve("data").toString(),
                30,
                2,
                5);

        CodexConnectionResponse connection = service.status(user);
        ChatResponse response = service.answer(user, request);

        assertTrue(connection.enabled());
        assertTrue(connection.available());
        assertTrue(connection.connected());
        assertEquals(63.5, connection.usage().usedPercent());
        assertEquals("Análise pronta com os dados do Money.", response.message());
        assertEquals(structured.mode(), response.mode());
        assertTrue(response.suggestions().isEmpty());
    }

    @Test
    void interruptsTheActiveConversationTurn() throws Exception {
        service = new CodexAppServerService(
                mock(CodexMoneyDataService.class),
                new ObjectMapper(),
                true,
                fakeInterruptibleCodexExecutable().toString(),
                temporaryDirectory.resolve("interrupt-data").toString(),
                30,
                2,
                5);
        UserAccount user = user(43L);
        ChatRequest request = new ChatRequest(
                "Faça uma análise", "READY", null, null, "conversation-stop");
        ExecutorService executor = Executors.newSingleThreadExecutor();
        try {
            Future<ApiException> answer = executor.submit(() -> assertThrows(
                    ApiException.class,
                    () -> service.answer(user, request)));
            boolean accepted = false;
            for (int attempt = 0; attempt < 100 && !accepted; attempt++) {
                accepted = service.interrupt(user, "conversation-stop");
                if (!accepted) Thread.sleep(20);
            }

            assertTrue(accepted);
            assertEquals(HttpStatus.REQUEST_TIMEOUT, answer.get(5, TimeUnit.SECONDS).getStatus());
        } finally {
            executor.shutdownNow();
        }
    }

    private Path fakeCodexExecutable() throws Exception {
        Path executable = temporaryDirectory.resolve("fake-codex.sh");
        Files.writeString(executable, """
                #!/bin/sh
                awaiting_tool=false
                while IFS= read -r line; do
                  id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p')
                  case "$line" in
                    *'"method":"initialize"'*)
                      printf '{"id":%s,"result":{"userAgent":"fake"}}\\n' "$id"
                      ;;
                    *'"method":"account/read"'*)
                      printf '{"id":%s,"result":{"account":{"type":"chatgpt","email":"tester@example.com","planType":"plus"}}}\\n' "$id"
                      ;;
                    *'"method":"account/rateLimits/read"'*)
                      printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":21,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":63.5,"windowDurationMins":10080,"resetsAt":1800500000}}}}\\n' "$id"
                      ;;
                    *'"method":"model/list"'*)
                      printf '{"id":%s,"result":{"data":[{"id":"gpt-test","displayName":"GPT Test","isDefault":true,"inputModalities":["text","image"],"defaultServiceTier":"default","serviceTiers":[{"id":"default","name":"Padrão","description":"Velocidade padrão"},{"id":"fast","name":"Fast","description":"Resposta mais rápida"}]}]}}\\n' "$id"
                      ;;
                    *'"method":"thread/start"'*)
                      printf '{"id":%s,"result":{"thread":{"id":"thread-1"}}}\\n' "$id"
                      ;;
                    *'"method":"turn/start"'*)
                      printf '{"id":%s,"result":{"turn":{"id":"turn-1"}}}\\n' "$id"
                      printf '{"id":"tool-1","method":"item/tool/call","params":{"threadId":"thread-1","turnId":"turn-1","callId":"call-1","tool":"consultar_dados_money","arguments":{"fonte":"CONTEXTO","pergunta":"Quanto venceu hoje?"}}}\\n'
                      awaiting_tool=true
                      ;;
                    *'"id":"tool-1"'*'"result"'*)
                      if [ "$awaiting_tool" = true ]; then
                        printf '{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"type":"agentMessage","id":"message-1","text":"Análise pronta com os dados do Money."}}}\\n'
                        printf '{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed","items":[],"error":null}}}\\n'
                        awaiting_tool=false
                      fi
                      ;;
                  esac
                done
                """);
        Files.setPosixFilePermissions(
                executable, PosixFilePermissions.fromString("rwx------"));
        return executable;
    }

    private Path fakeInterruptibleCodexExecutable() throws Exception {
        Path executable = temporaryDirectory.resolve("fake-interruptible-codex.sh");
        Files.writeString(executable, """
                #!/bin/sh
                while IFS= read -r line; do
                  id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p')
                  case "$line" in
                    *'"method":"initialize"'*)
                      printf '{"id":%s,"result":{"userAgent":"fake"}}\\n' "$id"
                      ;;
                    *'"method":"account/read"'*)
                      printf '{"id":%s,"result":{"account":{"type":"chatgpt","email":"tester@example.com","planType":"plus"}}}\\n' "$id"
                      ;;
                    *'"method":"model/list"'*)
                      printf '{"id":%s,"result":{"data":[{"id":"gpt-test","displayName":"GPT Test","isDefault":true,"inputModalities":["text","image"],"serviceTiers":[{"id":"fast","name":"Fast","description":"Resposta mais rápida"}]}]}}\\n' "$id"
                      ;;
                    *'"method":"thread/start"'*)
                      printf '{"id":%s,"result":{"thread":{"id":"thread-stop"}}}\\n' "$id"
                      ;;
                    *'"method":"turn/start"'*)
                      printf '{"id":%s,"result":{"turn":{"id":"turn-stop"}}}\\n' "$id"
                      ;;
                    *'"method":"turn/interrupt"'*)
                      printf '{"id":%s,"result":{}}\\n' "$id"
                      printf '{"method":"turn/completed","params":{"threadId":"thread-stop","turn":{"id":"turn-stop","status":"interrupted","items":[],"error":null}}}\\n'
                      ;;
                  esac
                done
                """);
        Files.setPosixFilePermissions(
                executable, PosixFilePermissions.fromString("rwx------"));
        return executable;
    }

    private UserAccount user(long id) {
        UserAccount user = mock(UserAccount.class);
        when(user.getId()).thenReturn(id);
        return user;
    }
}
