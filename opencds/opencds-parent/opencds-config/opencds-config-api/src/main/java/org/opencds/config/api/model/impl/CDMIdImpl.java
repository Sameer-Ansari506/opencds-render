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
import org.opencds.config.api.model.CDMId;

public record CDMIdImpl(String codeSystem,
                        String code,
                        String version) implements CDMId {
    public CDMIdImpl {
        assert StringUtils.isNotBlank(code);
    }

    public static CDMIdImpl create(String codeSystem, String code, String version) {
        return new CDMIdImpl(codeSystem, code, version);
    }

    public static CDMIdImpl create(CDMId cdmId) {
        if (cdmId == null) {
            return null;
        }
        if (cdmId instanceof CDMIdImpl cdmIdImpl) {
            return cdmIdImpl;
        }
        return create(
                cdmId.getCodeSystem(),
                cdmId.getCode(),
                cdmId.getVersion());
    }

    @Override
    public String getCodeSystem() {
        return codeSystem;
    }

    @Override
    public String getCode() {
        return code;
    }

    @Override
    public String getVersion() {
        return version;
    }
}
