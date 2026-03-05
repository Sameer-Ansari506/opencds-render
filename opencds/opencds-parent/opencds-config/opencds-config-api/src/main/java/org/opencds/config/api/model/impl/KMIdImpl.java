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
import org.opencds.config.api.model.EntityIdentifier;
import org.opencds.config.api.model.KMId;

public record KMIdImpl(String scopingEntityId,
                       String businessId,
                       String version) implements KMId {
    public KMIdImpl {
        assert StringUtils.isNotBlank(scopingEntityId);
        assert StringUtils.isNotBlank(businessId);
        assert StringUtils.isNotBlank(version);
    }

    public static KMIdImpl create(String scopingEntityId, String businessId, String version) {
        return new KMIdImpl(
                scopingEntityId,
                businessId,
                version);
    }

    public static KMIdImpl create(KMId kmid) {
        if (kmid == null) {
            return null;
        }
        if (kmid instanceof KMIdImpl kmIdImpl) {
            return kmIdImpl;
        }
        return create(
                kmid.getScopingEntityId(),
                kmid.getBusinessId(),
                kmid.getVersion());
    }

    public static KMId create(EntityIdentifier ei) {
        return create(
                ei.getScopingEntityId(),
                ei.getBusinessId(),
                ei.getVersion());
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
