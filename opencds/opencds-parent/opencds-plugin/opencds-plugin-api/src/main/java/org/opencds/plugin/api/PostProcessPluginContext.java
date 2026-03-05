package org.opencds.plugin.api;

import java.util.List;
import java.util.Map;
import java.util.Set;

public interface PostProcessPluginContext extends PluginContext {
    Map<Class<?>, List<?>> getAllFactLists();

    Set<String> getAssertions();

    Map<String, Object> getNamedObjects();

    Map<String, List<?>> getResultFactLists();
}
