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
import org.opencds.config.api.model.SSId;
import org.opencds.config.api.model.SemanticSignifier;

import java.util.Date;

public record SemanticSignifierImpl(SSId ssId,
                                    String name,
                                    String description,
                                    String entryPoint,
                                    String exitPoint,
                                    String factListsBuilder,
                                    String resultSetBuilder,
                                    Date timestamp,
                                    String userId) implements SemanticSignifier {
    public SemanticSignifierImpl {
        assert ssId != null;
        assert StringUtils.isNotBlank(name);
        assert StringUtils.isNotBlank(description);
        assert StringUtils.isNotBlank(entryPoint);
        assert StringUtils.isNotBlank(exitPoint);
        assert StringUtils.isNotBlank(factListsBuilder);
        assert timestamp != null;
        // required, but not enforced here
        // assert StringUtils.isNotBlank(userId);
    }

    public static SemanticSignifierImpl create(SSId ssId,
                                               String name,
                                               String description,
                                               String entryPoint,
                                               String exitPoint,
                                               String factListsBuilder,
                                               String resultSetBuilder,
                                               Date timestamp,
                                               String userId) {
        return new SemanticSignifierImpl(
                SSIdImpl.create(ssId),
                name,
                description,
                entryPoint,
                exitPoint,
                factListsBuilder,
                resultSetBuilder,
                timestamp,
                userId);
    }

    public static SemanticSignifierImpl create(SemanticSignifier ss) {
        if (ss == null) {
            return null;
        }
        if (ss instanceof SemanticSignifierImpl semanticSignifierImpl) {
            return semanticSignifierImpl;
        }
        return create(
                ss.getSSId(),
                ss.getName(),
                ss.getDescription(),
                ss.getEntryPoint(),
                ss.getExitPoint(),
                ss.getFactListsBuilder(),
                ss.getResultSetBuilder(),
                ss.getTimestamp(),
                ss.getUserId());
    }

    @Override
    public SSId getSSId() {
        return ssId;
    }

    @Override
    public String getName() {
        return name;
    }

    @Override
    public String getDescription() {
        return description;
    }

    @Override
    public String getEntryPoint() {
        return entryPoint;
    }

    @Override
    public String getExitPoint() {
        return exitPoint;
    }

    @Override
    public String getFactListsBuilder() {
        return factListsBuilder;
    }

    @Override
    public String getResultSetBuilder() {
        return resultSetBuilder;
    }

    @Override
    public Date getTimestamp() {
        return timestamp;
    }

    @Override
    public String getUserId() {
        return userId;
    }
}
