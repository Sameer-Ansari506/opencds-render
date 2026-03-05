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

import org.opencds.config.api.model.CDMId;
import org.opencds.config.api.model.SecondaryCDM;
import org.opencds.config.api.model.SupportMethod;

import java.util.ArrayList;
import java.util.List;

public record SecondaryCDMImpl(CDMId cdmId,
                               SupportMethod supportMethod) implements SecondaryCDM {
    public SecondaryCDMImpl {
        assert cdmId != null;
        assert supportMethod != null;
    }

    public static SecondaryCDMImpl create(CDMId cdmId, SupportMethod supportMethod) {
        return new SecondaryCDMImpl(
                CDMIdImpl.create(cdmId),
                supportMethod);
    }

    public static SecondaryCDMImpl create(SecondaryCDM scdm) {
        if (scdm == null) {
            return null;
        }
        if (scdm instanceof SecondaryCDMImpl secondaryCDMImpl) {
            return secondaryCDMImpl;
        }
        return create(
                scdm.getCDMId(),
                scdm.getSupportMethod());
    }

    public static List<SecondaryCDM> create(List<SecondaryCDM> secondaryCDMs) {
        if (secondaryCDMs == null) {
            return null;
        }
        var scdms = new ArrayList<SecondaryCDM>();
        for (var scdm : secondaryCDMs) {
            scdms.add(create(scdm));
        }
        return scdms;
    }

    @Override
    public CDMId getCDMId() {
        return cdmId;
    }

    @Override
    public SupportMethod getSupportMethod() {
        return supportMethod;
    }
}
