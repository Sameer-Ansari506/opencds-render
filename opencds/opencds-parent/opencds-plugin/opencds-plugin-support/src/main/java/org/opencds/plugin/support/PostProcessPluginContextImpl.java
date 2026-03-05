package org.opencds.plugin.support;

import org.opencds.plugin.api.PluginDataCache;
import org.opencds.plugin.api.PostProcessPluginContext;
import org.opencds.plugin.api.SupportingData;

import java.util.List;
import java.util.Map;
import java.util.Set;

public final class PostProcessPluginContextImpl implements PostProcessPluginContext {
    private final Map<String, SupportingData> supportingData;
    private final PluginDataCache cache;
    private final Set<String> assertions;
    private final Map<String, List<?>> resultFactLists;
    private final Map<String, Object> namedObjects;
    private final Map<Class<?>, List<?>> allFactLists;

    public PostProcessPluginContextImpl(Map<String, SupportingData> supportingData,
                                        PluginDataCache cache,
                                        Map<Class<?>, List<?>> allFactLists,
                                        Set<String> assertions,
                                        Map<String, List<?>> resultFactLists,
                                        Map<String, Object> namedObjects) {
        this.allFactLists = allFactLists;
        this.assertions = assertions;
        this.resultFactLists = resultFactLists;
        this.namedObjects = namedObjects;
        this.supportingData = supportingData;
        this.cache = cache;
    }

    public static PostProcessPluginContextImpl create(Map<String, SupportingData> supportingData,
                                                      PluginDataCache cache,
                                                      Map<Class<?>, List<?>> allFactLists,
                                                      Map<String, Object> namedObjects,
                                                      Set<String> assertions,
                                                      Map<String, List<?>> resultFactLists) {
        return new PostProcessPluginContextImpl(
                supportingData,
                cache,
                allFactLists,
                assertions,
                resultFactLists,
                namedObjects);
    }

    public static PostProcessPluginContextImpl createPostProcessPluginContext(Map<String, SupportingData> supportingData,
                                                                              PluginDataCache cache,
                                                                              Map<Class<?>, List<?>> allFactLists,
                                                                              Map<String, Object> namedObjects,
                                                                              Set<String> assertions,
                                                                              Map<String, List<?>> resultFactLists) {
        return create(
                supportingData,
                cache,
                allFactLists,
                namedObjects,
                assertions,
                resultFactLists);
    }

    @Override
    public Map<Class<?>, List<?>> getAllFactLists() {
        return allFactLists;
    }

    @Override
    public Set<String> getAssertions() {
        return assertions;
    }

    @Override
    public Map<String, List<?>> getResultFactLists() {
        return resultFactLists;
    }

    @Override
    public Map<String, Object> getNamedObjects() {
        return namedObjects;
    }

    @Override
    public PluginDataCache getCache() {
        return cache;
    }

    @Override
    public Map<String, SupportingData> getSupportingData() {
        return supportingData;
    }
}
