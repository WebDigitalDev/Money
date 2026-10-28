package com.webdigital.money2.integrations;

import org.bouncycastle.asn1.pkcs.PrivateKeyInfo;
import org.bouncycastle.openssl.PEMEncryptedKeyPair;
import org.bouncycastle.openssl.PEMKeyPair;
import org.bouncycastle.openssl.PEMParser;
import org.bouncycastle.openssl.jcajce.JcaPEMKeyConverter;
import org.bouncycastle.pkcs.PKCS8EncryptedPrivateKeyInfo;
import org.springframework.stereotype.Component;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import java.io.InputStream;
import java.io.Reader;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class SicrediMtlsClientFactory {

    private final Map<String, HttpClient> clients = new ConcurrentHashMap<>();

    public synchronized HttpClient create(PixRepository.BankConfig config) throws Exception {
        Path certificate = requiredPath(config.certificatePath(), "certificado .CER");
        Path privateKey = requiredPath(config.privateKeyPath(), "chave privada .KEY");
        Path chain = optionalPath(config.chainPath());
        String cacheKey = config.id() + "|" + config.updatedAt() + "|" + certificate + "|" + privateKey + "|" + chain;
        HttpClient current = clients.get(cacheKey);
        if (current != null) return current;
        HttpClient result = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .sslContext(sslContext(certificate, privateKey, chain))
                .build();
        clients.put(cacheKey, result);
        return result;
    }

    public void validate(Path certificate, Path privateKey, Path chain) throws Exception {
        sslContext(certificate, privateKey, chain);
    }

    private SSLContext sslContext(Path certificate, Path privateKey, Path chain) throws Exception {
        List<X509Certificate> certificates = certificates(certificate, chain);
        PrivateKey key = privateKey(privateKey);
        validatePair(key, certificates.get(0));
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        keyStore.load(null, null);
        char[] password = new char[0];
        keyStore.setKeyEntry("sicredi", key, password, certificates.toArray(new Certificate[0]));
        KeyManagerFactory keyManager = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        keyManager.init(keyStore, password);
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(keyManager.getKeyManagers(), null, null);
        return context;
    }

    private List<X509Certificate> certificates(Path certificate, Path chain) throws Exception {
        Map<String, X509Certificate> values = new LinkedHashMap<>();
        addCertificates(values, certificate);
        if (chain != null) addCertificates(values, chain);
        if (values.isEmpty()) throw new IllegalArgumentException("O arquivo .CER não contém certificado X.509 válido.");
        List<X509Certificate> source = new ArrayList<>(values.values());
        X509Certificate client = source.get(0);
        client.checkValidity();
        List<X509Certificate> ordered = new ArrayList<>();
        ordered.add(client);
        X509Certificate current = client;
        while (!current.getIssuerX500Principal().equals(current.getSubjectX500Principal())) {
            X509Certificate issuer = null;
            for (X509Certificate candidate : source) {
                if (!ordered.contains(candidate)
                        && current.getIssuerX500Principal().equals(candidate.getSubjectX500Principal())) {
                    issuer = candidate;
                    break;
                }
            }
            if (issuer == null) break;
            ordered.add(issuer);
            current = issuer;
        }
        return ordered;
    }

    private void addCertificates(Map<String, X509Certificate> target, Path path) throws Exception {
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        try (InputStream input = Files.newInputStream(path)) {
            Collection<? extends Certificate> found = factory.generateCertificates(input);
            for (Certificate value : found) {
                X509Certificate certificate = (X509Certificate) value;
                target.putIfAbsent(certificate.getSerialNumber() + "|" + certificate.getSubjectX500Principal(), certificate);
            }
        }
    }

    private PrivateKey privateKey(Path path) throws Exception {
        try (Reader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8);
             PEMParser parser = new PEMParser(reader)) {
            Object value = parser.readObject();
            JcaPEMKeyConverter converter = new JcaPEMKeyConverter();
            if (value instanceof PEMKeyPair pair) return converter.getKeyPair(pair).getPrivate();
            if (value instanceof PrivateKeyInfo info) return converter.getPrivateKey(info);
            if (value instanceof PEMEncryptedKeyPair || value instanceof PKCS8EncryptedPrivateKeyInfo) {
                throw new IllegalArgumentException("A chave privada deve estar sem senha, conforme o Sicredi.");
            }
            throw new IllegalArgumentException("O arquivo .KEY não contém uma chave privada PEM válida.");
        }
    }

    private void validatePair(PrivateKey privateKey, X509Certificate certificate) throws Exception {
        String algorithm = switch (privateKey.getAlgorithm().toUpperCase()) {
            case "RSA" -> "SHA256withRSA";
            case "EC" -> "SHA256withECDSA";
            default -> throw new IllegalArgumentException("Algoritmo da chave privada não suportado.");
        };
        byte[] challenge = "money2-sicredi-mtls".getBytes(StandardCharsets.UTF_8);
        Signature signature = Signature.getInstance(algorithm);
        signature.initSign(privateKey);
        signature.update(challenge);
        byte[] signed = signature.sign();
        signature.initVerify(certificate.getPublicKey());
        signature.update(challenge);
        if (!signature.verify(signed)) {
            throw new IllegalArgumentException("O certificado .CER não corresponde à chave privada .KEY.");
        }
    }

    private Path requiredPath(String value, String label) {
        Path path = optionalPath(value);
        if (path == null) throw new IllegalArgumentException("Informe o " + label + " do Sicredi.");
        return path;
    }

    private Path optionalPath(String value) {
        if (value == null || value.isBlank()) return null;
        Path path = Path.of(value.trim()).toAbsolutePath().normalize();
        if (!Files.isRegularFile(path)) throw new IllegalArgumentException("Arquivo Sicredi não encontrado: " + path.getFileName());
        return path;
    }
}
