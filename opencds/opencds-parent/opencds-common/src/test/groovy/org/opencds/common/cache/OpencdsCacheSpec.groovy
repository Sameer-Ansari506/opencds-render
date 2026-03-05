package org.opencds.common.cache


import spock.lang.Specification

class OpencdsCacheSpec extends Specification {
    private static final CacheRegion<String, String> R_ONE =
            CacheRegion.create(String.class, String.class)
    private static final CacheRegion<String, String> R_TWO =
            CacheRegion.create(String.class, String.class)
    private static final CacheRegion<String, String> R_THREE =
            CacheRegion.create(String.class, String.class)
    private static final CacheRegion<String, String> R_FOUR =
            CacheRegion.create(String.class, String.class)

    private static final CacheRegion<String, String> S_ONE =
            CacheRegion.create(String.class, String.class)
    private static final CacheRegion<String, Integer> I_ONE =
            CacheRegion.create(String.class, Integer.class)

    def 'test OpencdsCache'() {
        expect:
        var cache = new OpencdsCache()

        and: 'empty cache'
        cache.get(region1, key1) == null
        cache.getCacheKey(region1, key1) == null
        cache.get(region1, key2) == null
        cache.getCacheKey(region1, key2) == null

        and: 'put and test strRegion, strKey, strObj'
        cache.put(region1, key1, obj1)
        cache.get(region1, key1) == obj1
        cache.getCacheKey(region1, key1) == key1
        cache.getCacheValues(region1) == [obj1] as Set

        and: 'put strRegion, strKey, intObj (changes from strObj to intObj)'
        cache.put(region1, key1, obj2)
        cache.get(region1, key1) != obj1
        cache.get(region1, key1) == obj2
        cache.getCacheKey(region1, key1) == key1
        cache.getCacheKeys(region1) == [key1] as Set
        cache.getCacheValues(region1) == [obj2] as Set

        and: 'now evict and verify'
        cache.evict(region1, key1)
        cache.evict(region1, key2)
        cache.get(region1, key1) == null
        cache.getCacheKey(region1, key1) == null
        cache.getCacheKeys(region1) == [] as Set
        cache.getCacheValues(region1) == [] as Set

        and: 'now use strRegion, and keys-to-objects by number'
        cache.put(region1, key1, obj1)
        cache.put(region1, key2, obj2)
        cache.get(region1, key1) == obj1
        cache.get(region1, key2) == obj2
        cache.getCacheKey(region1, key1) == key1
        cache.getCacheKey(region1, key2) == key2
        cache.getCacheKeys(region1) == [key1, key2] as Set
        cache.getCacheValues(region1) == [obj1, obj2] as Set

        and: 'now evict and verify'
        cache.evict(region1, key1)
        cache.evict(region1, key2)
        cache.get(region1, key1) == null
        cache.get(region1, key2) == null
        cache.get(region2, key1) == null
        cache.get(region2, key2) == null
        cache.getCacheKey(region1, key1) == null
        cache.getCacheKey(region1, key2) == null
        cache.getCacheKey(region2, key1) == null
        cache.getCacheKey(region2, key2) == null
        cache.getCacheKeys(region1) == [] as Set
        cache.getCacheKeys(region2) == [] as Set
        cache.getCacheValues(region1) == [] as Set
        cache.getCacheValues(region2) == [] as Set

        and: 'now use two regions with one key'
        cache.put(region1, key1, obj1)
        cache.put(region2, key2, obj2)
        cache.get(region1, key1) == obj1
        cache.get(region1, key2) == null
        cache.get(region2, key1) == null
        cache.get(region2, key2) == obj2
        cache.getCacheKey(region1, key1) == key1
        cache.getCacheKey(region1, key2) == null
        cache.getCacheKey(region2, key1) == null
        cache.getCacheKey(region2, key2) == key2
        cache.getCacheKeys(region1) == [key1] as Set
        cache.getCacheKeys(region2) == [key2] as Set
        cache.getCacheValues(region1) == [obj1] as Set
        cache.getCacheValues(region2) == [obj2] as Set


        and: 'now use two regions with two keys'
        cache.put(region1, key1, obj1)
        cache.put(region1, key2, obj2)
        cache.put(region2, key1, obj1)
        cache.put(region2, key2, obj2)
        cache.get(region1, key1) == obj1
        cache.get(region1, key2) == obj2
        cache.get(region2, key1) == obj1
        cache.get(region2, key2) == obj2
        cache.getCacheKey(region1, key1) == key1
        cache.getCacheKey(region1, key2) == key2
        cache.getCacheKey(region2, key1) == key1
        cache.getCacheKey(region2, key2) == key2
        cache.getCacheKeys(region1) == [key1, key2] as Set
        cache.getCacheKeys(region2) == [key1, key2] as Set
        cache.getCacheValues(region1) == [obj1, obj2] as Set
        cache.getCacheValues(region2) == [obj1, obj2] as Set

        and: 'finally, evict and verify'
        cache.evict(region1, key1)
        cache.evict(region1, key2)
        cache.get(region1, key1) == null
        cache.get(region1, key2) == null
        cache.getCacheKey(region1, key1) == null
        cache.getCacheKey(region1, key2) == null
        cache.getCacheKeys(region1) == [] as Set
        cache.getCacheKeys(region1) == [] as Set
        cache.getCacheValues(region1) == [] as Set
        cache.getCacheValues(region1) == [] as Set

        where:
        region1 | key1 | obj1          | region2 | key2 | obj2
        R_ONE   | 'k1' | 'my-object-1' | R_TWO   | 'k2' | 'my-object-2'
        R_THREE | 'k3' | 'my-object-3' | R_FOUR  | 'k4' | 'my-object-4'
    }

