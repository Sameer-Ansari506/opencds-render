/*
 * Copyright 2020 OpenCDS.org
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
import org.opencds.config.api.model.PrePostProcessPluginId;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public record PrePostProcessPluginIdImpl(String scopingEntityId,
                                         String businessId,
                                         String version,
                                         List<String> supportingDataIdentifier) implements PrePostProcessPluginId {

    public PrePostProcessPluginIdImpl {
        assert StringUtils.isNotBlank(scopingEntityId);
        assert StringUtils.isNotBlank(businessId);
        assert StringUtils.isNotBlank(version);
        supportingDataIdentifier = supportingDataIdentifier == null ?
                Collections.emptyList() :
                Collections.unmodifiableList(supportingDataIdentifier);
    }

    public static PrePostProcessPluginId create(String scopingEntityId, String businessId, String version,
                                                List<String> supportingDataIdentifier) {
        return new PrePostProcessPluginIdImpl(
                scopingEntityId,
                businessId,
                version,
                supportingDataIdentifier);
    }

    public static PrePostProcessPluginId create(PrePostProcessPluginId pppid) {
        if (pppid == null) {
            return null;
        }
        return create(pppid.getScopingEntityId(), pppid.getBusinessId(), pppid.getVersion(),
                pppid.getSupportingDataIdentifiers());
    }

    public static List<PrePostProcessPluginId> create(List<PrePostProcessPluginId> prePostProcPlugins) {
        if (prePostProcPlugins == null) {
            return null;
        }
        var list = new ArrayList<PrePostProcessPluginId>();
        for (var id : prePostProcPlugins) {
            list.add(create(id));
        }
        return list;
    }

    @Override
    public String getScopingEntityId() {
        return scopingEntityId;
    }

    @Override
    public String getBusinessId() {
        return businessId;
    }

    @Override
    public String getVersion() {
        return version;
    }

    @Override
    public List<String> getSupportingDataIdentifiers() {
        return supportingDataIdentifier;
    }
}
