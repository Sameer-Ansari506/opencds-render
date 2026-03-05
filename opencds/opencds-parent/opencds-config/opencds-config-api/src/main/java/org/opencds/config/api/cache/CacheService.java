/*
 * Copyright 2014-2020 OpenCDS.org
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

package org.opencds.config.api.cache;

import org.opencds.common.cache.CacheRegion;

import java.util.Map;
import java.util.Set;
import java.util.function.Supplier;

public interface CacheService {

    <K, V> boolean containsKey(CacheRegion<K, V> cacheRegion, K key);

    // TODO: need the ability to refresh the cache
    <K, V> V get(CacheRegion<K, V> cacheRegion, K key);

    <K, V> Map<K, V> getAll(CacheRegion<K, V> cacheRegion);

    <K, V> Set<K> getAllKeys(CacheRegion<K, V> cacheRegion);

    <K, V> Set<V> getAllValues(CacheRegion<K, V> cacheRegion);

    <K, V> void put(CacheRegion<K, V> cacheRegion, K key, V cachable);

    <K, V> void putAll(CacheRegion<K, V> cacheRegion, Map<K, V> cachables);

    <K, V> void evict(CacheRegion<K, V> cacheRegion, K key);

    <K, V> void evictAll(CacheRegion<K, V> cacheRegion);
}
