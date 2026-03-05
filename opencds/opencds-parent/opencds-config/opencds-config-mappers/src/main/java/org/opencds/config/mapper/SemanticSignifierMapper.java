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

package org.opencds.config.mapper;

import org.opencds.common.utilities.XMLDateUtility;
import org.opencds.config.api.model.SSId;
import org.opencds.config.api.model.SemanticSignifier;
import org.opencds.config.api.model.impl.SSIdImpl;
import org.opencds.config.api.model.impl.SemanticSignifierImpl;
import org.opencds.config.schema.SemanticSignifierId;
import org.opencds.config.schema.SemanticSignifiers;

import java.util.ArrayList;
import java.util.List;

public abstract class SemanticSignifierMapper {

    public static SemanticSignifier internal(org.opencds.config.schema.SemanticSignifier external) {
        if (external == null) {
            return null;
        }
        SSId ssid = SSIdImpl.create(external.getIdentifier().getScopingEntityId(), external.getIdentifier()
                .getBusinessId(), external.getIdentifier().getVersion());

        return SemanticSignifierImpl.create(
                ssid,
                external.getName(),
                external.getDescription(),
                external.getEntryPoint(),
                external.getExitPoint(),
                external.getFactListsBuilder(),
                external.getResultSetBuilder(),
                external.getTimestamp().toGregorianCalendar().getTime(),
                external.getUserId());

    }

    public static List<SemanticSignifier> internal(SemanticSignifiers semanticSignifiers) {
        if (semanticSignifiers == null || semanticSignifiers.getSemanticSignifier() == null) {
            return null;
        }
        List<SemanticSignifier> internalSSes = new ArrayList<>();
        for (org.opencds.config.schema.SemanticSignifier ss : semanticSignifiers.getSemanticSignifier()) {
            internalSSes.add(internal(ss));
        }
        return internalSSes;
    }

    public static org.opencds.config.schema.SemanticSignifier external(SemanticSignifier internal) {
        if (internal == null) {
            return null;
        }
        org.opencds.config.schema.SemanticSignifier external = new org.opencds.config.schema.SemanticSignifier();

        external.setName(internal.getName());
        external.setDescription(internal.getDescription());
        external.setEntryPoint(internal.getEntryPoint());
        external.setExitPoint(internal.getExitPoint());
        external.setFactListsBuilder(internal.getFactListsBuilder());
        external.setResultSetBuilder(internal.getResultSetBuilder());
        external.setTimestamp(XMLDateUtility.date2XMLGregorian(internal.getTimestamp()));
        external.setUserId(internal.getUserId());

        SemanticSignifierId externalSSId = new SemanticSignifierId();
        externalSSId.setBusinessId(internal.getSSId().getBusinessId());
        externalSSId.setScopingEntityId(internal.getSSId().getScopingEntityId());
        externalSSId.setVersion(internal.getSSId().getVersion());
        external.setIdentifier(externalSSId);

        return external;
    }

    public static SemanticSignifiers external(List<SemanticSignifier> sses) {
        SemanticSignifiers externalSSes = new SemanticSignifiers();
        for (SemanticSignifier ss : sses) {
            externalSSes.getSemanticSignifier().add(external(ss));
        }
        return externalSSes;
    }

}
