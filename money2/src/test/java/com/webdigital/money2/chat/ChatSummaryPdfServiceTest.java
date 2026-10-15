package com.webdigital.money2.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.dashboard.DashboardModels.Metrics;
import com.webdigital.money2.dashboard.DashboardRepository;
import com.webdigital.money2.goals.FinancialGoalResponse;
import com.webdigital.money2.goals.FinancialGoalStatus;
import com.webdigital.money2.goals.FinancialGoalType;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.LocalDate;
import java.util.List;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ChatSummaryPdfServiceTest {

    @TempDir
    Path assetsDirectory;

    @Test
    void generatesSingleLandscapeOverviewWithEverySection() throws Exception {
        createLogo(assetsDirectory.resolve("moneybr.png"));
        ChatRepository chatRepository = mock(ChatRepository.class);
        DashboardRepository dashboardRepository = mock(DashboardRepository.class);
        UserAccount user = mock(UserAccount.class);
        when(user.getId()).thenReturn(7L);
        when(chatRepository.accessibleRegions(7L))
                .thenReturn(List.of(new ChatRegionOption(12L, "ALPHACRED")));

        LocalDate start = LocalDate.of(2026, 7, 22);
        LocalDate end = LocalDate.of(2026, 8, 20);
        when(chatRepository.summary(7L, 12L, start, end)).thenReturn(
                new ChatFinancialSummaryResponse(
                        234,
                        72,
                        money("59647.00"),
                        money("66004.38"),
                        money("72364.70"),
                        money("207.00"),
                        money("21453.64")));
        when(chatRepository.loanStatus(7L, 12L, start, end)).thenReturn(
                new ChatLoanStatusResponse(
                        2, money("207.00"),
                        70, money("70874.70"),
                        16, money("8200.00")));
        when(chatRepository.clientStatus(7L, 12L))
                .thenReturn(new ChatClientStatusResponse(120, 114, 0));
        when(chatRepository.activeFinancialGoals(7L, 12L)).thenReturn(List.of(
                goal(1L, FinancialGoalType.EMPRESTADO, "10000", "3500", "6500", "35"),
                goal(2L, FinancialGoalType.LUCRO, "100000", "35966.72", "64033.28", "36"),
                goal(3L, FinancialGoalType.RECEBIDO, "60000", "3295", "56705", "5")));
        when(dashboardRepository.metrics(7L, 12L)).thenReturn(new Metrics(
                17,
                17,
                money("5216.10"),
                money("3265.00"),
                91,
                money("236.00"),
                6,
                0,
                103,
                30,
                0,
                0,
                BigDecimal.ZERO));

        ChatSummaryPdfService service = new ChatSummaryPdfService(
                chatRepository, dashboardRepository, assetsDirectory.toString());
        ChatSummaryPdfResult result = service.generate(user, 12L, start, end);

        assertThat(result.bytes()).hasSizeGreaterThan(25_000);
        try (PDDocument document = Loader.loadPDF(result.bytes())) {
            assertThat(document.getNumberOfPages()).isEqualTo(1);
            assertThat(document.getPage(0).getMediaBox().getWidth())
                    .isGreaterThan(document.getPage(0).getMediaBox().getHeight());
            String text = new PDFTextStripper().getText(document);
            assertThat(text).contains(
                    "RESUMO FINANCEIRO",
                    "INDICADORES DA OPERAÇÃO",
                    "EMPRÉSTIMOS POR SITUAÇÃO",
                    "CLIENTES POR SITUAÇÃO",
                    "META FINANCEIRA - EMPRESTADO",
                    "META FINANCEIRA - LUCRO",
                    "META FINANCEIRA - RECEBIDO",
                    "Página 1 de 1");
            writeQaArtifacts(result.bytes(), document);
        }
    }

    private void writeQaArtifacts(byte[] pdf, PDDocument document) throws IOException {
        String configured = System.getProperty("money.pdf.qa-dir", "").trim();
        if (configured.isEmpty()) return;
        Path directory = Path.of(configured).toAbsolutePath().normalize();
        Files.createDirectories(directory);
        Files.write(directory.resolve("resumo-financeiro-referencia.pdf"), pdf);
        BufferedImage page = new PDFRenderer(document)
                .renderImageWithDPI(0, 180, ImageType.RGB);
        ImageIO.write(page, "png", directory.resolve("resumo-financeiro-referencia.png").toFile());
    }

    private void createLogo(Path path) throws IOException {
        String configured = System.getProperty("money.pdf.qa-logo", "").trim();
        if (!configured.isEmpty()) {
            Files.copy(Path.of(configured), path, StandardCopyOption.REPLACE_EXISTING);
            return;
        }
        BufferedImage image = new BufferedImage(600, 180, BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        graphics.setColor(Color.WHITE);
        graphics.setFont(new Font("Serif", Font.BOLD, 108));
        graphics.drawString("$Money", 18, 125);
        graphics.dispose();
        ImageIO.write(image, "png", path.toFile());
    }

    private FinancialGoalResponse goal(
            long id,
            FinancialGoalType type,
            String target,
            String achieved,
            String remaining,
            String percentage) {
        return new FinancialGoalResponse(
                id,
                12L,
                "ALPHACRED",
                type,
                money(target),
                money(achieved),
                money(remaining),
                money(percentage),
                LocalDate.of(2026, 8, 20),
                LocalDate.of(2026, 9, 19),
                FinancialGoalStatus.ATIVA,
                null,
                null,
                true,
                List.of(12L),
                List.of("ALPHACRED"));
    }

    private static BigDecimal money(String value) {
        return new BigDecimal(value);
    }
}
