package com.webdigital.money2.integrations;

import com.fasterxml.jackson.databind.JsonNode;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.integrations.IntegrationModels.ActionResult;
import com.webdigital.money2.integrations.IntegrationModels.BankAccount;
import com.webdigital.money2.integrations.IntegrationModels.BankAccountRequest;
import com.webdigital.money2.integrations.IntegrationModels.SicrediConfigRequest;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappConfig;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappConfigRequest;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappDevice;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappLog;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappSecret;
import com.webdigital.money2.shared.ApiException;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.text.NumberFormat;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
public class IntegrationService {

    private static final String BASE_URL = WebDigitalWhatsappClient.BASE_URL;
    private static final String OVERDUE_DEFAULT = "Olá, {nome_cliente}.\n\nSeu contrato {contrato} possui {qtd_parcelas} {texto_parcelas} em atraso desde {primeiro_vencimento}{dias_atraso_texto}.\nParcelas em atraso: {parcelas_atraso}.\nValor devedor das parcelas: {valor_devedor}.\nJuros do contrato já incluídos: {juros_contrato}.\nJuros/multa por atraso até hoje: {juros_atraso}.\nTotal atualizado para pagamento hoje: {valor_total_atualizado}.\n\nResponda com uma opção:\n1 - Quero pagar hoje\n2 - Preciso negociar uma data\n3 - Quero falar com um atendente";
    private static final String DUE_TODAY_DEFAULT = "Olá, {nome_cliente}. A parcela {parcela} do contrato {contrato} vence hoje ({vencimento}). Valor pendente: {valor_pendente}.";
    private static final String MISSING_DEFAULT = "Olá, {nome_cliente}. Precisamos atualizar seu contato referente ao contrato {contrato}. Entre em contato para regularização.";
    private static final String ACQUISITION_DEFAULT = "Olá, {nome_cliente}. Temos uma nova condição de empréstimo disponível para você. Caso tenha interesse, responda esta mensagem.";
    private static final String PIX_DEFAULT = "Segue abaixo o PIX para pagamento. Basta copiar e realizar o pagamento.";
    private static final String PIX_RECEIVED_DEFAULT = "Olá, {nome_cliente}. Recebemos seu pagamento via PIX no valor de {valor_pix}, referente ao contrato {contrato}. Obrigado!";
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final NumberFormat CURRENCY = NumberFormat.getCurrencyInstance(new Locale("pt", "BR"));

    private final IntegrationRepository repository;
    private final WebDigitalWhatsappClient whatsappClient;
    private final SicrediMtlsClientFactory mtlsClientFactory;
    private final Path certificateDirectory;
    private final ExecutorService dispatchExecutor = Executors.newFixedThreadPool(2);

    public IntegrationService(
            IntegrationRepository repository,
            WebDigitalWhatsappClient whatsappClient,
            SicrediMtlsClientFactory mtlsClientFactory,
            @Value("${money.integrations.sicredi-storage-path:/home/money/money2/data/sicredi/certificados}")
            String certificateDirectory) {
        this.repository = repository;
        this.whatsappClient = whatsappClient;
        this.mtlsClientFactory = mtlsClientFactory;
        this.certificateDirectory = Path.of(certificateDirectory).toAbsolutePath().normalize();
    }

    @PostConstruct
    void recoverInterruptedDispatches() {
        repository.clearInterruptedDispatches();
    }

    @PreDestroy
    void shutdown() {
        dispatchExecutor.shutdownNow();
    }

    public List<BankAccount> bankAccounts(UserAccount user) {
        requireAdministrator(user);
        return repository.bankAccounts();
    }

    @Transactional
    public BankAccount createBank(UserAccount user, BankAccountRequest request) {
        requirePrincipalAdministrator(user);
        String name = required(request == null ? null : request.name(), "Informe o nome da conta bancária.");
        long id = repository.createBank(name);
        repository.replaceBankRegions(id, normalizedIds(request.regionIds()));
        return repository.requireBank(id);
    }

