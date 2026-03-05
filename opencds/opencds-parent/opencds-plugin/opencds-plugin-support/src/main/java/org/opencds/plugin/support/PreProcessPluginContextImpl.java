package org.opencds.plugin.support;

import org.opencds.plugin.api.PluginDataCache;
import org.opencds.plugin.api.PreProcessPluginContext;
import org.opencds.plugin.api.SupportingData;

import java.util.List;
import java.util.Map;

public final class PreProcessPluginContextImpl implements PreProcessPluginContext {
    private final Map<String, SupportingData> supportingData;
    private final PluginDataCache cache;
    private final Map<Class<?>, List<?>> allFactLists;
    private final Map<String, Object> namedObjects;
    private final Map<String, Object> globals;

    private PreProcessPluginContextImpl(Map<String, SupportingData> supportingData,
                                        PluginDataCache cache,
                                        Map<Class<?>, List<?>> allFactLists,
                                        Map<String, Object> namedObjects,
                                        Map<String, Object> globals) {
        this.allFactLists = allFactLists;
        this.namedObjects = namedObjects;
        this.globals = globals;
        this.supportingData = supportingData;
        this.cache = cache;
    }

    public static PreProcessPluginContextImpl create(Map<String, SupportingData> supportingData,
                                                     PluginDataCache cache,
                                                     Map<Class<?>, List<?>> allFactLists,
                                                     Map<String, Object> namedObjects,
                                                     Map<String, Object> globals) {
        return new PreProcessPluginContextImpl(
                supportingData,
                cache,
                allFactLists,
                namedObjects,
                globals);
    }

    public static PreProcessPluginContextImpl createPreProcessPluginContext(Map<String, SupportingData> supportingData,
                                                                            PluginDataCache cache,
                                                                            Map<Class<?>, List<?>> allFactLists,
                                                                            Map<String, Object> namedObjects,
                                                                            Map<String, Object> globals) {
        return create(
                supportingData,
                cache,
                allFactLists,
                namedObjects,
                globals);
    }

    @Override
    public Map<Class<?>, List<?>> getAllFactLists() {
        return allFactLists;
    }

    @Override
    public Map<String, Object> getNamedObjects() {
        return namedObjects;
    }

    @Override
    public Map<String, Object> getGlobals() {
        return globals;
    }

    @Override
    public Map<String, SupportingData> getSupportingData() {
        return supportingData;
    }

    @Override
    public PluginDataCache getCache() {
        return cache;
    }
}
