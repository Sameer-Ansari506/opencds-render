/*
 * Copyright 2015-2020 OpenCDS.org
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
import org.opencds.config.api.model.ValueSet;

public record ValueSetImpl(String oid,
                           String name) implements ValueSet {

    public ValueSetImpl {
        assert StringUtils.isNotBlank(oid);
    }

    public static ValueSetImpl create(String oid, String name) {
        return new ValueSetImpl(
                oid,
                name);
    }

    public static ValueSetImpl create(ValueSet valueSet) {
        if (valueSet == null) {
            return null;
        }
        if (valueSet instanceof ValueSetImpl valueSetImpl) {
            return valueSetImpl;
        }
        return create(valueSet.getOid(), valueSet.getName());
    }

    @Override
    public String getOid() {
        return oid;
    }

    @Override
    public String getName() {
        return name;
    }
}
