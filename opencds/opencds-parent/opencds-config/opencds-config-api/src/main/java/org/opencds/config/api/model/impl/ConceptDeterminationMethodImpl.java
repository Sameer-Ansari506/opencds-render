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
import org.opencds.config.api.model.ConceptDeterminationMethod;
import org.opencds.config.api.model.ConceptMapping;

import java.util.Collections;
import java.util.Date;
import java.util.List;

public record ConceptDeterminationMethodImpl(CDMId cdmId,
                                             String displayName,
                                             String description,
                                             Date timestamp,
                                             String userId,
                                             List<ConceptMapping> conceptMappings) implements ConceptDeterminationMethod {

    public ConceptDeterminationMethodImpl {
        assert cdmId != null;
        assert timestamp != null;
        // required, but we don't enforce it atm
        // assert StringUtils.isNotBlank(userId);
        conceptMappings = conceptMappings == null ?
                Collections.emptyList() :
                Collections.unmodifiableList(conceptMappings);
    }

    public static ConceptDeterminationMethodImpl create(CDMId cdmId,
                                                        String displayName,
                                                        String description,
                                                        Date timestamp,
                                                        String userId,
                                                        List<ConceptMapping> conceptMappings) {
        return new ConceptDeterminationMethodImpl(
                CDMIdImpl.create(cdmId),
                displayName,
                description,
                timestamp,
                userId,
                ConceptMappingImpl.create(conceptMappings));
    }

    public static ConceptDeterminationMethodImpl create(ConceptDeterminationMethod cdm) {
        if (cdm == null) {
            return null;
        }
        if (cdm instanceof ConceptDeterminationMethodImpl conceptDeterminationMethodImpl) {
            return conceptDeterminationMethodImpl;
        }
        return create(
                cdm.getCDMId(),
                cdm.getDisplayName(),
                cdm.getDescription(),
                cdm.getTimestamp(),
                cdm.getUserId(),
                cdm.getConceptMappings());
    }

    @Override
    public CDMId getCDMId() {
        return cdmId;
    }

    @Override
    public String getDisplayName() {
        return displayName;
    }

    @Override
    public String getDescription() {
        return description;
    }

    @Override
    public Date getTimestamp() {
        return timestamp;
    }

    @Override
    public String getUserId() {
        return userId;
    }

    @Override
    public List<ConceptMapping> getConceptMappings() {
        return conceptMappings;
    }
}
