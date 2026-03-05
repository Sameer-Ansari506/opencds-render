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
import org.opencds.config.api.model.CDSHook;
import org.opencds.config.api.model.FhirVersion;
import org.opencds.config.api.model.Prefetch;

import java.util.List;

public record CDSHookImpl(String hook,
                          String id,
                          String title,
                          String description,
                          List<String> clientIds,
                          Prefetch prefetch,
                          FhirVersion fhirVersion) implements CDSHook {
    public CDSHookImpl {
        assert StringUtils.isNotBlank(hook);
        assert StringUtils.isNotBlank(id);
        assert StringUtils.isNotBlank(description);
        assert fhirVersion != null;
        clientIds = clientIds == null ? List.of() : List.copyOf(clientIds);
        prefetch = prefetch == null ? PrefetchImpl.empty() : prefetch;
    }

    public static CDSHook create(String hook,
                                 String id,
                                 String title,
                                 String description,
                                 List<String> clientIds,
                                 Prefetch prefetch,
                                 FhirVersion fhirVersion) {
        return new CDSHookImpl(
                hook,
                id,
                title,
                description,
                clientIds,
                PrefetchImpl.create(prefetch),
                fhirVersion);
    }

    public static CDSHook create(CDSHook cdsHook) {
        if (cdsHook == null) {
            return null;
        }
        if (cdsHook instanceof CDSHookImpl cdsHookImpl) {
            return cdsHookImpl;
        }
        return create(
                cdsHook.getHook(),
                cdsHook.getId(),
                cdsHook.getTitle(),
                cdsHook.getDescription(),
                cdsHook.getClientIds(),
                cdsHook.getPrefetch(),
                cdsHook.getFhirVersion());
    }

    @Override
    public String getHook() {
        return hook;
    }

    @Override
    public String getId() {
        return id;
    }

    @Override
    public String getTitle() {
        return title;
    }

    @Override
    public String getDescription() {
        return description;
    }

    @Override
    public List<String> getClientIds() {
        return clientIds;
    }

    @Override
    public Prefetch getPrefetch() {
        return prefetch;
    }

    public FhirVersion getFhirVersion() {
        return fhirVersion;
    }

}
