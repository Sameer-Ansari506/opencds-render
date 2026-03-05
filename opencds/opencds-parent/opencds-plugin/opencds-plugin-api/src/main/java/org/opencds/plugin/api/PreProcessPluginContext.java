package org.opencds.plugin.api;

import java.util.List;
import java.util.Map;

public interface PreProcessPluginContext extends PluginContext {
    Map<Class<?>, List<?>> getAllFactLists();

    Map<String, Object> getNamedObjects();

    Map<String, Object> getGlobals();
}
