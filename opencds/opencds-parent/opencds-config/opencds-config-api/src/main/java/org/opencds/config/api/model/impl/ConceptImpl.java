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
import org.opencds.config.api.model.Concept;
import org.opencds.config.api.model.ValueSet;

import java.util.ArrayList;
import java.util.List;

public record ConceptImpl(String code,
                          String codeSystem,
                          String codeSystemName,
                          String displayName,
                          String comment,
                          ValueSetImpl valueSet) implements Concept {

    public ConceptImpl {
        assert StringUtils.isNotBlank(code);
        assert StringUtils.isNotBlank(codeSystem);
    }

    public static ConceptImpl create(String code, String codeSystem, String codeSystemName, String displayName,
                                     String comment, ValueSet valueSet) {
        return new ConceptImpl(
                code,
                codeSystem,
                codeSystemName,
                displayName,
                comment,
                ValueSetImpl.create(valueSet));
    }

    public static ConceptImpl create(Concept concept) {
        if (concept == null) {
            return null;
        }
        if (concept instanceof ConceptImpl conceptImpl) {
            return conceptImpl;
        }
        return create(
                concept.getCode(),
                concept.getCodeSystem(),
                concept.getCodeSystemName(),
                concept.getDisplayName(),
                concept.getComment(),
                concept.getValueSet());
    }

    public static List<Concept> create(List<Concept> fromConcepts) {
        if (fromConcepts == null) {
            return null;
        }
        var cis = new ArrayList<Concept>();
        for (var c : fromConcepts) {
            cis.add(create(c));
        }
        return cis;
    }

    @Override
    public String getCode() {
        return code;
    }

    @Override
    public String getCodeSystem() {
        return codeSystem;
    }

    @Override
    public String getCodeSystemName() {
        return codeSystemName;
    }

    @Override
    public String getDisplayName() {
        return displayName;
    }

    @Override
    public String getComment() {
        return comment;
    }

    @Override
    public ValueSet getValueSet() {
        return valueSet;
    }
}
