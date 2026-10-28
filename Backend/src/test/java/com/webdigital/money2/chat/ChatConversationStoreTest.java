package com.webdigital.money2.chat;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ChatConversationStoreTest {

    @Test
    void preservesContextInsideTheSameAuthenticatedConversation() {
        ChatConversationStore store = new ChatConversationStore();

        store.selectClient(7L, "conversation-a", 91L);
        store.selectRegion(7L, "conversation-a", 12L, "SUMMARY_REGION");
        store.rememberIntent(7L, "conversation-a", "LAST_PAYMENT");

        ChatConversationContext context = store.get(7L, "conversation-a");
        assertThat(context.clientId()).isEqualTo(91L);
        assertThat(context.regionId()).isEqualTo(12L);
        assertThat(context.lastIntent()).isEqualTo("LAST_PAYMENT");
    }

    @Test
    void isolatesContextBetweenUsersAndConversations() {
        ChatConversationStore store = new ChatConversationStore();
        store.selectClient(7L, "conversation-a", 91L);

        assertThat(store.get(8L, "conversation-a").clientId()).isNull();
        assertThat(store.get(7L, "conversation-b").clientId()).isNull();
        assertThat(store.get(7L, null).clientId()).isNull();
    }
}
