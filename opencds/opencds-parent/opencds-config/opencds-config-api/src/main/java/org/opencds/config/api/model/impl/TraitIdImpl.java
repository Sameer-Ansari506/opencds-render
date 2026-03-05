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

import org.opencds.config.api.model.TraitId;

import java.util.ArrayList;
import java.util.List;

public record TraitIdImpl(String scopingEntityId,
                          String businessId,
                          String version) implements TraitId {

    public static TraitIdImpl create(String scopingEntityId,
                                     String businessId,
                                     String version) {
        return new TraitIdImpl(
                scopingEntityId,
                businessId,
                version);
    }

    public static TraitIdImpl create(TraitId traitId) {
        if (traitId == null) {
            return null;
        }
        if (traitId instanceof TraitIdImpl traitIdImpl) {
            return traitIdImpl;
        }
        return create(
                traitId.getScopingEntityId(),
                traitId.getBusinessId(),
                traitId.getVersion());
    }

    public static List<TraitId> create(List<TraitId> traitIds) {
        if (traitIds == null) {
            return null;
        }
        var tids = new ArrayList<TraitId>();
        for (var tid : traitIds) {
            tids.add(create(tid));
        }
        return tids;
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
}
