package com.webdigital.money2.chat;

import com.webdigital.money2.goals.FinancialGoalResponse;
import java.util.List;

public record ChatResponse(
        String message,
        String mode,
        List<ChatSuggestionResponse> suggestions,
        List<ChatClientResponse> clients,
        ChatFinancialSummaryResponse summary,
        boolean semanticSearch,
        List<ChatLoanResponse> loans,
        ChatLoanStatusResponse loanStatus,
        ChatClientStatusResponse clientStatus,
        FinancialGoalResponse financialGoal,
        List<FinancialGoalResponse> financialGoals,
        ChatSummaryContextResponse summaryContext,
        ChatContractResponse contract) {

    public ChatResponse {
        suggestions = suggestions == null ? List.of() : List.copyOf(suggestions);
        clients = clients == null ? List.of() : List.copyOf(clients);
        loans = loans == null ? List.of() : List.copyOf(loans);
        financialGoals = financialGoals == null ? List.of() : List.copyOf(financialGoals);
        if (financialGoal == null && !financialGoals.isEmpty()) {
            financialGoal = financialGoals.get(0);
        }
    }

    public ChatResponse(
            String message,
            String mode,
            List<ChatSuggestionResponse> suggestions,
            List<ChatClientResponse> clients,
            ChatFinancialSummaryResponse summary,
            boolean semanticSearch) {
        this(message, mode, suggestions, clients, summary, semanticSearch,
                List.of(), null, null, null, List.of(), null, null);
    }

    public ChatResponse(
            String message,
            String mode,
            List<ChatSuggestionResponse> suggestions,
            List<ChatClientResponse> clients,
            ChatFinancialSummaryResponse summary,
            boolean semanticSearch,
            List<ChatLoanResponse> loans,
            ChatLoanStatusResponse loanStatus,
            ChatClientStatusResponse clientStatus,
            FinancialGoalResponse financialGoal,
            List<FinancialGoalResponse> financialGoals,
            ChatSummaryContextResponse summaryContext) {
        this(message, mode, suggestions, clients, summary, semanticSearch,
                loans, loanStatus, clientStatus, financialGoal, financialGoals,
                summaryContext, null);
    }
}
