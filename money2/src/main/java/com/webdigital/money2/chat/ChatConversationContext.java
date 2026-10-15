package com.webdigital.money2.chat;

record ChatConversationContext(
        Long clientId,
        Long loanId,
        Long regionId,
        String lastIntent) {

    static ChatConversationContext empty() {
        return new ChatConversationContext(null, null, null, null);
    }
}