    def 'test types of regions'() {
        expect:
        var cache = new OpencdsCache()

        and: 'empty cache'
        cache.get(strRegion, strKey) == null
        cache.get(strRegion, intKey) == null
        cache.get(intRegion, intKey) == null
        cache.get(intRegion, strKey) == null
        cache.getCacheKey(strRegion, strKey) == null
        cache.getCacheKey(strRegion, intKey) == null
        cache.getCacheKey(intRegion, strKey) == null
        cache.getCacheKey(intRegion, intKey) == null
        cache.getCacheKeys(strRegion) == [] as Set
        cache.getCacheKeys(intRegion) == [] as Set
        cache.getCacheValues(strRegion) == [] as Set
        cache.getCacheValues(intRegion) == [] as Set

        and: 'add strKey to StringRegion'
        cache.put(strRegion, strKey, strObj)
        cache.get(strRegion, strKey) == strObj
        cache.getCacheKey(strRegion, strKey) == strKey
        cache.getCacheKeys(strRegion) == [strKey] as Set
        cache.getCacheValues(strRegion) == [strObj] as Set

        and: 'add intKey to IntegerRegion'
        cache.put(intRegion, intKey, intObj)
        cache.get(intRegion, intKey) == intObj
        cache.getCacheKey(intRegion, intKey) == intKey
        cache.getCacheKeys(intRegion) == [intKey] as Set
        cache.getCacheValues(intRegion) == [intObj] as Set

        and: 'try to add an intObj value to StringRegion'
        var message
        try {
            cache.put(strRegion, intKey, intObj)
        } catch (RuntimeException e) {
            message = e.getMessage()
        }
        message.startsWith('This CacheRegion (CacheRegion.CacheRegion[keyType=class java.lang.String, valueType=class java.lang.String, uuid=')
        message.endsWith(']) should not support instance or subclass of type: class java.lang.Integer')

        and: 'try to add an strObj value to IntegerRegion'
        try {
            cache.put(intRegion, strKey, strObj)
        } catch (RuntimeException e) {
            message = e.getMessage()
        }
        message.startsWith 'This CacheRegion (CacheRegion.CacheRegion[keyType=class java.lang.String, valueType=class java.lang.Integer, uuid='
        message.endsWith ']) should not support instance or subclass of type: class java.lang.String'

        where:
        strRegion | strKey | strObj   | intRegion | intKey | intObj
        S_ONE     | 'ks1'  | 'string' | I_ONE     | 'ki2'  | 1
    }

    def 'test operations on a region'() {
        expect:
        var cache = new OpencdsCache()

        and: 'add strKey to StringRegion'
        cache.put(strRegion, strKey1, strObj1)
        cache.put(strRegion, strKey2, strObj2)
        cache.put(strRegion, strKey3, strObj3)
        cache.put(strRegion, strKey4, strObj4)
        cache.get(strRegion, strKey1) == strObj1
        cache.get(strRegion, strKey2) == strObj2
        cache.get(strRegion, strKey3) == strObj3
        cache.get(strRegion, strKey4) == strObj4
        cache.getCacheKey(strRegion, strKey1) == strKey1
        cache.getCacheKeys(strRegion) == [strKey1, strKey2, strKey3, strKey4] as Set
        cache.getCacheValues(strRegion) == [strObj1, strObj2, strObj3, strObj4] as Set

        and: 'get the cache and update it externally'
        var ex = null
        cache.getCache(S_ONE).size() == 4
        try {
            cache.getCache(S_ONE).clear()
        } catch (Exception e) {
            ex = e
        }
        ex instanceof UnsupportedOperationException
        cache.getCacheKeys(S_ONE).size() == 4
        try {
            ex = null
            cache.getCacheKeys(S_ONE).clear()
        } catch (Exception e) {
            ex = e
        }
        ex instanceof UnsupportedOperationException
        cache.getCacheKeys(S_ONE).size() == 4
        cache.getCacheValues(S_ONE).size() == 4
        try {
            ex = null
            cache.getCacheValues(S_ONE).clear()
        } catch (Exception e) {
            ex = e
        }
        ex instanceof UnsupportedOperationException
        cache.getCacheValues(S_ONE).size() == 4


        where:
        strRegion | strKey1 | strKey2 | strKey3 | strKey4 | strObj1   | strObj2   | strObj3   | strObj4
        S_ONE     | 'ks1'   | 'ks2'   | 'ks3'   | 'ks4'   | 'string1' | 'string2' | 'string3' | 'string4'
    }
}
