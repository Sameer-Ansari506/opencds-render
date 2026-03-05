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

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import org.apache.commons.lang3.StringUtils;
import org.opencds.config.api.model.DssOperation;
import org.opencds.config.api.model.ExecutionEngine;

public record ExecutionEngineImpl(String identifier,
                                  String adapter,
                                  String context,
                                  String knowledgeLoader,
                                  String description,
                                  Date timestamp,
                                  String userId,
                                  List<DssOperation> supportedOperations) implements ExecutionEngine {

    public ExecutionEngineImpl {
        assert StringUtils.isNotEmpty(identifier);
        assert StringUtils.isNotEmpty(adapter);
        assert StringUtils.isNotEmpty(context);
        assert StringUtils.isNotEmpty(knowledgeLoader);
        assert StringUtils.isNotEmpty(description);
        assert timestamp != null;
        // required, but not enforced here
        // assert StringUtils.isNotBlank(userId);
        assert supportedOperations != null && !supportedOperations.isEmpty();
        supportedOperations = Collections.unmodifiableList(supportedOperations);
    }

    public static ExecutionEngineImpl create(String identifier,
                                             String adapter,
                                             String context,
                                             String knowledgeLoader,
                                             String description,
                                             Date timestamp,
                                             String userId,
                                             List<DssOperation> supportedOperations) {
        return new ExecutionEngineImpl(
                identifier,
                adapter,
                context,
                knowledgeLoader,
                description,
                timestamp,
                userId,
                new ArrayList<>(supportedOperations));
    }

    public static ExecutionEngineImpl create(ExecutionEngine ee) {
        if (ee == null) {
            return null;
        }
        if (ee instanceof ExecutionEngineImpl executionEngineImpl) {
            return executionEngineImpl;
        }
        return create(
                ee.getIdentifier(),
                ee.getAdapter(),
                ee.getContext(),
                ee.getKnowledgeLoader(),
                ee.getDescription(),
                ee.getTimestamp(),
                ee.getUserId(),
                ee.getSupportedOperations());
    }

    public static List<ExecutionEngineImpl> create(List<ExecutionEngine> ees) {
        if (ees == null) {
            return null;
        }
        var eeis = new ArrayList<ExecutionEngineImpl>();
        for (var ee : ees) {
            eeis.add(create(ee));
        }
        return eeis;
    }

    @Override
    public String getIdentifier() {
        return identifier;
    }

    @Override
    public String getAdapter() {
        return adapter;
    }

    @Override
    public String getContext() {
        return context;
    }

    @Override
    public String getKnowledgeLoader() {
        return knowledgeLoader;
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
    public List<DssOperation> getSupportedOperations() {
        return supportedOperations;
    }

}
