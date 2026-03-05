package org.opencds.common.cache;

import java.util.UUID;

public record CacheRegion<K, V>(Class<K> keyType, Class<V> valueType, UUID uuid) {
    public CacheRegion {
        uuid = UUID.randomUUID();
    }

    public static <K, V> CacheRegion<K, V> create(Class<K> keyType, Class<V> valueType) {
        return new CacheRegion<>(keyType, valueType, UUID.randomUUID());
    }

    boolean supportsValueType(Class<?> type) {
        return valueType().isAssignableFrom(type);
    }
}
