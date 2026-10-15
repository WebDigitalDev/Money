package com.webdigital.money2.chat;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class TextVectorizerTest {

    private final TextVectorizer vectorizer = new TextVectorizer();

    @Test
    void normalizesAccentsPunctuationAndCase() {
        assertEquals(
                "joao da silva 65 99999 9999",
                vectorizer.normalize("  JOÃO da SILVA — (65) 99999-9999 "));
    }

    @Test
    void createsNormalizedDeterministicVectors() {
        float[] first = vectorizer.vectorize("Maria Aparecida");
        float[] same = vectorizer.vectorize("MARÍA  APARECIDA");
        float[] different = vectorizer.vectorize("Carlos Oliveira");

        assertEquals(TextVectorizer.DIMENSIONS, first.length);
        assertEquals(1.0, length(first), 0.00001);
        assertEquals(1.0, length(same), 0.00001);
        assertTrue(cosine(first, same) > 0.99);
        assertNotEquals(cosine(first, different), cosine(first, same));
    }

    private static double length(float[] vector) {
        double sum = 0;
        for (float value : vector) sum += value * value;
        return Math.sqrt(sum);
    }

    private static double cosine(float[] first, float[] second) {
        double value = 0;
        for (int index = 0; index < first.length; index++) {
            value += first[index] * second[index];
        }
        return value;
    }
}
