package com.webdigital.money2.chat;

import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.Locale;
import org.springframework.stereotype.Component;

@Component
public class TextVectorizer {

    public static final int DIMENSIONS = 384;

    public float[] vectorize(String rawText) {
        String normalized = normalize(rawText);
        float[] vector = new float[DIMENSIONS];
        if (normalized.isBlank()) return vector;

        String padded = "  " + normalized + "  ";
        for (int index = 0; index <= padded.length() - 3; index++) {
            String gram = padded.substring(index, index + 3);
            byte[] bytes = gram.getBytes(StandardCharsets.UTF_8);
            int hash = 0x811c9dc5;
            for (byte value : bytes) {
                hash ^= value & 0xff;
                hash *= 0x01000193;
            }
            int position = Math.floorMod(hash, DIMENSIONS);
            vector[position] += ((hash >>> 8) & 1) == 0 ? 1.0f : -1.0f;
        }

        double length = 0;
        for (float value : vector) length += value * value;
        if (length == 0) return vector;
        float divisor = (float) Math.sqrt(length);
        for (int index = 0; index < vector.length; index++) {
            vector[index] /= divisor;
        }
        return vector;
    }

    public String normalize(String value) {
        if (value == null) return "";
        return Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "")
                .toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }
}
