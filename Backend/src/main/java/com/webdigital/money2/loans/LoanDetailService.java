package com.webdigital.money2.loans;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanDetailRepository.ApprovalSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.ContractMessageSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.InstallmentSeed;
import com.webdigital.money2.loans.LoanDetailRepository.InstallmentMessageSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.InstallmentSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.LoanSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.PaymentSnapshot;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.NumberFormat;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.time.temporal.WeekFields;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LoanDetailService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final String SYSTEM_APPROVER = "APROVADO PELO SISTEMA";
    private static final int MAX_INSTALLMENTS = 240;
    private static final Set<String> TYPES = Set.of("D", "S", "Q", "M", "Z", "A", "B", "C");
    private static final NumberFormat CURRENCY = NumberFormat.getCurrencyInstance(new Locale("pt", "BR"));
    private static final DateTimeFormatter SHORT_DATE = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final DateTimeFormatter SHORT_WEEKDAY =
            DateTimeFormatter.ofPattern("EEE", new Locale("pt", "BR"));
    private final LoanDetailRepository repository;
    private final LoanFeedbackRepository feedbackRepository;

    public LoanDetailService(
            LoanDetailRepository repository,
            LoanFeedbackRepository feedbackRepository) {
        this.repository = repository;
        this.feedbackRepository = feedbackRepository;
    }

    @Transactional(readOnly = true)
    public LoanDetailResponse get(UserAccount user, long loanId) {
        return get(user, loanId, false);
    }

    @Transactional(readOnly = true)
    public LoanDetailResponse get(UserAccount user, long loanId, boolean compact) {
        LoanSnapshot loan = repository.requireSnapshot(user.getId(), loanId);
        return response(user, loan, !compact);
    }

    @Transactional
    public LoanDetailResponse create(UserAccount user, LoanCreateRequest request) {
        requireEditable(user);
        if (request == null || request.clientId() == null || request.clientId() <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Selecione o cliente do empréstimo.");
        }
        repository.requireAccessibleClient(user.getId(), request.clientId());
        LocalDate contractDate = required(request.contractDate(), "Informe a data do contrato.");
        LocalDate firstDueDate = required(request.firstDueDate(), "Informe o primeiro vencimento.");
        int installments = request.installmentCount() == null ? 0 : request.installmentCount();
        if (installments < 1 || installments > MAX_INSTALLMENTS) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Informe uma quantidade entre 1 e " + MAX_INSTALLMENTS + " parcelas.");
        }
        BigDecimal principal = positive(request.loanedAmount(),
                "Informe um valor emprestado maior que zero.");
        BigDecimal discount = nonNegative(request.discountAmount(), "O desconto não pode ser negativo.");
        // O aplicativo legado soma esse campo ao valor emprestado. No Money novo
        // ele recebe o nome de "Valor do Negociado", mas continua persistido em
        // `juros` para manter parcelas, relatórios e integrações compatíveis.
        BigDecimal interest = negotiatedAmount(request.negotiatedAmount(), request.interestAmount());
        BigDecimal lateFee = nonNegative(request.lateFeeAmount(), "A multa diária não pode ser negativa.");
        BigDecimal total = principal.add(interest).subtract(discount).setScale(2, RoundingMode.HALF_UP);
        if (total.signum() <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O valor total do contrato deve ser maior que zero.");
        }
        String type = paymentType(request.paymentType());
        String approval = user.isAdministrator() ? "APROVADO" : "PENDENTE";
        long loanId = repository.insertLoan(request.clientId(), contractDate, firstDueDate,
                installments, nullable(request.notes()), type, principal, discount, interest,
                lateFee, nullable(request.collateral()), upperNullable(request.clientOwner()),
                Boolean.TRUE.equals(request.missing()), approval);
        repository.insertInstallments(loanId, schedule(firstDueDate, installments, type, total));
        LoanSnapshot loan = repository.requireSnapshot(user.getId(), loanId);
        if (!user.isAdministrator()) {
            repository.createApproval(loan, "EMPRESTIMO", null, loanId, null, total,
                    user.getUsername(), "Novo empréstimo " + loanId + " aguardando conferência.", null);
        }
        repository.log("EMPRESTIMO", loanId, "criarEmprestimo",
                "Novo contrato criado para o cliente " + request.clientId() + ".",
                user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional(readOnly = true)
    public LoanMessageResponse message(UserAccount user, long loanId, String rawType) {
        LoanSnapshot loan = repository.requireSnapshot(user.getId(), loanId);
        String type = rawType == null ? "" : rawType.trim().toUpperCase(Locale.ROOT);
        if (!Set.of("CONTRATO", "DIVIDA").contains(type)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Tipo de mensagem inválido.");
        }
        List<LoanInstallmentResponse> installments = repository.installments(loanId, loan.lateFee());
        return new LoanMessageResponse(type, "DIVIDA".equals(type)
                ? debtMessage(loan, installments)
                : contractMessage(loan, installments, repository.requireContractMessage(loanId)));
    }

    @Transactional(readOnly = true)
    public String contractMessageForSystem(long loanId) {
        LoanSnapshot loan = repository.requireSnapshotForSystem(loanId);
        return contractMessage(loan, repository.installments(loanId, loan.lateFee()),
                repository.requireContractMessage(loanId));
    }

    @Transactional(readOnly = true)
    public LoanMessageResponse installmentMessage(UserAccount user, long loanId,
                                                   long installmentId, String rawType) {
        LoanSnapshot loan = repository.requireSnapshot(user.getId(), loanId);
        String type = rawType == null ? "" : rawType.trim().toUpperCase(Locale.ROOT);
        if (!Set.of("COBRANCA", "ATRASO").contains(type)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Tipo de mensagem da parcela inválido.");
        }
        LoanInstallmentResponse installment = repository.installments(loanId, loan.lateFee()).stream()
                .filter(item -> item.id() == installmentId)
                .findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Parcela não encontrada."));
        InstallmentMessageSnapshot source = repository.requireInstallmentMessage(loanId, installmentId);
        return new LoanMessageResponse(type, installmentMessageText(loan, installment, source, type));
    }

    private String installmentMessageText(LoanSnapshot loan, LoanInstallmentResponse installment,
                                          InstallmentMessageSnapshot source, String type) {
        String link = nullable(source.link());
        String template;
        if ("ATRASO".equals(type)) {
            template = nullable(source.overdueMessage());
            if (template == null) {
                template = "Olá, {nome}. A parcela {numero_parcela} do contrato {contrato} "
                        + "venceu em {vencimento} e possui o total atualizado de {total}.";
            }
        } else {
            template = link != null && nullable(source.collectionLinkMessage()) != null
                    ? source.collectionLinkMessage() : nullable(source.collectionMessage());
            if (template == null) {
                template = "Olá, {nome}. A parcela {numero_parcela} do contrato {contrato} "
                        + "possui o valor pendente de {valor}.";
            }
        }
        BigDecimal updatedTotal = installment.balanceAmount()
                .add(installment.overdueInterestAmount()).setScale(2, RoundingMode.HALF_UP);
        return template
                .replace("{nome}", source.clientName())
                .replace("{contrato}", String.valueOf(loan.id()))
                .replace("{numero_parcela}", installment.number())
                .replace("{parcela_texto}", installment.number() + "ª parcela")
                .replace("{parcela}", currency(installment.amount()))
                .replace("{valor}", currency(updatedTotal))
                .replace("{valor_pendente}", currency(updatedTotal))
                .replace("{multa}", currency(installment.overdueInterestAmount()))
                .replace("{dias}", String.valueOf(installment.overdueDays()))
                .replace("{total}", currency(updatedTotal))
                .replace("{vencimento}", shortDate(installment.dueDate()))
                .replace("{link}", link == null ? "Entre em contato para regularização." : link)
                .trim();
    }

    private String contractMessage(LoanSnapshot loan, List<LoanInstallmentResponse> installments,
                                   ContractMessageSnapshot source) {
        boolean refinanced = isNegotiatedOrigin(loan);
        String template = refinanced ? nullable(source.refinancedLoanMessage()) : nullable(source.loanMessage());
        if (template == null && refinanced) {
            template = nullable(source.loanMessage());
        }
        if (template == null) {
            return defaultContractMessage(loan, installments);
        }

        BigDecimal installmentAmount = loan.installmentCount() <= 0
                ? zero()
                : loan.loaned().add(loan.interest())
                        .divide(BigDecimal.valueOf(loan.installmentCount()), 2, RoundingMode.HALF_UP);
        String city = joinCity(source.city(), source.state());
        String postalCode = "0".equals(source.postalCode()) ? "" : text(source.postalCode());
        String result = template
                .replace("{cliente}", text(source.clientName()))
                .replace("{endereco}", text(source.address()))
                .replace("{bairro}", text(source.neighborhood()))
                .replace("{numero}", text(source.number()))
                .replace("{area}", text(loan.regionName()))
                .replace("{cep}", postalCode)
                .replace("{cidade}", city)
                .replace("{comercio}", source.business() == null ? "Sem comércio" : source.business())
                .replace("{parcelas}", String.valueOf(loan.installmentCount()))
                .replace("{data}", shortDate(loan.contractDate()))
                .replace("{valor}", currency(refinanced ? loan.originalLoanAmount() : loan.loaned()))
                .replace("{refinanciamento}", currency(loan.loaned()))
                .replace("{valorparcela}", currency(installmentAmount))
                .replace("{tipo}", paymentTypeLabel(loan.paymentType()))
                .replace("{gerarparcelas}", installmentSchedule(loan, installments));
        return result.trim();
    }

    private String installmentSchedule(LoanSnapshot loan, List<LoanInstallmentResponse> installments) {
        StringBuilder message = new StringBuilder();
        int previousWeek = -1;
        int weekSequence = 1;
        if ("D".equals(loan.paymentType()) && !installments.isEmpty()) {
            message.append("*SEMANA 01*\n");
        }
        for (LoanInstallmentResponse installment : installments) {
            LocalDateTime dueDate = installment.dueDate();
            if ("D".equals(loan.paymentType()) && dueDate != null) {
                int currentWeek = dueDate.toLocalDate()
                        .get(WeekFields.of(Locale.getDefault()).weekOfWeekBasedYear());
                if (previousWeek < 0) {
                    previousWeek = currentWeek;
                } else if (previousWeek != currentWeek) {
                    previousWeek = currentWeek;
                    weekSequence++;
                    message.append("\n*SEMANA ")
                            .append(String.format(Locale.ROOT, "%02d", weekSequence))
                            .append("*\n");
                }
            }
            message.append("🟡 ").append(shortDate(dueDate));
            if (dueDate != null) {
                message.append(" ").append(SHORT_WEEKDAY.format(dueDate).toUpperCase(new Locale("pt", "BR")));
            }
            if (!installment.pending()) {
                message.append(" ✅");
            } else if (installment.paidAmount().signum() > 0) {
                message.append(" 🟨 Vlr. Pendente: ").append(currency(installment.balanceAmount()));
            }
            message.append("\n");
        }
        return message.toString();
    }

    private String joinCity(String city, String state) {
        String cityText = text(city);
        String stateText = text(state);
        if (cityText.isEmpty()) return stateText;
        if (stateText.isEmpty()) return cityText;
        return cityText + " - " + stateText;
    }

    private String text(String value) {
        return value == null ? "" : value;
    }

    private String defaultContractMessage(LoanSnapshot loan, List<LoanInstallmentResponse> installments) {
        BigDecimal displayedLoaned = isNegotiatedOrigin(loan)
                ? loan.originalLoanAmount() : loan.loaned();
        BigDecimal negotiated = negotiatedValue(loan, loan.loaned(), loan.interest());
        StringBuilder message = new StringBuilder()
                .append("Olá, ").append(loan.clientName()).append(". Seguem os dados do contrato ")
                .append(loan.id()).append(":\n\n")
                .append("Valor emprestado: ").append(currency(displayedLoaned)).append("\n")
                .append("Valor negociado: ").append(currency(negotiated)).append("\n")
                .append("Valor total: ")
                .append(currency(loan.loaned().add(loan.interest()).subtract(loan.discount())))
                .append("\nTipo de cobrança: ").append(paymentTypeLabel(loan.paymentType()))
                .append("\nParcelas: ").append(loan.installmentCount()).append("\n\nCronograma:\n");
        for (LoanInstallmentResponse installment : installments) {
            message.append("• ").append(installment.number()).append("ª parcela - ")
                    .append(shortDate(installment.dueDate())).append(" - ")
                    .append(currency(installment.totalAmount()));
            if (!installment.pending()) message.append(" ✅");
            else if (installment.paidAmount().signum() > 0) {
                message.append(" - saldo ").append(currency(installment.balanceAmount()));
            }
            message.append("\n");
        }
        return message.toString().trim();
    }

    private String debtMessage(LoanSnapshot loan, List<LoanInstallmentResponse> installments) {
        long paidCount = installments.stream().filter(item -> !item.pending()).count();
        long pendingCount = installments.stream().filter(LoanInstallmentResponse::pending).count();
        long partialCount = installments.stream()
                .filter(item -> item.pending() && item.paidAmount().signum() > 0).count();
        long overdueCount = installments.stream().filter(item -> item.pending() && item.overdueDays() > 0).count();
        BigDecimal paid = installments.stream().map(LoanInstallmentResponse::paidAmount)
                .reduce(zero(), BigDecimal::add);
        BigDecimal debt = installments.stream().map(LoanInstallmentResponse::balanceAmount)
                .reduce(zero(), BigDecimal::add);
        BigDecimal overdueInterest = installments.stream().map(LoanInstallmentResponse::overdueInterestAmount)
                .reduce(zero(), BigDecimal::add);
        BigDecimal displayedLoaned = isNegotiatedOrigin(loan)
                ? loan.originalLoanAmount() : loan.loaned();
        BigDecimal negotiated = negotiatedValue(loan, loan.loaned(), loan.interest());
        StringBuilder message = new StringBuilder()
                .append("Olá, ").append(loan.clientName())
                .append(". Segue o resumo atual da dívida do contrato ").append(loan.id()).append(":\n\n")
                .append("Valor emprestado: ").append(currency(displayedLoaned)).append("\n")
                .append("Valor negociado: ").append(currency(negotiated)).append("\n")
                .append("Valor total do contrato: ")
                .append(currency(loan.loaned().add(loan.interest()).subtract(loan.discount()))).append("\n")
                .append("Valor pago até agora: ").append(currency(paid)).append("\n")
                .append("Dívida pendente sem juros de atraso: ").append(currency(debt)).append("\n")
                .append("Juros/multa por atraso até hoje: ").append(currency(overdueInterest)).append("\n")
                .append("Total atualizado para pagamento hoje: ")
                .append(currency(debt.add(overdueInterest))).append("\n\n")
                .append("Parcelas do contrato: ").append(installments.size()).append("\n")
                .append("Parcelas pagas: ").append(paidCount).append("\n")
                .append("Parcelas pendentes: ").append(pendingCount).append("\n")
                .append("Parcelas parciais: ").append(partialCount).append("\n")
                .append("Parcelas vencidas: ").append(overdueCount);
        if (pendingCount > 0) {
            message.append("\n\nDetalhamento das parcelas pendentes:\n");
            for (LoanInstallmentResponse item : installments) {
                if (!item.pending()) continue;
                message.append("• Parcela ").append(item.number()).append(" | venc. ")
                        .append(shortDate(item.dueDate())).append(" | saldo ")
                        .append(currency(item.balanceAmount()));
                if (item.overdueInterestAmount().signum() > 0) {
                    message.append(" | juros atraso ").append(currency(item.overdueInterestAmount()));
                }
                message.append(" | total ")
                        .append(currency(item.balanceAmount().add(item.overdueInterestAmount()))).append("\n");
            }
        } else {
            message.append("\n\nNão constam parcelas pendentes neste contrato.");
        }
        return message.toString().trim();
    }

    private String currency(BigDecimal value) {
        return CURRENCY.format(money(value));
    }

    private String shortDate(LocalDateTime value) {
        return value == null ? "não informado" : SHORT_DATE.format(value);
    }

    @Transactional
    public LoanDetailResponse update(UserAccount user, long loanId, LoanUpdateRequest request) {
        requireEditable(user);
        LoanSnapshot loan = requireUnlocked(user, loanId);
        LocalDate contractDate = required(request.contractDate(), "Informe a data do contrato.");
        LocalDate firstDueDate = required(request.firstDueDate(), "Informe o primeiro vencimento.");
        int installments = request.installmentCount() == null ? 0 : request.installmentCount();
        if (installments < 1 || installments > MAX_INSTALLMENTS) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Informe uma quantidade entre 1 e " + MAX_INSTALLMENTS + " parcelas.");
        }
        BigDecimal discount = nonNegative(request.discountAmount(), "O desconto não pode ser negativo.");
        boolean negotiatedOrigin = isNegotiatedOrigin(loan);
        BigDecimal principal;
        BigDecimal interest;
        if (request.negotiatedAmount() == null) {
            // Compatibilidade com clientes anteriores da API, que enviam juros diretamente.
            principal = positive(request.loanedAmount(), "Informe um valor emprestado maior que zero.");
            interest = nonNegative(request.interestAmount(), "Os juros não podem ser negativos.");
        } else if (negotiatedOrigin) {
            // No legado, o destino de uma negociação guarda o valor negociado em
            // valor_emprestado. O valor original está na tabela refinanciamentos.
            principal = positive(request.negotiatedAmount(), "Informe um valor negociado maior que zero.");
            interest = loan.interest();
        } else {
            principal = positive(request.loanedAmount(), "Informe um valor emprestado maior que zero.");
            interest = negotiatedAmount(request.negotiatedAmount(), null);
        }
        BigDecimal lateFee = nonNegative(request.lateFeeAmount(), "A multa diária não pode ser negativa.");
        BigDecimal total = principal.add(interest).subtract(discount).setScale(2, RoundingMode.HALF_UP);
        if (total.signum() <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "O valor total do contrato deve ser maior que zero.");
        }
        String type = paymentType(request.paymentType());
        boolean structural = !sameDate(loan.contractDate(), contractDate)
                || !sameDate(loan.firstDueDate(), firstDueDate)
                || loan.installmentCount() != installments || loan.loaned().compareTo(principal) != 0
                || loan.discount().compareTo(discount) != 0 || loan.interest().compareTo(interest) != 0
                || !loan.paymentType().equals(type);
        if (structural && repository.paymentCount(loanId) > 0) {
            throw new ApiException(HttpStatus.CONFLICT,
                    "Este contrato já possui pagamentos. Valores, parcelas e vencimentos estruturais não podem ser recriados.");
        }
        MapSqlParameterSource values = new MapSqlParameterSource()
                .addValue("contractDate", java.sql.Timestamp.valueOf(contractDate.atTime(12, 0)))
                .addValue("firstDueDate", java.sql.Timestamp.valueOf(firstDueDate.atTime(12, 0)))
                .addValue("installmentCount", installments).addValue("notes", nullable(request.notes()))
                .addValue("paymentType", type).addValue("loanedAmount", principal)
                .addValue("discountAmount", discount).addValue("interestAmount", interest)
                .addValue("totalAmount", total).addValue("profitAmount", zero())
                .addValue("lateFeeAmount", lateFee).addValue("collateral", nullable(request.collateral()))
                .addValue("clientOwner", upperNullable(request.clientOwner()))
                .addValue("missing", Boolean.TRUE.equals(request.missing()));
        repository.updateLoan(loanId, values);
        if (structural) {
            repository.deleteInstallments(loanId);
            repository.insertInstallments(loanId, schedule(firstDueDate, installments, type, total));
        }
        repository.log("EMPRESTIMO", loanId, "alterarEmprestimo",
                structural ? "Contrato alterado e parcelas recalculadas." : "Dados do contrato atualizados.",
                user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse updateInstallment(UserAccount user, long loanId, long installmentId,
                                                InstallmentUpdateRequest request) {
        requireEditable(user);
        requireUnlocked(user, loanId);
        InstallmentSnapshot current = repository.requireInstallment(loanId, installmentId);
        LocalDate dueDate = required(request.dueDate(), "Informe o vencimento da parcela.");
        BigDecimal amount = positive(request.amount(), "O valor da parcela deve ser maior que zero.");
        BigDecimal interest = nonNegative(request.interestAmount(), "Os juros da parcela não podem ser negativos.");
        BigDecimal total = amount.add(interest);
        if (current.paid().compareTo(total) > 0) {
            throw new ApiException(HttpStatus.CONFLICT,
                    "O novo valor da parcela é menor que o total já recebido.");
        }
        boolean changedDueDate = !sameDate(current.dueDate(), dueDate);
        String note = nullable(request.dueDateNote());
        if (changedDueDate && note == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Informe o motivo da alteração do vencimento.");
        }
        repository.updateInstallment(installmentId, dueDate, amount, interest, note);
        if (changedDueDate) {
            repository.renumberInstallmentsByDueDate(loanId);
        }
        // Uma parcela pode ser editada depois de já ter recebido o valor total.
        // Recalcula o indicador pendente e os totais para não voltar a exibi-la
        // como parcial apenas porque o estado persistido era anterior à edição.
        repository.synchronizeInstallment(installmentId);
        repository.refreshLoanFinancialTotals(loanId);
        repository.log("PARCELA", installmentId, "alterarParcela",
                "Parcela do contrato " + loanId + " atualizada.", user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse addPayment(UserAccount user, long loanId, long installmentId,
                                         PaymentRequest request) {
        requireEditable(user);
        LoanSnapshot loan = requireUnlocked(user, loanId);
        InstallmentSnapshot installment = repository.requireInstallment(loanId, installmentId);
        BigDecimal amount = positive(request.amount(), "Informe um pagamento maior que zero.");
        BigDecimal balance = installment.amount().add(installment.interest()).subtract(installment.paid());
        if (amount.compareTo(balance) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O pagamento não pode ser maior que o saldo da parcela.");
        }
        LocalDate date = request.date() == null ? today() : request.date();
        long paymentId = repository.insertPayment(loanId, installmentId, amount, date,
                nullable(request.note()), "APROVADO");
        // A conferência financeira é somente uma auditoria posterior. Como no
        // Money legado, a baixa manual entra no saldo da parcela imediatamente.
        repository.createApproval(loan, "PAGAMENTO", null, paymentId, installmentId, amount,
                user.getUsername(), "Pagamento manual na parcela do contrato " + loanId + ".", null);
        repository.synchronizeInstallment(installmentId);
        repository.refreshLoanFinancialTotals(loanId);
        repository.log("PAGAMENTO", paymentId, "lancarPagamento",
                "Pagamento de " + amount + " lançado na parcela do contrato " + loanId + ".",
                user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse updatePayment(UserAccount user, long loanId, long installmentId,
                                            long paymentId, PaymentRequest request) {
        requireEditable(user);
        requireUnlocked(user, loanId);
        InstallmentSnapshot installment = repository.requireInstallment(loanId, installmentId);
        PaymentSnapshot current = repository.requirePayment(loanId, installmentId, paymentId);
        if (current.automatic()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Pagamentos automáticos não podem ser editados.");
        }
        if ("JUROS_ROLAGEM".equals(current.type())) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "A baixa somente dos juros não pode ser editada como pagamento comum.");
        }
        BigDecimal amount = positive(request.amount(), "Informe um pagamento maior que zero.");
        BigDecimal balanceWithoutCurrent = installment.amount().add(installment.interest())
                .subtract(installment.paid()).add(current.amount());
        if (amount.compareTo(balanceWithoutCurrent) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O pagamento não pode ser maior que o saldo da parcela.");
        }
        repository.updatePayment(paymentId, amount, request.date() == null ? today() : request.date(),
                nullable(request.note()), "APROVADO");
        repository.synchronizeInstallment(installmentId);
        repository.refreshLoanFinancialTotals(loanId);
        repository.log("PAGAMENTO", paymentId, "alterarPagamento",
                "Pagamento do contrato " + loanId + " alterado.", user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse deletePayment(UserAccount user, long loanId, long installmentId, long paymentId) {
        requireEditable(user);
        requireUnlocked(user, loanId);
        PaymentSnapshot payment = repository.requirePayment(loanId, installmentId, paymentId);
        if (payment.automatic()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Pagamentos automáticos não podem ser excluídos.");
        }
        if ("JUROS_ROLAGEM".equals(payment.type())) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "A baixa somente dos juros deve ser conferida pelo fluxo financeiro.");
        }
        repository.deletePayment(paymentId);
        repository.synchronizeInstallment(installmentId);
        repository.refreshLoanFinancialTotals(loanId);
        repository.log("PAGAMENTO", paymentId, "excluirPagamento",
                "Pagamento removido do contrato " + loanId + ".", user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse distributePayment(UserAccount user, long loanId, PaymentRequest request) {
        requireEditable(user);
        LoanSnapshot loan = requireUnlocked(user, loanId);
        BigDecimal requested = positive(request.amount(), "Informe um pagamento maior que zero.");
        List<LoanInstallmentResponse> installments = repository.installments(loanId, loan.lateFee());
        BigDecimal available = installments.stream().map(LoanInstallmentResponse::balanceAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        if (requested.compareTo(available) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O pagamento não pode ser maior que o saldo do contrato.");
        }
        String group = "MONEY2-" + UUID.randomUUID();
        BigDecimal remaining = requested;
        for (LoanInstallmentResponse installment : installments) {
            if (remaining.signum() <= 0 || installment.balanceAmount().signum() <= 0) continue;
            BigDecimal amount = remaining.min(installment.balanceAmount());
            long paymentId = repository.insertPayment(loanId, installment.id(), amount,
                    request.date() == null ? today() : request.date(), nullable(request.note()), "APROVADO");
            repository.createApproval(loan, "PAGAMENTO", null, paymentId, installment.id(), amount,
                    user.getUsername(), "Pagamento distribuído no contrato " + loanId + ".", group);
            repository.synchronizeInstallment(installment.id());
            remaining = remaining.subtract(amount);
        }
        repository.refreshLoanFinancialTotals(loanId);
        repository.log("PAGAMENTO", loanId, "lancarPagamentoContrato",
                "Pagamento de " + requested + " distribuído entre as parcelas.", user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse interestOnlyPayment(
            UserAccount user, long loanId, InterestOnlyPaymentRequest request) {
        requireEditable(user);
        LoanSnapshot loan = requireUnlocked(user, loanId);
        if (request == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe os dados da baixa dos juros.");
        }
        List<LoanInstallmentResponse> pending = repository.installments(loanId, loan.lateFee()).stream()
                .filter(item -> item.pending() && item.balanceAmount().signum() > 0)
                .toList();
        if (pending.isEmpty()) {
            throw new ApiException(HttpStatus.CONFLICT, "Este contrato não possui parcela pendente.");
        }
        long installmentId = request.installmentId() == null
                ? pending.get(0).id() : request.installmentId();
        InstallmentSnapshot installment = repository.requireInstallment(loanId, installmentId);
        if (pending.stream().noneMatch(item -> item.id() == installmentId)) {
            throw new ApiException(HttpStatus.CONFLICT, "A parcela selecionada já está paga.");
        }
        BigDecimal suggested = loan.interest().signum() > 0 ? loan.interest() : installment.interest();
        BigDecimal amount = request.amount() == null
                ? positive(suggested, "Informe o valor dos juros.")
                : positive(request.amount(), "Informe o valor dos juros.");
        LocalDate previousDue = installment.dueDate() == null
                ? today() : installment.dueDate().toLocalDate();
        LocalDate newDue = request.newDueDate() == null
                ? dueDate(previousDue, loan.paymentType(), 1) : request.newDueDate();
        if (!newDue.isAfter(previousDue)) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O novo vencimento deve ser posterior ao vencimento atual.");
        }
        String note = nullable(request.note());
        long paymentId = repository.insertPayment(loanId, installmentId, amount,
                request.date() == null ? today() : request.date(), note, "APROVADO", "JUROS_ROLAGEM");
        repository.updateInstallmentDueDate(installmentId, newDue,
                "Vencimento prorrogado após baixa somente dos juros.");
        repository.renumberInstallmentsByDueDate(loanId);
        repository.createApproval(loan, "PAGAMENTO", "JUROS_ROLAGEM",
                paymentId, installmentId, amount, user.getUsername(),
                "Baixa somente dos juros e prorrogação da parcela no contrato " + loanId + ".",
                "JUROS_ROLAGEM_" + loanId + "_" + System.currentTimeMillis());
        repository.synchronizeInstallment(installmentId);
        repository.refreshLoanFinancialTotals(loanId);
        repository.log("PAGAMENTO", paymentId, "baixarSoJuros",
                "Juros de " + amount + " registrados; vencimento de " + previousDue
                        + " para " + newDue + ".", user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse requestClosure(UserAccount user, long loanId, String action) {
        requireEditable(user);
        LoanSnapshot loan = requireUnlocked(user, loanId);
        String normalized = action == null ? "" : action.trim().toUpperCase(Locale.ROOT);
        if (!Set.of("CANCELAR", "FINALIZAR").contains(normalized)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Ação de encerramento inválida.");
        }
        if (user.isAdministrator()) {
            if ("CANCELAR".equals(normalized)) repository.cancelLoan(loanId);
            else repository.deleteLoan(loanId);
            if ("FINALIZAR".equals(normalized)) return null;
        } else {
            repository.setLoanApproval(loanId, "PENDENTE");
            repository.createApproval(loan, "FINALIZACAO", normalized, loanId, null,
                    loan.receivable(), user.getUsername(),
                    "Solicitação para " + normalized.toLowerCase(Locale.ROOT) + " o contrato " + loanId + ".", null);
        }
        repository.log("EMPRESTIMO", loanId, normalized.toLowerCase(Locale.ROOT),
                (user.isAdministrator() ? "Contrato processado pelo administrador." : "Aguardando aprovação do administrador."),
                user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public LoanDetailResponse negotiate(UserAccount user, long loanId, String mode,
                                        LoanNegotiationRequest request) {
        requireEditable(user);
        LoanSnapshot origin = requireUnlocked(user, loanId);
        String type = mode == null ? "" : mode.trim().toUpperCase(Locale.ROOT);
        boolean renewal = "RENOVACAO".equals(type);
        if (!renewal && !"REFINANCIAMENTO".equals(type)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Tipo de negociação inválido.");
        }
        // O saldo da negociação é sempre recalculado no servidor a partir das
        // parcelas pendentes e dos pagamentos aprovados. Assim, refinanciamento
        // e renovação não dependem de um resumo antigo enviado pelo aplicativo.
        BigDecimal debt = nonNegative(repository.pendingDebt(loanId),
                "A dívida não pode ser negativa.");
        BigDecimal additional = nonNegative(request.additionalAmount(), "O valor a emprestar não pode ser negativo.");
        BigDecimal interest = nonNegative(request.interestAmount(), "Os juros não podem ser negativos.");
        BigDecimal percent = nonNegative(request.interestPercent(), "O percentual não pode ser negativo.");
        BigDecimal principal = renewal
                ? positive(additional, "Informe o valor a emprestar.")
                : positive(debt, "Não há saldo devedor para refinanciar.");
        BigDecimal total = principal.add(interest).setScale(2, RoundingMode.HALF_UP);
        if (total.signum() <= 0) throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o valor da negociação.");
        int count = request.installmentCount() == null ? 0 : request.installmentCount();
        if (count < 1 || count > MAX_INSTALLMENTS) throw new ApiException(HttpStatus.BAD_REQUEST, "Quantidade de parcelas inválida.");
        LocalDate firstDue = required(request.firstDueDate(), "Informe o primeiro vencimento.");
        String paymentType = paymentType(request.paymentType());
        String approval = user.isAdministrator() ? "APROVADO" : "PENDENTE";
        // Mantém a mesma persistência do aplicativo antigo. No refinanciamento,
        // o total negociado passa a ser o valor emprestado e os juros do novo
        // contrato ficam zerados. Na renovação, principal e juros seguem separados.
        BigDecimal storedPrincipal = renewal ? principal : total;
        BigDecimal storedInterest = renewal ? interest : zero();
        BigDecimal recordedTotal = renewal ? principal : total;
        long destinationId = repository.insertNegotiatedLoan(origin, storedPrincipal, storedInterest,
                zero(), count, firstDue, paymentType, nullable(request.notes()), approval);
        repository.insertInstallments(destinationId, schedule(firstDue, count, paymentType, total));
        if (renewal) feedbackRepository.copyForRenewal(loanId, destinationId);
        if (user.isAdministrator()) {
            repository.setNegotiatedOrigin(loanId, renewal);
            repository.insertRefinancing(loanId, destinationId, origin.loaned(), debt, interest, percent,
                    recordedTotal);
            repository.refreshLoanFinancialTotals(loanId);
            repository.refreshLoanFinancialTotals(destinationId);
        } else {
            LoanSnapshot destination = repository.requireSnapshot(user.getId(), destinationId);
            long approvalId = repository.createApproval(destination, type, null, destinationId, null, recordedTotal,
                    user.getUsername(), type + " do contrato " + loanId + " para o contrato " + destinationId + ".", null);
            repository.setApprovalNegotiationData(approvalId, loanId, origin.loaned(), debt, interest, percent,
                    recordedTotal);
        }
        repository.log("EMPRESTIMO", destinationId, type.toLowerCase(Locale.ROOT),
                "Novo contrato criado a partir do contrato " + loanId + ".", user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), destinationId));
    }

    @Transactional
    public LoanDetailResponse decideApproval(UserAccount user, long loanId, long approvalId,
                                             boolean approve, LoanDecisionRequest request) {
        if (!user.isAdministrator()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Somente administradores podem conferir operações.");
        }
        repository.requireSnapshot(user.getId(), loanId);
        ApprovalSnapshot approval = repository.requirePendingApproval(user.getId(), loanId, approvalId);
        if (!"PENDENTE".equals(approval.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "Esta operação já foi conferida.");
        }
        String reason = nullable(request == null ? null : request.reason());
        if (!approve && reason == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o motivo da reprovação.");
        }
        if ("PAGAMENTO".equals(approval.type())) {
            if (approval.entityId() == null) throw new ApiException(HttpStatus.CONFLICT, "Pagamento da conferência não encontrado.");
            // Aprovar ou indeferir encerra somente a conferência. O pagamento já
            // produziu a baixa financeira no momento em que foi lançado.
            repository.setPaymentApproval(approval.entityId(), "APROVADO");
            if ("JUROS_ROLAGEM".equals(approval.action())) {
                repository.applyDeferredInterestRollIfPresent(approvalId);
            }
            if (approval.installmentId() != null) repository.synchronizeInstallment(approval.installmentId());
            repository.refreshLoanFinancialTotals(loanId);
        } else if ("FINALIZACAO".equals(approval.type())) {
            long target = approval.loanId() == null ? loanId : approval.loanId();
            if (approve) {
                if ("FINALIZAR".equals(approval.action())) {
                    repository.decideApproval(approvalId, "APROVADO", user.getUsername(), reason);
                    repository.deleteLoan(target);
                    return null;
                }
                repository.cancelLoan(target);
            } else repository.setLoanApproval(target, "APROVADO");
        } else if ("EMPRESTIMO".equals(approval.type())) {
            long target = approval.entityId() == null ? loanId : approval.entityId();
            if (approve) repository.setLoanApproval(target, "APROVADO");
            else {
                repository.decideApproval(approvalId, "REPROVADO", user.getUsername(), reason);
                repository.deleteLoan(target);
                return null;
            }
        } else if (Set.of("REFINANCIAMENTO", "RENOVACAO").contains(approval.type())) {
            long destination = approval.entityId() == null ? approval.loanId() : approval.entityId();
            if (approve) {
                repository.setLoanApproval(destination, "APROVADO");
                if (approval.originLoanId() != null) {
                    repository.setNegotiatedOrigin(approval.originLoanId(), "RENOVACAO".equals(approval.type()));
                    repository.insertRefinancing(approval.originLoanId(), destination,
                            approval.originalAmount(), approval.debtAmount(), approval.interestAmount(),
                            approval.interestPercent(), approval.totalAmount());
                    repository.refreshLoanFinancialTotals(approval.originLoanId());
                    repository.refreshLoanFinancialTotals(destination);
                }
            } else {
                repository.decideApproval(approvalId, "REPROVADO", user.getUsername(), reason);
                if (approval.originLoanId() != null && approval.originLoanId() > 0) {
                    repository.linkRejectedNegotiationToOrigin(approvalId, approval.originLoanId());
                }
                repository.deleteLoanPreservingApproval(destination, approvalId);
                repository.log("APROVACAO", approvalId, "reprovar",
                        "Operação reprovada: " + reason, user.getUsername());
                return null;
            }
        }
        repository.decideApproval(approvalId, approve ? "APROVADO" : "REPROVADO",
                user.getUsername(), reason);
        repository.log("APROVACAO", approvalId, approve ? "aprovar" : "reprovar",
                approve ? "Operação aprovada." : "Operação reprovada: " + reason, user.getUsername());
        return response(user, repository.requireSnapshot(user.getId(), loanId));
    }

    @Transactional
    public boolean approveExpiredPaymentBySystem(long loanId, long approvalId) {
        ApprovalSnapshot approval = repository.lockExpiredPaymentApproval(loanId, approvalId);
        if (approval == null) return false;
        if (approval.entityId() == null) {
            throw new IllegalStateException("Pagamento da conferência " + approvalId + " não encontrado.");
        }
        repository.setPaymentApproval(approval.entityId(), "APROVADO");
        if ("JUROS_ROLAGEM".equals(approval.action())) {
            repository.applyDeferredInterestRollIfPresent(approvalId);
        }
        if (approval.installmentId() != null) {
            repository.synchronizeInstallment(approval.installmentId());
        }
        repository.refreshLoanFinancialTotals(loanId);
        repository.decideApproval(approvalId, "APROVADO", SYSTEM_APPROVER, SYSTEM_APPROVER);
        repository.log("APROVACAO", approvalId, "aprovar", SYSTEM_APPROVER, SYSTEM_APPROVER);
        return true;
    }

    private LoanDetailResponse response(UserAccount user, LoanSnapshot loan) {
        return response(user, loan, true);
    }

    private LoanDetailResponse response(
            UserAccount user,
            LoanSnapshot loan,
            boolean includeSupplemental) {
        BigDecimal total = loan.loaned().add(loan.interest()).subtract(loan.discount()).setScale(2, RoundingMode.HALF_UP);
        BigDecimal installmentAmount = loan.installmentCount() <= 0 ? zero()
                : total.divide(BigDecimal.valueOf(loan.installmentCount()), 2, RoundingMode.HALF_UP);
        String lockReason = loan.operationLocked() ? "Existe uma operação aguardando aprovação." : null;
        boolean negotiatedOrigin = isNegotiatedOrigin(loan);
        BigDecimal negotiated = negotiatedValue(loan, loan.loaned(), loan.interest());
        return new LoanDetailResponse(loan.id(), loan.clientId(), loan.clientName(), loan.regionId(), loan.regionName(),
                loan.contractDate(), loan.firstDueDate(), loan.installmentCount(), loan.notes(), loan.paymentType(),
                paymentTypeLabel(loan.paymentType()), loan.loaned(), loan.originalLoanAmount(),
                loan.discount(), loan.interest(), negotiated, negotiatedOrigin, loan.lateFee(),
                total, installmentAmount, loan.received(), loan.receivable(), loan.profit(),
                loan.collateral(),
                loan.clientOwner(), loan.missing(), loan.active(), loan.refinanced(), loan.renewed(), loan.numericStatus(),
                loan.status(), loan.approvalStatus(), loan.operationLocked(), lockReason,
                canEdit(user) && loan.numericStatus() != 3 && !loan.refinanced(), user.isAdministrator(),
                repository.installments(loan.id(), loan.lateFee()),
                includeSupplemental ? repository.history(loan.id()) : List.of(),
                includeSupplemental ? repository.approvals(loan.id()) : List.of(),
                includeSupplemental ? repository.origins(loan.id()) : List.of());
    }

    private LoanSnapshot requireUnlocked(UserAccount user, long loanId) {
        LoanSnapshot loan = repository.requireSnapshot(user.getId(), loanId);
        if (loan.numericStatus() == 3 || loan.refinanced()) {
            throw new ApiException(HttpStatus.CONFLICT, "Este empréstimo está encerrado e não pode ser alterado.");
        }
        if (loan.operationLocked()) {
            throw new ApiException(HttpStatus.CONFLICT, "Este empréstimo possui uma operação aguardando aprovação.");
        }
        return loan;
    }

    private void requireEditable(UserAccount user) {
        if (!canEdit(user)) throw new ApiException(HttpStatus.FORBIDDEN,
                "Seu usuário não possui permissão para editar rotinas financeiras.");
    }
    private boolean canEdit(UserAccount user) { return user.isAdministrator() || !user.isReadOnly(); }

    private BigDecimal negotiatedAmount(BigDecimal negotiatedValue, BigDecimal legacyInterest) {
        BigDecimal negotiated = negotiatedValue == null
                ? nonNegative(legacyInterest, "O valor negociado não pode ser negativo.")
                : nonNegative(negotiatedValue, "O valor negociado não pode ser negativo.");
        return negotiated.setScale(2, RoundingMode.HALF_UP);
    }

    private boolean isNegotiatedOrigin(LoanSnapshot loan) {
        return loan.originalLoanAmount().signum() > 0;
    }

    private BigDecimal negotiatedValue(LoanSnapshot loan, BigDecimal principal, BigDecimal interest) {
        return (isNegotiatedOrigin(loan) ? principal : interest)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private List<InstallmentSeed> schedule(LocalDate firstDue, int count, String type, BigDecimal total) {
        BigDecimal standard = total.divide(BigDecimal.valueOf(count), 2, RoundingMode.HALF_UP);
        BigDecimal accumulated = zero();
        List<InstallmentSeed> result = new ArrayList<>(count);
        for (int index = 0; index < count; index++) {
            BigDecimal amount = index == count - 1 ? total.subtract(accumulated).setScale(2, RoundingMode.HALF_UP) : standard;
            result.add(new InstallmentSeed(String.valueOf(index + 1), dueDate(firstDue, type, index), amount));
            accumulated = accumulated.add(amount);
        }
        return result;
    }

    private LocalDate dueDate(LocalDate first, String type, int index) {
        LocalDate date = switch (type) {
            case "S" -> first.plusWeeks(index);
            case "Q" -> first.plusWeeks(index * 2L);
            case "M" -> first.plusMonths(index);
            case "A" -> first.plusDays(index * 2L);
            case "B" -> first.with(TemporalAdjusters.nextOrSame(DayOfWeek.SATURDAY)).plusWeeks(index);
            case "C" -> first.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY)).plusWeeks(index);
            case "Z" -> businessDaily(first, index, true);
            default -> businessDaily(first, index, false);
        };
        if (!Set.of("A", "B", "C", "D", "Z").contains(type)) {
            if (date.getDayOfWeek() == DayOfWeek.SATURDAY) date = date.plusDays(2);
            else if (date.getDayOfWeek() == DayOfWeek.SUNDAY) date = date.plusDays(1);
        }
        return date;
    }

    private LocalDate businessDaily(LocalDate first, int index, boolean includeSaturday) {
        LocalDate date = first;
        while (isSkipped(date, includeSaturday)) date = date.plusDays(1);
        for (int advanced = 0; advanced < index; advanced++) {
            do {
                date = date.plusDays(1);
            } while (isSkipped(date, includeSaturday));
        }
        return date;
    }

    private boolean isSkipped(LocalDate date, boolean includeSaturday) {
        return date.getDayOfWeek() == DayOfWeek.SUNDAY
                || (!includeSaturday && date.getDayOfWeek() == DayOfWeek.SATURDAY);
    }

    private String paymentType(String value) {
        String normalized = value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
        Map<String, String> labels = Map.ofEntries(Map.entry("DIÁRIO", "D"), Map.entry("DIARIO", "D"),
                Map.entry("SEMANAL", "S"), Map.entry("QUINZENAL", "Q"), Map.entry("MENSAL", "M"),
                Map.entry("DIÁRIO SEG-SAB", "Z"), Map.entry("DIARIO SEG-SAB", "Z"),
                Map.entry("DIA SIM E DIA NÃO", "A"), Map.entry("DIA SIM E DIA NAO", "A"),
                Map.entry("TODO SÁBADO", "B"), Map.entry("TODO SABADO", "B"),
                Map.entry("TODO DOMINGO", "C"));
        normalized = labels.getOrDefault(normalized, normalized);
        if (!TYPES.contains(normalized)) throw new ApiException(HttpStatus.BAD_REQUEST, "Tipo de cobrança inválido.");
        return normalized;
    }

    private String paymentTypeLabel(String type) {
        return switch (type) { case "D" -> "Diário"; case "S" -> "Semanal"; case "Q" -> "Quinzenal";
            case "M" -> "Mensal"; case "Z" -> "Diário Seg-Sab"; case "A" -> "Dia sim e Dia não";
            case "B" -> "Todo Sábado"; case "C" -> "Todo Domingo"; default -> type; };
    }

    private boolean sameDate(LocalDateTime value, LocalDate date) { return value != null && value.toLocalDate().equals(date); }
    private <T> T required(T value, String message) { if (value == null) throw new ApiException(HttpStatus.BAD_REQUEST, message); return value; }
    private BigDecimal positive(BigDecimal value, String message) { BigDecimal result = money(value); if (result.signum() <= 0) throw new ApiException(HttpStatus.BAD_REQUEST, message); return result; }
    private BigDecimal nonNegative(BigDecimal value, String message) { BigDecimal result = money(value); if (result.signum() < 0) throw new ApiException(HttpStatus.BAD_REQUEST, message); return result; }
    private BigDecimal money(BigDecimal value) { return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP); }
    private BigDecimal zero() { return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP); }
    private LocalDate today() { return LocalDate.now(BUSINESS_ZONE); }
    private String nullable(String value) { String clean = value == null ? "" : value.trim(); return clean.isEmpty() ? null : clean; }
    private String upperNullable(String value) { String clean = nullable(value); return clean == null ? null : clean.toUpperCase(Locale.ROOT); }
}
