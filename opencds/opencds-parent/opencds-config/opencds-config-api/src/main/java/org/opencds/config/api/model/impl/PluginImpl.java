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

package org.opencds.config.api.model.impl;

import org.apache.commons.lang3.StringUtils;
import org.opencds.config.api.model.Plugin;
import org.opencds.config.api.model.PluginId;

import java.util.ArrayList;
import java.util.List;

public record PluginImpl(PluginId identifier,
                         String className) implements Plugin {

    public PluginImpl {
        assert identifier != null;
        assert StringUtils.isNotBlank(className);
    }

    public static PluginImpl create(PluginId identifier, String className) {
        return new PluginImpl(
                PluginIdImpl.create(identifier),
                className);
    }

    public static PluginImpl create(Plugin pp) {
        if (pp == null) {
            return null;
        }
        if (pp instanceof PluginImpl pluginImpl) {
            return pluginImpl;
        }
        return create(pp.getIdentifier(), pp.getClassName());
    }

    public static List<Plugin> create(List<Plugin> plugins) {
        if (plugins == null) {
            return null;
        }
        var pis = new ArrayList<Plugin>();
        for (var p : plugins) {
            pis.add(create(p));
        }
        return pis;
    }

    @Override
    public PluginId getIdentifier() {
        return identifier;
    }

    @Override
    public String getClassName() {
        return className;
    }

}
