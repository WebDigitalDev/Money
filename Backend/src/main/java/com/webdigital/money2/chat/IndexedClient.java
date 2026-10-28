package com.webdigital.money2.chat;

public record IndexedClient(
        Long id,
        String name,
        String legalName,
        String document,
        String phone,
        String secondaryPhone,
        Long regionId,
        String regionName) {

    public String searchableText() {
        return String.join(" ",
                clean(name),
                clean(name),
                clean(legalName),
                clean(document),
                clean(phone),
                clean(secondaryPhone),
                clean(regionName));
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