    @Transactional
    public BankAccount updateBank(UserAccount user, long id, BankAccountRequest request) {
        requireAdministrator(user);
        repository.requireBank(id);
        if (request != null && request.name() != null) {
            requirePrincipalAdministrator(user);
            repository.updateBankName(id, required(request.name(), "Informe o nome da conta bancária."));
        }
        if (request != null && request.regionIds() != null) {
            repository.replaceBankRegions(id, normalizedIds(request.regionIds()));
        }
        return repository.requireBank(id);
    }

    public BankAccount bank(UserAccount user, long id) {
        requireAdministrator(user);
        return repository.requireBank(id);
    }

    @Transactional
    public BankAccount saveSicredi(
            UserAccount user, long id, SicrediConfigRequest request) {
        requirePrincipalAdministrator(user);
        repository.requireBank(id);
        if (request == null) throw new ApiException(HttpStatus.BAD_REQUEST, "Informe a configuração Sicredi.");
        IntegrationRepository.BankCredentials current = repository.bankCredentials(id);
        String clientId = keepSecret(request.clientId(), current.clientId());
        String clientSecret = keepSecret(request.clientSecret(), current.clientSecret());
        String pixKey = keepSecret(request.pixKey(), current.pixKey());
        if (request.active() && (clientId == null || clientSecret == null || pixKey == null
                || current.certificatePath() == null || current.privateKeyPath() == null)) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Preencha as credenciais, o certificado .CER e a chave privada .KEY antes de ativar.");
        }
        repository.updateSicredi(id, request.active(), clientId, clientSecret, pixKey);
        return repository.requireBank(id);
    }

    @Transactional
    public BankAccount uploadSicrediFiles(
            UserAccount user,
            long id,
            MultipartFile certificate,
            MultipartFile privateKey,
            MultipartFile chain) {
        requirePrincipalAdministrator(user);
        repository.requireBank(id);
        if (empty(certificate) && empty(privateKey) && empty(chain)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Selecione ao menos um arquivo Sicredi.");
        }
        try {
            Files.createDirectories(certificateDirectory);
            StoredUpload cert = store(id, certificate, "certificado", ".cer", Set.of("cer", "crt", "pem"));
            StoredUpload key = store(id, privateKey, "chave-privada", ".key", Set.of("key", "pem"));
            StoredUpload fullChain = store(id, chain, "cadeia", ".cer", Set.of("cer", "crt", "pem"));
            IntegrationRepository.BankCredentials current = repository.bankCredentials(id);
            Path certificatePath = path(first(cert.path(), current.certificatePath()));
            Path privateKeyPath = path(first(key.path(), current.privateKeyPath()));
            Path chainPath = path(first(fullChain.path(), current.chainPath()));
            if (certificatePath != null && privateKeyPath != null) {
                mtlsClientFactory.validate(certificatePath, privateKeyPath, chainPath);
            }
            repository.updateBankFiles(id, new IntegrationRepository.StoredFiles(
                    cert.path(), cert.name(), key.path(), key.name(), fullChain.path(), fullChain.name()));
            return repository.requireBank(id);
        } catch (ApiException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Não foi possível armazenar os certificados Sicredi.");
        }
    }

    public WhatsappConfig whatsappConfig(UserAccount user) {
        requireAdministrator(user);
        return withDefaults(repository.whatsappConfig());
    }

    @Transactional
    public WhatsappConfig saveWhatsappConfig(UserAccount user, WhatsappConfigRequest request) {
        requirePrincipalAdministrator(user);
        if (request == null) throw new ApiException(HttpStatus.BAD_REQUEST, "Informe a configuração do WhatsApp.");
        WhatsappSecret current = repository.whatsappSecret();
        String token = keepSecret(request.apiToken(), current.token());
        if (request.active() && token == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o token da API WebDigital.");
        }
        repository.saveWhatsappConfig(new WhatsappSecret(
                request.active(), token, BASE_URL,
                template(request.overdueMessage(), OVERDUE_DEFAULT),
                template(request.dueTodayMessage(), DUE_TODAY_DEFAULT),
                template(request.missingMessage(), MISSING_DEFAULT),
                template(request.acquisitionMessage(), ACQUISITION_DEFAULT),
                template(request.pixMessage(), PIX_DEFAULT),
                template(request.pixReceivedMessage(), PIX_RECEIVED_DEFAULT)));
        return withDefaults(repository.whatsappConfig());
    }

    public List<WhatsappDevice> devices(UserAccount user) {
        requireAdministrator(user);
        WhatsappSecret configuration = repository.whatsappSecret();
        if (configuration.token() == null) return List.of();
        JsonNode result = whatsappClient.devices(configuration);
        JsonNode data = result.path("data");
        if (!data.isArray()) {
            throw new ApiException(HttpStatus.BAD_GATEWAY, "A WebDigital não retornou a lista de dispositivos.");
        }
        Set<String> remoteIds = new LinkedHashSet<>();
        for (JsonNode remote : data) {
            String remoteId = nullable(remote.path("id").asText(null));
            if (remoteId == null) continue;
            remoteIds.add(remoteId);
            boolean connected = remoteConnected(remote);
            String provider = nullable(remote.path("provider").asText(null));
            boolean pix = remote.path("capabilities").path("pix_copy").asBoolean(
                    "evolution".equalsIgnoreCase(provider));
            repository.upsertRemoteDevice(remoteId,
                    first(remote.path("name").asText(null), "Dispositivo WebDigital"),
                    nullable(remote.path("phone").asText(null)),
                    remoteStatus(remote, connected),
                    provider, connected, pix);
        }
        repository.markMissingRemoteDevicesDisconnected(remoteIds);
        return repository.whatsappDevices(remoteIds);
    }

    public List<WhatsappDevice> deviceProgress(UserAccount user) {
        requireAdministrator(user);
        return repository.whatsappDevices();
    }

    public WhatsappDevice refreshDevice(UserAccount user, long id) {
        requireAdministrator(user);
        WhatsappSecret configuration = requireActiveWhatsapp();
        WhatsappDevice device = repository.requireDevice(id);
        JsonNode remote = whatsappClient.deviceStatus(configuration, required(device.remoteId(),
                "Dispositivo sem vínculo WebDigital.")).path("device");
        if (!remote.isObject()) {
            throw new ApiException(HttpStatus.BAD_GATEWAY, "A WebDigital não retornou o status do dispositivo.");
        }
        boolean connected = remoteConnected(remote);
        String provider = nullable(remote.path("provider").asText(null));
        repository.upsertRemoteDevice(device.remoteId(),
                first(remote.path("name").asText(null), device.name(), "Dispositivo WebDigital"),
                first(remote.path("phone").asText(null), device.phone()),
                remoteStatus(remote, connected),
                provider, connected,
                remote.path("capabilities").path("pix_copy").asBoolean(device.pixCopySupported()));
        return repository.requireDevice(id);
    }

    @Transactional
    public WhatsappDevice updateDeviceRegions(UserAccount user, long id, List<Long> regionIds) {
        requireAdministrator(user);
        boolean currentlyListed = devices(user).stream().anyMatch(device -> device.id() == id);
        if (!currentlyListed) {
            throw new ApiException(HttpStatus.NOT_FOUND,
                    "Este dispositivo não está mais listado na API WebDigital.");
        }
        repository.replaceDeviceRegions(id, normalizedIds(regionIds));
        return repository.requireDevice(id);
    }

    public WhatsappLog sendTest(UserAccount user, long id, String phone) {
        requireAdministrator(user);
        WhatsappSecret configuration = requireActiveWhatsapp();
        WhatsappDevice device = repository.requireDevice(id);
        if (!device.connected()) throw new ApiException(HttpStatus.BAD_REQUEST, "O dispositivo não está conectado.");
        String number = required(phone, "Informe o telefone para o teste.");
        String message = "Teste de envio do Money via API WebDigital.";
        try {
            JsonNode dispatch = whatsappClient.sendText(configuration, required(device.remoteId(), "Dispositivo sem vínculo WebDigital."),
                    number, message, "money.test", "test:" + System.currentTimeMillis(), "Teste");
            repository.insertWhatsappLog(id, null, null, null, "TESTE", number, "Teste",
                    WebDigitalWhatsappClient.logStatus(dispatch), message,
                    WebDigitalWhatsappClient.pendingNotice(dispatch));
        } catch (RuntimeException exception) {
            repository.insertWhatsappLog(id, null, null, null, "TESTE", number, "Teste",
                    "ERRO", message, summarize(exception.getMessage()));
            throw exception;
        }
        return repository.whatsappLogs().get(0);
    }

    public ActionResult startDispatch(UserAccount user, long id, String rawType) {
        requireAdministrator(user);
        requireActiveWhatsapp();
        WhatsappDevice device = repository.requireDevice(id);
        if (!device.connected()) throw new ApiException(HttpStatus.BAD_REQUEST, "O dispositivo não está conectado.");
        if (device.dispatching()) throw new ApiException(HttpStatus.CONFLICT, "Este dispositivo já está disparando.");
        if (device.regionIds().isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "Selecione ao menos uma região.");
        String type = normalizeDispatchType(rawType);
        List<IntegrationRepository.DispatchTarget> targets = repository.dispatchTargets(id, type);
        if (targets.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "Nenhum cliente encontrado para este disparo.");
        if (!repository.tryStartDispatch(id, type, targets.size())) {
            throw new ApiException(HttpStatus.CONFLICT, "Este dispositivo já está disparando.");
        }
        try {
            dispatchExecutor.execute(() -> executeDispatch(id, type, targets));
        } catch (RuntimeException exception) {
            repository.setDispatching(id, false);
            throw exception;
        }
        return new ActionResult("Disparo iniciado para " + targets.size() + " cliente(s).");
    }

    public ActionResult startDispatchTest(UserAccount user, long id, String phone) {
        requireAdministrator(user);
        requireActiveWhatsapp();
        WhatsappDevice device = repository.requireDevice(id);
        if (!device.connected()) throw new ApiException(HttpStatus.BAD_REQUEST, "O dispositivo não está conectado.");
        String number = required(phone, "Informe o telefone para o teste do disparo em massa.");
        if (!repository.tryStartDispatch(id, "TESTE_MASSA", 1)) {
            throw new ApiException(HttpStatus.CONFLICT, "Este dispositivo já está disparando.");
        }
        try {
            dispatchExecutor.execute(() -> executeDispatchTest(id, number));
        } catch (RuntimeException exception) {
            repository.setDispatching(id, false);
            throw exception;
        }
        return new ActionResult("Teste do disparo em massa iniciado para 1 destinatário.");
    }

    public WhatsappDevice stopDispatch(UserAccount user, long id) {
        requireAdministrator(user);
        repository.requireDevice(id);
        repository.setDispatching(id, false);
        repository.insertWhatsappLog(id, null, null, null, "SISTEMA", null, null,
                "AVISO", null, "Disparo interrompido pelo usuário.");
        return repository.requireDevice(id);
    }

    public List<WhatsappLog> logs(UserAccount user) {
        requireAdministrator(user);
        return repository.whatsappLogs();
    }

    public void clearLogs(UserAccount user) {
        requireAdministrator(user);
        repository.clearWhatsappLogs();
    }

    private void executeDispatch(
            long deviceId,
            String type,
            List<IntegrationRepository.DispatchTarget> targets) {
        int successful = 0;
        int errors = 0;
        int warnings = 0;
        boolean interrupted = false;
        String dispatchRun = UUID.randomUUID().toString();
        try {
            WhatsappSecret configuration = requireActiveWhatsapp();
            WhatsappDevice device = repository.requireDevice(deviceId);
            for (int i = 0; i < targets.size(); i++) {
                if (!repository.isDispatching(deviceId)) {
                    interrupted = true;
                    break;
                }
                IntegrationRepository.DispatchTarget target = targets.get(i);
                if (!repository.isDispatchTargetEligible(type, target)) {
                    repository.insertWhatsappLog(deviceId, target.clientId(), target.loanId(),
                            target.installmentId(), type, target.phone(), target.clientName(), "AVISO",
                            null, "Cliente ignorado: o contrato não está mais elegível para este disparo.");
                    warnings++;
                    repository.recordDispatchProgress(deviceId, "AVISO");
                    continue;
                }
                String message = dispatchMessage(configuration, type, target);
                if (message == null) {
                    repository.insertWhatsappLog(deviceId, target.clientId(), target.loanId(),
                            target.installmentId(), type, target.phone(), target.clientName(), "AVISO",
                            null, "Cliente ignorado: não há mais valor pendente para montar a mensagem.");
                    warnings++;
                    repository.recordDispatchProgress(deviceId, "AVISO");
                    continue;
                }
                if (target.phone() == null) {
                    repository.insertWhatsappLog(deviceId, target.clientId(), target.loanId(),
                            target.installmentId(), type, null, target.clientName(), "ERRO",
                            message, "Cliente sem telefone válido.");
                    errors++;
                    repository.recordDispatchProgress(deviceId, "ERRO");
                } else {
                    try {
                        JsonNode dispatch = whatsappClient.sendText(configuration, device.remoteId(), target.phone(), message,
                                "money.collection." + type.toLowerCase(Locale.ROOT),
                                type.toLowerCase(Locale.ROOT) + ":" + dispatchRun + ":" + target.clientId()
                                        + ":" + first(target.installmentId() == null ? null
                                                : target.installmentId().toString(), Long.toString(target.loanId())),
                                target.clientName());
                        repository.insertWhatsappLog(deviceId, target.clientId(), target.loanId(),
                                target.installmentId(), type, target.phone(), target.clientName(),
                                WebDigitalWhatsappClient.logStatus(dispatch), message,
                                WebDigitalWhatsappClient.pendingNotice(dispatch));
                        if (WebDigitalWhatsappClient.pending(dispatch)) warnings++;
                        else successful++;
                        repository.recordDispatchProgress(deviceId, WebDigitalWhatsappClient.logStatus(dispatch));
                    } catch (RuntimeException exception) {
                        repository.insertWhatsappLog(deviceId, target.clientId(), target.loanId(),
                                target.installmentId(), type, target.phone(), target.clientName(),
                                "ERRO", message, summarize(exception.getMessage()));
                        errors++;
                        repository.recordDispatchProgress(deviceId, "ERRO");
                    }
                }
                if (i + 1 < targets.size() && !waitForNextDispatch(deviceId)) {
                    interrupted = true;
                    break;
                }
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            interrupted = true;
        } catch (RuntimeException exception) {
            repository.insertWhatsappLog(deviceId, null, null, null, type, null, null,
                    "ERRO", null, summarize(exception.getMessage()));
            errors++;
        } finally {
            repository.setDispatching(deviceId, false);
            String summary = (interrupted ? "Disparo interrompido." : "Disparo finalizado.")
                    + " Total: " + targets.size() + ", sucessos: " + successful
                    + ", erros: " + errors + ", avisos/pendentes: " + warnings + ".";
            String finalStatus = interrupted ? "AVISO"
                    : successful == 0 && errors > 0 ? "ERRO"
                    : errors > 0 ? "AVISO" : "SUCESSO";
            repository.insertWhatsappLog(deviceId, null, null, null, type, null, null,
                    finalStatus, summary, null);
        }
    }

    private void executeDispatchTest(long deviceId, String phone) {
        String message = "Teste do disparo em massa do Money realizado com sucesso.";
        String status = "SUCESSO";
        String error = null;
        try {
            WhatsappSecret configuration = requireActiveWhatsapp();
            WhatsappDevice device = repository.requireDevice(deviceId);
            JsonNode dispatch = whatsappClient.sendText(configuration, device.remoteId(), phone, message,
                    "money.collection.test", "bulk-test:" + UUID.randomUUID(), "Teste Money");
            status = WebDigitalWhatsappClient.logStatus(dispatch);
            error = WebDigitalWhatsappClient.pendingNotice(dispatch);
            repository.recordDispatchProgress(deviceId, status);
        } catch (RuntimeException exception) {
            status = "ERRO";
            error = summarize(exception.getMessage());
            repository.recordDispatchProgress(deviceId, "ERRO");
        } finally {
            repository.insertWhatsappLog(deviceId, null, null, null, "TESTE_MASSA",
                    phone, "Teste Money", status, message, error);
            repository.setDispatching(deviceId, false);
        }
    }

    private boolean waitForNextDispatch(long deviceId) throws InterruptedException {
        for (int second = 0; second < 30; second++) {
            if (!repository.isDispatching(deviceId)) return false;
            Thread.sleep(1000L);
        }
        return repository.isDispatching(deviceId);
    }

    private String dispatchMessage(
            WhatsappSecret configuration,
            String type,
            IntegrationRepository.DispatchTarget target) {
        String source = switch (type) {
            case "VENCE_HOJE" -> template(configuration.dueTodayMessage(), DUE_TODAY_DEFAULT);
            case "DESAPARECIDAS" -> template(configuration.missingMessage(), MISSING_DEFAULT);
            case "AQUISICAO" -> template(configuration.acquisitionMessage(), ACQUISITION_DEFAULT);
            default -> template(configuration.overdueMessage(), OVERDUE_DEFAULT);
        };
        BigDecimal pending = target.installmentId() == null
                ? target.pendingAmount() : repository.pendingAmount(target.installmentId());
        String message = source.replace("{nome_cliente}", target.clientName())
                .replace("{cliente}", target.clientName())
                .replace("{contrato}", Long.toString(target.loanId()))
                .replace("{parcela}", target.installment())
                .replace("{vencimento}", DATE.format(target.dueDate()))
                .replace("{valor_pendente}", currency(pending));
        if (!"ATRASADAS".equals(type)) return message;

        IntegrationRepository.OverdueSummary summary = repository.overdueSummary(target.loanId());
        if (summary == null) return null;
        long overdueDays = Math.max(0, ChronoUnit.DAYS.between(
                summary.firstDue().toLocalDate(), LocalDateTime.now().toLocalDate()));
        String lateFee = currency(summary.overdueFee());
        if (summary.dailyFee().compareTo(new BigDecimal("0.01")) > 0) {
            lateFee += " (" + currency(summary.dailyFee()) + " ao dia)";
        } else if (summary.overdueFee().compareTo(new BigDecimal("0.01")) <= 0) {
            lateFee = "Sem juros/multa diária cadastrada";
        }
        return message.replace("{qtd_parcelas}", Integer.toString(summary.installmentCount()))
                .replace("{texto_parcelas}", summary.installmentCount() == 1 ? "parcela" : "parcelas")
                .replace("{primeiro_vencimento}", DATE.format(summary.firstDue()))
                .replace("{dias_atraso}", Long.toString(overdueDays))
                .replace("{dias_atraso_texto}", overdueDays > 0 ? " (" + overdueDays + " dia(s) em atraso)" : "")
                .replace("{parcelas_atraso}", first(summary.installments(), target.installment()))
                .replace("{valor_devedor}", currency(summary.debt()))
                .replace("{juros_contrato}", currency(summary.contractInterest()))
                .replace("{juros_atraso}", lateFee)
                .replace("{multa_dia}", currency(summary.dailyFee()))
                .replace("{valor_total_atualizado}", currency(summary.updatedTotal()));
    }

    private String currency(BigDecimal value) {
        synchronized (CURRENCY) {
            return CURRENCY.format(value == null ? BigDecimal.ZERO : value);
        }
    }

    private WhatsappSecret requireActiveWhatsapp() {
        WhatsappSecret value = repository.whatsappSecret();
        if (!value.active() || value.token() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Ative e configure a API WhatsApp primeiro.");
        }
        return value;
    }

    private WhatsappConfig withDefaults(WhatsappConfig value) {
        return new WhatsappConfig(value.active(), value.tokenConfigured(), BASE_URL,
                template(value.overdueMessage(), OVERDUE_DEFAULT),
                template(value.dueTodayMessage(), DUE_TODAY_DEFAULT),
                template(value.missingMessage(), MISSING_DEFAULT),
                template(value.acquisitionMessage(), ACQUISITION_DEFAULT),
                template(value.pixMessage(), PIX_DEFAULT),
                template(value.pixReceivedMessage(), PIX_RECEIVED_DEFAULT));
    }

    private StoredUpload store(
            long id, MultipartFile file, String label, String defaultExtension,
            Set<String> extensions) throws Exception {
        if (empty(file)) return new StoredUpload(null, null);
        if (file.getSize() > 8 * 1024 * 1024L) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "O arquivo " + label + " excede 8 MB.");
        }
        String original = safeFileName(file.getOriginalFilename(), label + defaultExtension);
        String extension = extension(original);
        if (!extensions.contains(extension)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Formato inválido para " + label + ".");
        }
        Path destination = certificateDirectory.resolve(
                "conta-" + id + "-" + label + "-" + UUID.randomUUID() + "." + extension).normalize();
        if (!destination.startsWith(certificateDirectory)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Nome de arquivo inválido.");
        }
        try (var input = file.getInputStream()) {
            Files.copy(input, destination, StandardCopyOption.REPLACE_EXISTING);
        }
        return new StoredUpload(destination.toString(), original);
    }

    private Path path(String value) {
        return value == null || value.isBlank() ? null : Path.of(value).toAbsolutePath().normalize();
    }

    private static List<Long> normalizedIds(List<Long> values) {
        if (values == null) return List.of();
        return values.stream().filter(value -> value != null && value > 0).distinct().toList();
    }

    private static boolean remoteConnected(JsonNode remote) {
        if (remote.hasNonNull("connected")) return remote.path("connected").asBoolean(false);
        String status = first(
                remote.path("status").asText(null),
                remote.path("state").asText(null),
                remote.path("connectionStatus").asText(null)).toLowerCase(Locale.ROOT);
        return Set.of("open", "connected", "conectado", "online", "ready", "active")
                .contains(status);
    }

    private static String remoteStatus(JsonNode remote, boolean connected) {
        if (connected) return "CONECTADO";
        String status = first(
                remote.path("status").asText(null),
                remote.path("state").asText(null),
                remote.path("connectionStatus").asText(null)).toLowerCase(Locale.ROOT);
        if (Set.of("close", "closed", "disconnected", "desconectado", "offline")
                .contains(status)) {
            return "DESCONECTADO";
        }
        return status.isBlank() ? "DESCONECTADO" : status.toUpperCase(Locale.ROOT);
    }

    private static String normalizeDispatchType(String raw) {
        String value = clean(raw).toUpperCase(Locale.ROOT);
        if (!Set.of("ATRASADAS", "VENCE_HOJE", "DESAPARECIDAS", "AQUISICAO").contains(value)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Tipo de disparo inválido.");
        }
        return value;
    }

    private static String keepSecret(String incoming, String current) {
        String value = nullable(incoming);
        return value == null ? nullable(current) : value;
    }

    private static String template(String value, String fallback) {
        String result = nullable(value);
        return result == null ? fallback : result;
    }

    private static String required(String value, String message) {
        String result = nullable(value);
        if (result == null) throw new ApiException(HttpStatus.BAD_REQUEST, message);
        return result;
    }

    private static String first(String... values) {
        for (String value : values) {
            String result = nullable(value);
            if (result != null) return result;
        }
        return "";
    }

    private static String safeFileName(String value, String fallback) {
        String source = first(value, fallback);
        String result = Path.of(source).getFileName().toString().replaceAll("[^A-Za-z0-9._-]", "_");
        return result.isBlank() ? fallback : result;
    }

    private static String extension(String name) {
        int dot = name.lastIndexOf('.');
        return dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    private static boolean empty(MultipartFile file) {
        return file == null || file.isEmpty();
    }

    private static String summarize(String value) {
        String result = first(value, "Erro não informado.");
        return result.length() > 500 ? result.substring(0, 497) + "..." : result;
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String result = clean(value);
        return result.isBlank() ? null : result;
    }

    private static void requireAdministrator(UserAccount user) {
        if (user == null || !user.isAdministrator()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Apenas administradores podem acessar integrações.");
        }
    }

    private static void requirePrincipalAdministrator(UserAccount user) {
        requireAdministrator(user);
        if (user.getId() != 1L && !"ADMINISTRADOR".equalsIgnoreCase(user.getUsername())) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Apenas o usuário ADMINISTRADOR pode alterar credenciais de integração.");
        }
    }

    private record StoredUpload(String path, String name) {
    }
}
