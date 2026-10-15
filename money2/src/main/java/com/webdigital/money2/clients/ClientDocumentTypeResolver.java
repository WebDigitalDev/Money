package com.webdigital.money2.clients;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Resolves legacy document names and MIME types without trusting picker metadata. */
public final class ClientDocumentTypeResolver {

    private ClientDocumentTypeResolver() { }

    public static ResolvedFile resolve(String rawFileName, String rawContentType, byte[] signature) {
        String fileName = safeFileName(rawFileName);
        String declaredType = normalizedContentType(rawContentType);
        String detectedType = detectContentType(signature);
        String contentType = isGeneric(declaredType)
                ? detectedType != null
                        ? detectedType
                        : contentTypeFromExtension(extension(fileName))
                : declaredType;
        if (contentType == null) contentType = "application/octet-stream";

        String expectedExtension = extensionForContentType(contentType);
        String currentExtension = extension(fileName);
        if (expectedExtension != null
                && (currentExtension == null
                        || currentExtension.equals("bin")
                        || currentExtension.equals("dat"))) {
            int suffixStart = fileName.lastIndexOf('.');
            String base = currentExtension == null ? fileName : fileName.substring(0, suffixStart);
            fileName = base + "." + expectedExtension;
        }
        return new ResolvedFile(fileName, contentType);
    }

    private static String safeFileName(String raw) {
        String value = raw == null ? "" : raw.trim().replace('\\', '_').replace('/', '_');
        return value.isEmpty() ? "documento" : value;
    }

    private static String normalizedContentType(String raw) {
        if (raw == null) return null;
        String value = raw.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
        if (value.equals("image/jpg")) return "image/jpeg";
        if (value.equals("application/x-pdf")) return "application/pdf";
        return value.isEmpty() ? null : value;
    }

    private static boolean isGeneric(String value) {
        return value == null
                || value.equals("application/octet-stream")
                || value.equals("binary/octet-stream")
                || value.equals("content/unknown");
    }

    private static String extension(String name) {
        int dot = name.lastIndexOf('.');
        if (dot <= 0 || dot == name.length() - 1) return null;
        String value = name.substring(dot + 1).toLowerCase(Locale.ROOT);
        return value.length() > 10 ? null : value;
    }

    private static String contentTypeFromExtension(String extension) {
        if (extension == null) return null;
        return switch (extension) {
            case "jpg", "jpeg" -> "image/jpeg";
            case "png" -> "image/png";
            case "gif" -> "image/gif";
            case "webp" -> "image/webp";
            case "bmp" -> "image/bmp";
            case "tif", "tiff" -> "image/tiff";
            case "pdf" -> "application/pdf";
            case "zip" -> "application/zip";
            case "mp4" -> "video/mp4";
            case "txt" -> "text/plain";
            case "html", "htm" -> "text/html";
            case "doc" -> "application/msword";
            case "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
            case "xls" -> "application/vnd.ms-excel";
            case "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            default -> null;
        };
    }

    private static String extensionForContentType(String type) {
        return switch (type) {
            case "image/jpeg" -> "jpg";
            case "image/png" -> "png";
            case "image/gif" -> "gif";
            case "image/webp" -> "webp";
            case "image/bmp" -> "bmp";
            case "image/tiff" -> "tiff";
            case "application/pdf" -> "pdf";
            case "application/zip" -> "zip";
            case "video/mp4" -> "mp4";
            case "text/plain" -> "txt";
            case "text/html" -> "html";
            case "application/msword" -> "doc";
            case "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx";
            case "application/vnd.ms-excel" -> "xls";
            case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx";
            default -> null;
        };
    }

    private static String detectContentType(byte[] bytes) {
        if (bytes == null || bytes.length < 4) return null;
        if (startsWith(bytes, 0x25, 0x50, 0x44, 0x46)) return "application/pdf";
        if (startsWith(bytes, 0xFF, 0xD8, 0xFF)) return "image/jpeg";
        if (startsWith(bytes, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) return "image/png";
        if (asciiStartsWith(bytes, "GIF87a") || asciiStartsWith(bytes, "GIF89a")) return "image/gif";
        if (asciiStartsWith(bytes, "RIFF") && asciiAt(bytes, 8, "WEBP")) return "image/webp";
        if (startsWith(bytes, 0x42, 0x4D)) return "image/bmp";
        if (startsWith(bytes, 0x49, 0x49, 0x2A, 0x00)
                || startsWith(bytes, 0x4D, 0x4D, 0x00, 0x2A)) return "image/tiff";
        if (startsWith(bytes, 0x50, 0x4B, 0x03, 0x04)
                || startsWith(bytes, 0x50, 0x4B, 0x05, 0x06)
                || startsWith(bytes, 0x50, 0x4B, 0x07, 0x08)) return "application/zip";
        if (asciiAt(bytes, 4, "ftyp")) return "video/mp4";

        String prefix = new String(bytes, 0, Math.min(bytes.length, 64), StandardCharsets.UTF_8)
                .stripLeading().toLowerCase(Locale.ROOT);
        if (prefix.startsWith("<!doctype html") || prefix.startsWith("<html")) return "text/html";
        return null;
    }

    private static boolean asciiStartsWith(byte[] bytes, String value) {
        return asciiAt(bytes, 0, value);
    }

    private static boolean asciiAt(byte[] bytes, int offset, String value) {
        byte[] expected = value.getBytes(StandardCharsets.US_ASCII);
        if (offset < 0 || bytes.length < offset + expected.length) return false;
        for (int index = 0; index < expected.length; index++) {
            if (bytes[offset + index] != expected[index]) return false;
        }
        return true;
    }

    private static boolean startsWith(byte[] bytes, int... expected) {
        if (bytes.length < expected.length) return false;
        for (int index = 0; index < expected.length; index++) {
            if ((bytes[index] & 0xFF) != expected[index]) return false;
        }
        return true;
    }

    public record ResolvedFile(String fileName, String contentType) { }
}
