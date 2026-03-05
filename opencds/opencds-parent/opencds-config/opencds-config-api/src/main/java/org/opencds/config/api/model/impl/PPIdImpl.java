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

import org.opencds.config.api.model.PPId;

public record PPIdImpl(String scopingEntityId,
                      String businessId,
                      String version) implements PPId {

    public static PPIdImpl create(String scopingEntityId,
                                  String businessId,
                                  String version) {
        return new PPIdImpl(
                scopingEntityId,
                businessId,
                version);
    }

    public static PPIdImpl create(PPId pluginPackageid) {
        if (pluginPackageid == null) {
            return null;
        }
        if (pluginPackageid instanceof PPIdImpl ppIdImpl) {
            return ppIdImpl;
        }
        return create(
                pluginPackageid.getScopingEntityId(),
                pluginPackageid.getBusinessId(),
                pluginPackageid.getVersion());
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
