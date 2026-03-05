/*
 * Copyright 2013-2020 OpenCDS.org
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.opencds.common.cache;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import java.util.Collection;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.stream.Collectors;

public class OpencdsCache {
    private static final Log log = LogFactory.getLog(org.opencds.common.cache.OpencdsCache.class);

    private final ConcurrentMap<CacheRegion<?, ?>, ConcurrentMap<Object, Object>> cache = new ConcurrentHashMap<>();

    public <V, K> boolean containsKey(CacheRegion<K, V> cacheRegion, K key) {
        return cache.get(cacheRegion).containsKey(key);
    }

    public <K, V> Map<K, V> getCache(CacheRegion<K, V> cacheRegion) {
        ensureRegionExists(cacheRegion);
        return copy(cache.get(cacheRegion));
    }

    public <K, V> K getCacheKey(CacheRegion<K, V> cacheRegion, K key) {
        ensureRegionExists(cacheRegion);
        return cache.get(cacheRegion).keySet().stream()
                .filter(k -> k.equals(key))
                .map(k -> (K) k)
                .findFirst()
                .orElse(null);
    }

    public <K, V> Set<K> getCacheKeys(CacheRegion<K, V> cacheRegion) {
        ensureRegionExists(cacheRegion);
        // return a copied set.
        return copy(cache.get(cacheRegion).keySet());
    }

    public <K, V> Set<V> getCacheValues(CacheRegion<K, V> cacheRegion) {
        ensureRegionExists(cacheRegion);
        // return a copied set.
        return copy(cache.get(cacheRegion).values());
    }

    public <K, V> V get(CacheRegion<K, V> cacheRegion, K key) {
        ensureRegionExists(cacheRegion);
        return (V) cache.get(cacheRegion).get(key);
    }

    public <K, V> void put(CacheRegion<K, V> cacheRegion, K key, V instance) {
        if (cacheRegion.supportsValueType(instance.getClass())) {
            ensureRegionExists(cacheRegion);
            cache.get(cacheRegion).put(key, instance);
        } else {
            var message = "This CacheRegion (" +
                    cacheRegion.getClass().getSimpleName() + "." + cacheRegion +
                    ") should not support instance or subclass of type: " + instance.getClass();
            log.warn(message);
            throw new RuntimeException(message);
        }
    }

    private <V> Set<V> copy(Collection<Object> coll) {
        return coll.stream()
                .map(this::<V>cast)
                .filter(Objects::nonNull)
                .collect(Collectors.toUnmodifiableSet());
    }

    private <K, V> Map<K, V> copy(Map<Object, Object> map) {
        return map.entrySet().stream()
                .map(e -> Map.entry((K) e.getKey(), (V) e.getValue()))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private <V> V cast(Object o) {
        try {
            return (V) o;
        } catch (ClassCastException e) {
            var message = "Object is not expected type T: " + o.getClass();
            log.warn(message);
            throw new RuntimeException(message);
        }
    }

    private <K, V> void ensureRegionExists(CacheRegion<K, V> cacheRegion) {
        cache.putIfAbsent(cacheRegion, new ConcurrentHashMap<>());
    }

    public <K, V> void evict(CacheRegion<K, V> cacheRegion, K key) {
        ensureRegionExists(cacheRegion);
        cache.get(cacheRegion).remove(key);
    }

    public <K, V> void evictAll(CacheRegion<K, V> cacheRegion) {
        ensureRegionExists(cacheRegion);
        cache.get(cacheRegion).clear();
    }
}
