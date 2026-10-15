package com.webdigital.money2.chat;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.dashboard.DashboardModels.Metrics;
import com.webdigital.money2.dashboard.DashboardRepository;
import com.webdigital.money2.goals.FinancialGoalResponse;
import com.webdigital.money2.shared.ApiException;
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Arc2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.text.NumberFormat;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Semaphore;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType1Font;
import org.apache.pdfbox.pdmodel.font.Standard14Fonts;
import org.apache.pdfbox.pdmodel.graphics.image.LosslessFactory;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ChatSummaryPdfService {

    private static final Locale BRAZIL = Locale.forLanguageTag("pt-BR");
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final PDRectangle PAGE_SIZE = new PDRectangle(
            PDRectangle.A4.getHeight(), PDRectangle.A4.getWidth());
    private static final float PAGE_WIDTH = PAGE_SIZE.getWidth();
    private static final float PAGE_HEIGHT = PAGE_SIZE.getHeight();
    private static final Color PRIMARY = new Color(0x61B76C);
    private static final Color PRIMARY_DARK = new Color(0x064A32);
    private static final Color PRIMARY_PALE = new Color(0xEAF5EA);
    private static final Color BACKGROUND = new Color(0xF5F7FA);
    private static final Color SURFACE = Color.WHITE;
    private static final Color TEXT = new Color(0x1E1E1E);
    private static final Color TEXT_SECONDARY = new Color(0x667085);
    private static final Color DIVIDER = new Color(0xE3E7ED);
    private static final Color SHADOW = new Color(0xE9EDF2);
    private static final Color ERROR = new Color(0xD72B2B);
    private static final Color WARNING = new Color(0xF4A900);
    private static final Color NEUTRAL = new Color(0x98A2B3);
    private static final Color RECEIVED = new Color(0x247CC2);
    private static final Color RECEIVABLE = new Color(0x2467A8);
    private static final Color PROFIT = new Color(0x7C65B7);
    private static final Semaphore PDF_GENERATION_SLOTS = new Semaphore(2, true);

    private final ChatRepository chatRepository;
    private final DashboardRepository dashboardRepository;
    private final java.nio.file.Path assetsDirectory;
    private final PDType1Font regular = new PDType1Font(Standard14Fonts.FontName.HELVETICA);
    private final PDType1Font bold = new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD);

    private enum ReportIcon {
        LOANS,
        MONEY,
        RECEIVED,
        RECEIVABLE,
        OVERDUE,
        PROFIT,
        PAYMENTS,
        SETTLED,
        RENEWED,
        CLIENTS,
        INSTALLMENTS
    }

    public ChatSummaryPdfService(
            ChatRepository chatRepository,
            DashboardRepository dashboardRepository,
            @Value("${money.chat.pdf-assets-directory:/home/money/money2/data/pdf-assets}")
            String assetsDirectory) {
        this.chatRepository = chatRepository;
        this.dashboardRepository = dashboardRepository;
        this.assetsDirectory = java.nio.file.Path.of(assetsDirectory).toAbsolutePath().normalize();
    }

    @Transactional(readOnly = true, timeout = 35)
    public ChatSummaryPdfResult generate(
            UserAccount user,
            long regionId,
            LocalDate startDate,
            LocalDate endDate) {
        if (!PDF_GENERATION_SLOTS.tryAcquire()) {
            throw new ApiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    "Já existem relatórios sendo gerados. Aguarde alguns instantes e tente novamente.");
        }
        try {
            validatePeriod(startDate, endDate);
            ChatRegionOption region = chatRepository.accessibleRegions(user.getId()).stream()
                    .filter(item -> item.id().equals(regionId))
                    .findFirst()
                    .orElseThrow(() -> new ApiException(
                            HttpStatus.FORBIDDEN,
                            "A região selecionada não está disponível para seu usuário."));
            ChatFinancialSummaryResponse summary = chatRepository.summary(
                    user.getId(), regionId, startDate, endDate);
            ChatLoanStatusResponse loanStatus = chatRepository.loanStatus(
                    user.getId(), regionId, startDate, endDate);
            ChatClientStatusResponse clientStatus = chatRepository.clientStatus(
                    user.getId(), regionId);
            List<FinancialGoalResponse> goals = chatRepository.activeFinancialGoals(
                    user.getId(), regionId);
            Metrics metrics = dashboardRepository.metrics(user.getId(), regionId);

            byte[] moneyBrImage = requiredAsset("moneybr.png");
            byte[] pdf = buildPdf(
                    region.name(), startDate, endDate, summary, loanStatus,
                    clientStatus, goals, metrics, moneyBrImage);
            String fileName = "resumo_financeiro_" + safeName(region.name())
                    + "_" + LocalDate.now(BUSINESS_ZONE) + ".pdf";
            return new ChatSummaryPdfResult(pdf, fileName);
        } finally {
            PDF_GENERATION_SLOTS.release();
        }
    }

    private byte[] buildPdf(
            String regionName,
            LocalDate startDate,
            LocalDate endDate,
            ChatFinancialSummaryResponse summary,
            ChatLoanStatusResponse loanStatus,
            ChatClientStatusResponse clientStatus,
            List<FinancialGoalResponse> goals,
            Metrics metrics,
            byte[] moneyBrImage) {
        try (PDDocument document = new PDDocument();
                ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            PDImageXObject moneyBr = PDImageXObject.createFromByteArray(
                    document, moneyBrImage, "moneybr");
            addOverviewPage(
                    document, moneyBr, regionName, startDate, endDate,
                    summary, loanStatus, clientStatus, goals, metrics);
            document.save(output);
            return output.toByteArray();
        } catch (IOException exception) {
            throw new ApiException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "Não foi possível gerar o resumo financeiro em PDF.");
        }
    }

    private void addOverviewPage(
            PDDocument document,
            PDImageXObject moneyBr,
            String regionName,
            LocalDate startDate,
            LocalDate endDate,
            ChatFinancialSummaryResponse summary,
            ChatLoanStatusResponse loanStatus,
            ChatClientStatusResponse clientStatus,
            List<FinancialGoalResponse> goals,
            Metrics metrics) throws IOException {
        PDPage page = new PDPage(PAGE_SIZE);
        document.addPage(page);
        try (PDPageContentStream stream = new PDPageContentStream(document, page)) {
            fill(stream, BACKGROUND, 0, 0, PAGE_WIDTH, PAGE_HEIGHT);
            float headerHeight = 90;
            fill(stream, PRIMARY_DARK, 0, PAGE_HEIGHT - headerHeight, PAGE_WIDTH, headerHeight);
            text(stream, "RESUMO FINANCEIRO", bold, 18, Color.WHITE, 22, PAGE_HEIGHT - 29);
            text(stream, fit(regionName, 62), bold, 10.5f, Color.WHITE, 22, PAGE_HEIGHT - 48);
            periodPill(stream, periodLabel(startDate, endDate), 22, PAGE_HEIGHT - 76);
            stream.drawImage(moneyBr, PAGE_WIDTH - 158, PAGE_HEIGHT - 61, 132, 43);
            text(stream, "Inteligência financeira", regular, 7.5f,
                    new Color(0xE5F2E9), PAGE_WIDTH - 129, PAGE_HEIGHT - 70);

            float horizontalMargin = 22;
            float cardY = 438;
            float gap = 7;
            float cardWidth = (PAGE_WIDTH - horizontalMargin * 2 - gap * 5) / 6;
            summaryCard(stream, horizontalMargin, cardY, cardWidth, 52,
                    "EMPRÉSTIMOS", summary.openLoans(), PRIMARY_DARK, ReportIcon.LOANS);
            summaryCard(stream, horizontalMargin + (cardWidth + gap), cardY, cardWidth, 52,
                    "EMPRESTADO", summary.loaned(), PRIMARY, ReportIcon.MONEY);
            summaryCard(stream, horizontalMargin + (cardWidth + gap) * 2, cardY, cardWidth, 52,
                    "RECEBIDO", summary.received(), RECEIVED, ReportIcon.RECEIVED);
            summaryCard(stream, horizontalMargin + (cardWidth + gap) * 3, cardY, cardWidth, 52,
                    "A RECEBER", summary.receivable(), RECEIVABLE, ReportIcon.RECEIVABLE);
            summaryCard(stream, horizontalMargin + (cardWidth + gap) * 4, cardY, cardWidth, 52,
                    "EM ATRASO", summary.overdue(), ERROR, ReportIcon.OVERDUE);
            summaryCard(stream, horizontalMargin + (cardWidth + gap) * 5, cardY, cardWidth, 52,
                    "LUCRO", summary.profit(), PROFIT, ReportIcon.PROFIT);

            float panelGap = 9;
            float firstPanelWidth = 278;
            float otherPanelWidth = (PAGE_WIDTH - horizontalMargin * 2
                    - firstPanelWidth - panelGap * 2) / 2;
            float firstPanelX = horizontalMargin;
            float secondPanelX = firstPanelX + firstPanelWidth + panelGap;
            float thirdPanelX = secondPanelX + otherPanelWidth + panelGap;
            float panelY = 176;
            float panelHeight = 250;

            roundedCard(stream, firstPanelX, panelY, firstPanelWidth, panelHeight, SURFACE);
            text(stream, "INDICADORES DA OPERAÇÃO", bold, 10, TEXT, firstPanelX + 14, 407);
            text(stream, "Posição atual da região", regular, 7.2f,
                    TEXT_SECONDARY, firstPanelX + 14, 394);
            float metricGap = 5;
            float metricWidth = (firstPanelWidth - 28 - metricGap) / 2;
            float metricX1 = firstPanelX + 14;
            float metricX2 = metricX1 + metricWidth + metricGap;
            float metricHeight = 34;
            float metricRowGap = 4;
            float metricTop = 380;
            metric(stream, metricX1, metricTop - metricHeight, metricWidth, metricHeight,
                    "Recebido hoje", currency(metrics.receivedTodayAmount()), PRIMARY,
                    ReportIcon.RECEIVED);
            metric(stream, metricX2, metricTop - metricHeight, metricWidth, metricHeight,
                    "Pagamentos hoje", metrics.receivedTodayPayments(), PRIMARY_DARK,
                    ReportIcon.PAYMENTS);
            float secondRow = metricTop - (metricHeight + metricRowGap) - metricHeight;
            metric(stream, metricX1, secondRow, metricWidth, metricHeight,
                    "Lucro hoje", currency(metrics.profitTodayAmount()), PROFIT, ReportIcon.PROFIT);
            metric(stream, metricX2, secondRow, metricWidth, metricHeight,
                    "Quitados hoje", metrics.settledTodayLoans(), WARNING, ReportIcon.SETTLED);
            float thirdRow = secondRow - metricHeight - metricRowGap;
            metric(stream, metricX1, thirdRow, metricWidth, metricHeight,
                    "Renovados hoje", metrics.renewedTodayLoans(), RECEIVED, ReportIcon.RENEWED);
            metric(stream, metricX2, thirdRow, metricWidth, metricHeight,
                    "Clientes atrasados", metrics.overdueClients(), ERROR, ReportIcon.CLIENTS);
            float fourthRow = thirdRow - metricHeight - metricRowGap;
            metric(stream, metricX1, fourthRow, metricWidth, metricHeight,
                    "Empréstimos atrasados", metrics.overdueLoans(), ERROR, ReportIcon.OVERDUE);
            metric(stream, metricX2, fourthRow, metricWidth, metricHeight,
                    "Parcelas atrasadas", metrics.overdueInstallments(), WARNING,
                    ReportIcon.INSTALLMENTS);
            float fifthRow = fourthRow - metricHeight - metricRowGap;
            metric(stream, metricX1, fifthRow, firstPanelWidth - 28, metricHeight,
                    "Valor em atraso", currency(metrics.overdueAmount()), PROFIT,
                    ReportIcon.MONEY);

            roundedCard(stream, secondPanelX, panelY, otherPanelWidth, panelHeight, SURFACE);
            text(stream, "EMPRÉSTIMOS POR SITUAÇÃO", bold, 10, TEXT, secondPanelX + 14, 407);
            text(stream, "Quantidade, percentual e valor", regular, 7.2f,
                    TEXT_SECONDARY, secondPanelX + 14, 394);
            BufferedImage donut = donutChart(loanStatus, 1000, 680);
            PDImageXObject donutImage = LosslessFactory.createFromImage(document, donut);
            stream.drawImage(donutImage, secondPanelX + 8, 190, otherPanelWidth - 16, 180);

            roundedCard(stream, thirdPanelX, panelY, otherPanelWidth, panelHeight, SURFACE);
            text(stream, "CLIENTES POR SITUAÇÃO", bold, 10, TEXT, thirdPanelX + 14, 407);
            text(stream, "Distribuição atual da região", regular, 7.2f,
                    TEXT_SECONDARY, thirdPanelX + 14, 394);
            BufferedImage bars = clientBarChart(clientStatus, 1000, 680);
            PDImageXObject barImage = LosslessFactory.createFromImage(document, bars);
            stream.drawImage(barImage, thirdPanelX + 8, 190, otherPanelWidth - 16, 180);

            drawGoalCards(stream, goals, horizontalMargin, 42,
                    PAGE_WIDTH - horizontalMargin * 2, 123, panelGap);
            footer(stream);
        }
    }

    private void drawGoalCards(
            PDPageContentStream stream,
            List<FinancialGoalResponse> goals,
            float x,
            float y,
            float width,
            float height,
            float gap) throws IOException {
        List<FinancialGoalResponse> visibleGoals = goals == null
                ? List.of()
                : goals.stream().limit(3).toList();
        int visibleCards = Math.max(1, visibleGoals.size());
        float cardWidth = (width - gap * (visibleCards - 1)) / visibleCards;
        for (int index = 0; index < visibleCards; index++) {
            float cardX = x + index * (cardWidth + gap);
            FinancialGoalResponse goal = visibleGoals.isEmpty()
                    ? null : visibleGoals.get(index);
            roundedCard(stream, cardX, y, cardWidth, height, SURFACE);
            goalCard(stream, goal, cardX + 12, y + 12, cardWidth - 24, height - 24);
        }
    }

    private void goalCard(
            PDPageContentStream stream,
            FinancialGoalResponse goal,
            float x,
            float y,
            float width,
            float height) throws IOException {
        Color accent = goal == null ? PRIMARY : goalColor(goal);
        String title = goal == null
                ? "META FINANCEIRA"
                : "META FINANCEIRA - " + goalTypeLabel(goal).toUpperCase(BRAZIL);
        text(stream, title, bold, 10, TEXT, x, y + height - 5);
        if (goal == null) {
            fill(stream, PRIMARY_PALE, x, y + 47, 34, 34);
            text(stream, "$", bold, 18, PRIMARY_DARK, x + 11, y + 57);
            text(stream, "Nenhuma meta ativa", bold, 10, TEXT, x + 44, y + 69);
            text(stream, "Cadastre uma meta no Money para", regular, 7.5f,
                    TEXT_SECONDARY, x + 44, y + 54);
            text(stream, "acompanhar o progresso da região.", regular, 7.5f,
                    TEXT_SECONDARY, x + 44, y + 42);
            return;
        }
        text(stream, DATE.format(goal.startDate()) + " até " + DATE.format(goal.endDate()),
                regular, 7.5f, TEXT_SECONDARY, x, y + height - 20);
        text(stream, goal.type().name().replace('_', ' '), bold, 7.5f,
                accent, x, y + height - 35);
        float valueWidth = width / 3;
        goalValue(stream, x, y + 37, "META", goal.targetAmount());
        goalValue(stream, x + valueWidth, y + 37, "ALCANÇADO", goal.achievedAmount());
        goalValue(stream, x + valueWidth * 2, y + 37, "RESTANTE", goal.remainingAmount());
        String percent = percentage(goal.percentage()) + "%";
        textRight(stream, percent, bold, 15, accent, x + width, y + 24);
        fill(stream, DIVIDER, x, y + 8, width, 7);
        float progress = goal.percentage() == null
                ? 0
                : (float) Math.max(0, Math.min(1, goal.percentage().doubleValue() / 100));
        fill(stream, accent, x, y + 8, width * progress, 7);
    }

    private Color goalColor(FinancialGoalResponse goal) {
        return switch (goal.type()) {
            case EMPRESTADO -> PRIMARY;
            case RECEBIDO -> RECEIVED;
            case LUCRO -> PROFIT;
            default -> PRIMARY;
        };
    }

    private String goalTypeLabel(FinancialGoalResponse goal) {
        return switch (goal.type()) {
            case EMPRESTADO -> "Emprestado";
            case RECEBIDO -> "Recebido";
            case LUCRO -> "Lucro";
            case CLIENTES_ATIVOS -> "Novos clientes ativos";
            case CLIENTES_EM_DIA -> "Clientes em dia";
            case CLIENTES_ATRASO -> "Clientes em atraso";
        };
    }

    private void goalValue(
            PDPageContentStream stream,
            float x,
            float y,
            String label,
            BigDecimal value)
            throws IOException {
        text(stream, label, regular, 6.5f, TEXT_SECONDARY, x, y + 14);
        String formatted = currency(value);
        text(stream, formatted, bold, formatted.length() > 16 ? 7 : 8.5f, TEXT, x, y);
    }

    private BufferedImage donutChart(ChatLoanStatusResponse status, int width, int height) {
        BufferedImage image = canvas(width, height);
        Graphics2D graphics = graphics(image);
        long[] counts = {
            status.overdueCount(), status.onTimeCount(), status.settledCount()
        };
        BigDecimal[] amounts = {
            status.overdueAmount(), status.onTimeAmount(), status.settledAmount()
        };
        String[] labels = {"Atrasados", "Em dia", "Quitados"};
        Color[] colors = {ERROR, PRIMARY, TEXT};
        long total = 0;
        for (long count : counts) total += count;
        int diameter = 430;
        int x = 30;
        int y = 122;
        graphics.setStroke(new BasicStroke(72, BasicStroke.CAP_BUTT, BasicStroke.JOIN_ROUND));
        if (total == 0) {
            graphics.setColor(DIVIDER);
            graphics.draw(new Arc2D.Double(x, y, diameter, diameter, 0, 360, Arc2D.OPEN));
        } else {
            double start = 90;
            for (int index = 0; index < counts.length; index++) {
                if (counts[index] == 0) continue;
                double sweep = 360.0 * counts[index] / total;
                graphics.setColor(colors[index]);
                graphics.draw(new Arc2D.Double(x, y, diameter, diameter, start, -sweep, Arc2D.OPEN));
                start -= sweep;
            }
        }
        graphics.setFont(new Font("SansSerif", Font.BOLD, 58));
        graphics.setColor(TEXT);
        centered(graphics, Long.toString(total), x + diameter / 2, y + diameter / 2 + 5);
        graphics.setFont(new Font("SansSerif", Font.PLAIN, 23));
        graphics.setColor(TEXT_SECONDARY);
        centered(graphics, "empréstimos", x + diameter / 2, y + diameter / 2 + 35);

        graphics.setFont(new Font("SansSerif", Font.PLAIN, 24));
        int legendX = 520;
        for (int index = 0; index < labels.length; index++) {
            int rowY = 125 + index * 150;
            graphics.setColor(colors[index]);
            graphics.fillRoundRect(legendX, rowY, 16, 66, 8, 8);
            graphics.setColor(TEXT_SECONDARY);
            graphics.drawString(labels[index], legendX + 34, rowY + 24);
            graphics.setFont(new Font("SansSerif", Font.BOLD, 27));
            int percent = total == 0 ? 0 : (int) Math.round(counts[index] * 100.0 / total);
            graphics.setColor(TEXT);
            graphics.drawString(counts[index] + "  •  " + percent + "%", legendX + 34, rowY + 58);
            graphics.setFont(new Font("SansSerif", Font.PLAIN, 21));
            graphics.setColor(TEXT_SECONDARY);
            graphics.drawString(currency(amounts[index]), legendX + 235, rowY + 58);
            graphics.setFont(new Font("SansSerif", Font.PLAIN, 24));
        }
        graphics.dispose();
        return image;
    }

    private BufferedImage clientBarChart(ChatClientStatusResponse status, int width, int height) {
        BufferedImage image = canvas(width, height);
        Graphics2D graphics = graphics(image);
        long[] counts = {status.activeCount(), status.withoutLoansCount(), status.missingCount()};
        String[] labels = {"Ativos", "Sem empréstimos", "Desaparecido"};
        Color[] colors = {PRIMARY, NEUTRAL, ERROR};
        long maximum = Math.max(1, Math.max(counts[0], Math.max(counts[1], counts[2])));
        int baseline = 570;
        int chartTop = 105;
        int slot = width / 3;
        graphics.setColor(DIVIDER);
        graphics.setStroke(new BasicStroke(2));
        graphics.drawLine(45, baseline, width - 35, baseline);
        for (int index = 0; index < counts.length; index++) {
            int barWidth = 145;
            int heightValue = (int) ((baseline - chartTop) * counts[index] / (double) maximum);
            int x = slot * index + (slot - barWidth) / 2;
            graphics.setColor(colors[index]);
            graphics.fillRoundRect(x, baseline - heightValue, barWidth, heightValue, 24, 24);
            graphics.setFont(new Font("SansSerif", Font.BOLD, 38));
            graphics.setColor(TEXT);
            centered(graphics, Long.toString(counts[index]), x + barWidth / 2, baseline - heightValue - 18);
            graphics.setFont(new Font("SansSerif", Font.BOLD, 22));
            graphics.setColor(TEXT_SECONDARY);
            centered(graphics, labels[index], x + barWidth / 2, baseline + 35);
        }
        graphics.dispose();
        return image;
    }

    private BufferedImage canvas(int width, int height) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setComposite(java.awt.AlphaComposite.Clear);
        graphics.fillRect(0, 0, width, height);
        graphics.dispose();
        return image;
    }

    private Graphics2D graphics(BufferedImage image) {
        Graphics2D graphics = image.createGraphics();
        graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        graphics.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        return graphics;
    }

    private void centered(Graphics2D graphics, String value, int centerX, int baseline) {
        int width = graphics.getFontMetrics().stringWidth(value);
        graphics.drawString(value, centerX - width / 2, baseline);
    }

    private void summaryCard(
            PDPageContentStream stream,
            float x,
            float y,
            float width,
            float height,
            String label,
            Object value,
            Color accent,
            ReportIcon icon) throws IOException {
        roundedCard(stream, x, y, width, height, SURFACE);
        drawIconBadge(stream, x + 7, y + 9, 34, accent, icon);
        text(stream, label, regular, 6.3f, TEXT, x + 49, y + 33);
        String displayed = display(value);
        float valueSize = fitFontSize(bold, displayed, 10.8f, 7.2f, width - 56);
        text(stream, displayed, bold, valueSize, accent, x + 49, y + 15);
    }

    private void metric(
            PDPageContentStream stream,
            float x,
            float y,
            float width,
            float height,
            String label,
            Object value,
            Color accent,
            ReportIcon icon) throws IOException {
        fillRounded(stream, new Color(0xFBFCFD), x, y, width, height, 3);
        strokeRounded(stream, new Color(0xEEF1F4), x, y, width, height, 3);
        drawIconBadge(stream, x + 6, y + 6, 22, accent, icon);
        text(stream, fit(label, 24), regular, 6.2f, TEXT_SECONDARY, x + 34, y + 21);
        String displayed = display(value);
        float valueSize = fitFontSize(bold, displayed, 9.2f, 6.8f, width - 41);
        text(stream, displayed, bold, valueSize, TEXT, x + 34, y + 8);
    }

    private void roundedCard(
            PDPageContentStream stream,
            float x,
            float y,
            float width,
            float height,
            Color color) throws IOException {
        fillRounded(stream, SHADOW, x + .8f, y - 1.2f, width, height, 5);
        fillRounded(stream, color, x, y, width, height, 5);
        strokeRounded(stream, DIVIDER, x, y, width, height, 5);
    }

    private void periodPill(
            PDPageContentStream stream,
            String value,
            float x,
            float y) throws IOException {
        float width = Math.min(226, 34 + textWidth(regular, value, 8.2f));
        fillRounded(stream, new Color(0x0B573E), x, y, width, 18, 9);
        strokeRounded(stream, new Color(0x5D9B7E), x, y, width, 18, 9);
        stream.setStrokingColor(new Color(0xDDEEE4));
        stream.setLineWidth(.9f);
        stream.addRect(x + 8, y + 5, 8, 8);
        stream.stroke();
        stream.moveTo(x + 10, y + 15);
        stream.lineTo(x + 10, y + 12);
        stream.moveTo(x + 14, y + 15);
        stream.lineTo(x + 14, y + 12);
        stream.stroke();
        text(stream, fit(value, 48), regular, 8.2f, Color.WHITE, x + 22, y + 5.2f);
    }

    private void drawIconBadge(
            PDPageContentStream stream,
            float x,
            float y,
            float size,
            Color color,
            ReportIcon icon) throws IOException {
        fillRounded(stream, color, x, y, size, size, Math.max(3, size * .18f));
        float left = x + size * .25f;
        float right = x + size * .75f;
        float bottom = y + size * .24f;
        float top = y + size * .76f;
        float centerX = x + size / 2;
        float centerY = y + size / 2;
        stream.setStrokingColor(Color.WHITE);
        stream.setLineWidth(Math.max(.8f, size * .045f));
        switch (icon) {
            case MONEY, RECEIVED -> {
                circlePath(stream, centerX, centerY, size * .23f);
                stream.stroke();
                text(stream, "$", bold, size * .31f, Color.WHITE,
                        centerX - size * .095f, centerY - size * .105f);
            }
            case PROFIT -> {
                stream.moveTo(left, bottom + size * .05f);
                stream.lineTo(centerX - size * .06f, centerY - size * .04f);
                stream.lineTo(centerX + size * .07f, centerY + size * .08f);
                stream.lineTo(right, top);
                stream.stroke();
                stream.moveTo(right - size * .15f, top);
                stream.lineTo(right, top);
                stream.lineTo(right, top - size * .15f);
                stream.stroke();
            }
            case RECEIVABLE, OVERDUE -> {
                circlePath(stream, centerX, centerY, size * .24f);
                stream.stroke();
                stream.moveTo(centerX, centerY);
                stream.lineTo(centerX, centerY + size * .14f);
                stream.moveTo(centerX, centerY);
                stream.lineTo(centerX + size * .12f, centerY - size * .06f);
                stream.stroke();
                if (icon == ReportIcon.OVERDUE) {
                    text(stream, "!", bold, size * .20f, Color.WHITE,
                            right - size * .02f, bottom - size * .01f);
                }
            }
            case SETTLED -> {
                circlePath(stream, centerX, centerY, size * .24f);
                stream.stroke();
                stream.moveTo(left + size * .03f, centerY);
                stream.lineTo(centerX - size * .04f, bottom + size * .08f);
                stream.lineTo(right + size * .02f, top - size * .04f);
                stream.stroke();
            }
            case RENEWED -> {
                stream.moveTo(left, centerY + size * .08f);
                stream.lineTo(centerX - size * .06f, top);
                stream.lineTo(right, centerY + size * .08f);
                stream.stroke();
                stream.moveTo(right, centerY - size * .08f);
                stream.lineTo(centerX + size * .06f, bottom);
                stream.lineTo(left, centerY - size * .08f);
                stream.stroke();
            }
            case CLIENTS -> {
                circlePath(stream, centerX - size * .10f, top - size * .09f, size * .10f);
                circlePath(stream, centerX + size * .15f, top - size * .12f, size * .08f);
                stream.stroke();
                stream.moveTo(left, bottom);
                stream.curveTo(left, centerY, centerX, centerY, centerX, bottom);
                stream.moveTo(centerX + size * .04f, bottom);
                stream.curveTo(centerX + size * .04f, centerY - size * .03f,
                        right, centerY - size * .03f, right, bottom);
                stream.stroke();
            }
            case PAYMENTS -> {
                stream.addRect(left, bottom + size * .06f, right - left, top - bottom - size * .12f);
                stream.moveTo(left, top - size * .16f);
                stream.lineTo(right, top - size * .16f);
                stream.moveTo(left + size * .08f, bottom + size * .17f);
                stream.lineTo(right - size * .08f, bottom + size * .17f);
                stream.stroke();
            }
            case LOANS, INSTALLMENTS -> {
                stream.addRect(left, bottom, right - left, top - bottom);
                stream.moveTo(left + size * .08f, top - size * .14f);
                stream.lineTo(right - size * .08f, top - size * .14f);
                stream.moveTo(left + size * .08f, centerY);
                stream.lineTo(right - size * .08f, centerY);
                stream.moveTo(left + size * .08f, bottom + size * .13f);
                stream.lineTo(right - size * .08f, bottom + size * .13f);
                stream.stroke();
            }
        }
    }

    private void circlePath(
            PDPageContentStream stream,
            float centerX,
            float centerY,
            float radius) throws IOException {
        float control = radius * .55228475f;
        stream.moveTo(centerX + radius, centerY);
        stream.curveTo(centerX + radius, centerY + control,
                centerX + control, centerY + radius, centerX, centerY + radius);
        stream.curveTo(centerX - control, centerY + radius,
                centerX - radius, centerY + control, centerX - radius, centerY);
        stream.curveTo(centerX - radius, centerY - control,
                centerX - control, centerY - radius, centerX, centerY - radius);
        stream.curveTo(centerX + control, centerY - radius,
                centerX + radius, centerY - control, centerX + radius, centerY);
        stream.closePath();
    }

    private void fillRounded(
            PDPageContentStream stream,
            Color color,
            float x,
            float y,
            float width,
            float height,
            float radius) throws IOException {
        stream.setNonStrokingColor(color);
        roundedPath(stream, x, y, width, height, radius);
        stream.fill();
    }

    private void strokeRounded(
            PDPageContentStream stream,
            Color color,
            float x,
            float y,
            float width,
            float height,
            float radius) throws IOException {
        stream.setStrokingColor(color);
        stream.setLineWidth(.55f);
        roundedPath(stream, x, y, width, height, radius);
        stream.stroke();
    }

    private void roundedPath(
            PDPageContentStream stream,
            float x,
            float y,
            float width,
            float height,
            float radius) throws IOException {
        float r = Math.max(0, Math.min(radius, Math.min(width, height) / 2));
        float control = r * .55228475f;
        stream.moveTo(x + r, y);
        stream.lineTo(x + width - r, y);
        stream.curveTo(x + width - r + control, y, x + width, y + r - control, x + width, y + r);
        stream.lineTo(x + width, y + height - r);
        stream.curveTo(x + width, y + height - r + control,
                x + width - r + control, y + height, x + width - r, y + height);
        stream.lineTo(x + r, y + height);
        stream.curveTo(x + r - control, y + height, x, y + height - r + control, x, y + height - r);
        stream.lineTo(x, y + r);
        stream.curveTo(x, y + r - control, x + r - control, y, x + r, y);
        stream.closePath();
    }

    private void fill(
            PDPageContentStream stream,
            Color color,
            float x,
            float y,
            float width,
            float height) throws IOException {
        stream.setNonStrokingColor(color);
        stream.addRect(x, y, width, height);
        stream.fill();
    }

    private void stroke(
            PDPageContentStream stream,
            Color color,
            float x,
            float y,
            float width,
            float height) throws IOException {
        stream.setStrokingColor(color);
        stream.setLineWidth(.6f);
        stream.addRect(x, y, width, height);
        stream.stroke();
    }

    private void text(
            PDPageContentStream stream,
            String value,
            PDType1Font font,
            float size,
            Color color,
            float x,
            float y) throws IOException {
        stream.beginText();
        stream.setFont(font, size);
        stream.setNonStrokingColor(color);
        stream.newLineAtOffset(x, y);
        stream.showText(value == null ? "" : value);
        stream.endText();
    }

    private void textRight(
            PDPageContentStream stream,
            String value,
            PDType1Font font,
            float size,
            Color color,
            float right,
            float y) throws IOException {
        text(stream, value, font, size, color, right - textWidth(font, value, size), y);
    }

    private float textWidth(PDType1Font font, String value, float size) throws IOException {
        String safe = value == null ? "" : value;
        return font.getStringWidth(safe) / 1000f * size;
    }

    private float fitFontSize(
            PDType1Font font,
            String value,
            float maximum,
            float minimum,
            float availableWidth) throws IOException {
        float size = maximum;
        while (size > minimum && textWidth(font, value, size) > availableWidth) {
            size -= .25f;
        }
        return Math.max(minimum, size);
    }

    private void footer(PDPageContentStream stream) throws IOException {
        float y = 18;
        circlePath(stream, 29, y + 2.5f, 4.5f);
        stream.setStrokingColor(DIVIDER);
        stream.setLineWidth(.8f);
        stream.stroke();
        text(stream, "i", bold, 6.5f, TEXT_SECONDARY, 28.2f, y + .2f);
        text(stream, "Money - Inteligência financeira", regular, 7.2f,
                TEXT_SECONDARY, 38, y);

        float generatedX = PAGE_WIDTH / 2 - 49;
        stream.setStrokingColor(TEXT_SECONDARY);
        stream.setLineWidth(.7f);
        stream.addRect(generatedX, y - .5f, 7, 7);
        stream.stroke();
        text(stream, "Gerado em " + DATE.format(LocalDate.now(BUSINESS_ZONE)), regular, 7.2f,
                TEXT_SECONDARY, generatedX + 12, y);

        String page = "Página 1 de 1";
        float pageWidth = textWidth(regular, page, 7.2f);
        float pageX = PAGE_WIDTH - 24 - pageWidth;
        stream.setStrokingColor(TEXT_SECONDARY);
        stream.addRect(pageX - 12, y - .5f, 7, 8);
        stream.stroke();
        text(stream, page, regular, 7.2f, TEXT_SECONDARY, pageX, y);
    }

    private byte[] requiredAsset(String name) {
        java.nio.file.Path path = assetsDirectory.resolve(name).normalize();
        if (!path.startsWith(assetsDirectory)) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Imagem do relatório inválida.");
        }
        try {
            return java.nio.file.Files.readAllBytes(path);
        } catch (IOException exception) {
            throw new ApiException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "A imagem " + name + " não está disponível no servidor.");
        }
    }

    private void validatePeriod(LocalDate startDate, LocalDate endDate) {
        if ((startDate == null) != (endDate == null)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o período completo do resumo.");
        }
        if (startDate != null && startDate.isAfter(endDate)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "O período do resumo é inválido.");
        }
    }

    private String periodLabel(LocalDate startDate, LocalDate endDate) {
        if (startDate == null) return "Período geral";
        return "Período: " + DATE.format(startDate) + " até " + DATE.format(endDate);
    }

    private String display(Object value) {
        if (value instanceof BigDecimal decimal) return currency(decimal);
        return value == null ? "-" : value.toString();
    }

    private static String currency(BigDecimal value) {
        return NumberFormat.getCurrencyInstance(BRAZIL)
                .format(value == null ? BigDecimal.ZERO : value);
    }

    private static String percentage(BigDecimal value) {
        return value == null ? "0" : value.setScale(0, java.math.RoundingMode.HALF_UP).toPlainString();
    }

    private static String fit(String value, int maximum) {
        String clean = value == null ? "" : value.trim();
        if (clean.length() <= maximum) return clean;
        return clean.substring(0, Math.max(0, maximum - 3)) + "...";
    }

    private static String safeName(String value) {
        String clean = java.text.Normalizer.normalize(value, java.text.Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "")
                .toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "_")
                .replaceAll("^_+|_+$", "");
        return clean.isBlank() ? "regiao" : clean;
    }
}
