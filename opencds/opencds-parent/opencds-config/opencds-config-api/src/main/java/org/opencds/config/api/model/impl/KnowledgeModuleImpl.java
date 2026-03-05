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
import org.opencds.config.api.model.CDMId;
import org.opencds.config.api.model.CDSHook;
import org.opencds.config.api.model.KMId;
import org.opencds.config.api.model.KMStatus;
import org.opencds.config.api.model.KnowledgeModule;
import org.opencds.config.api.model.PrePostProcessPluginId;
import org.opencds.config.api.model.SSId;
import org.opencds.config.api.model.SecondaryCDM;
import org.opencds.config.api.model.TraitId;

public record KnowledgeModuleImpl(KMId kmId,
                                  KMStatus status,
                                  CDSHook cdsHook,
                                  String executionEngine,
                                  SSId ssId,
                                  CDMId primaryCDM,
                                  List<SecondaryCDM> secondaryCDMs,
                                  String packageType,
                                  String packageId,
                                  boolean preload,
                                  String primaryProcess,
                                  List<TraitId> traitIds,
                                  List<PrePostProcessPluginId> preProcessPluginIds,
                                  List<PrePostProcessPluginId> postProcessPluginIds,
                                  Date timestamp,
                                  String userId) implements KnowledgeModule {
    public KnowledgeModuleImpl {
        assert kmId != null;
        assert status != null;
        assert StringUtils.isNotBlank(executionEngine);
        assert ssId != null;
        assert StringUtils.isNotBlank(packageType);
        assert StringUtils.isNotBlank(packageId);
        assert timestamp != null;
        // required, but we don't enforce it atm
        // assert StringUtils.isNotBlank(userId);
        secondaryCDMs = secondaryCDMs == null ?
                Collections.emptyList() :
                Collections.unmodifiableList(secondaryCDMs);
        traitIds = traitIds == null ?
                Collections.emptyList() :
                Collections.unmodifiableList(traitIds);
        preProcessPluginIds = preProcessPluginIds == null ?
                Collections.emptyList() :
                Collections.unmodifiableList(preProcessPluginIds);
        postProcessPluginIds = postProcessPluginIds == null ?
                Collections.emptyList() :
                Collections.unmodifiableList(postProcessPluginIds);
    }

    public static KnowledgeModuleImpl create(KMId kmId,
                                             KMStatus kmStatus,
                                             CDSHook cdsHook,
                                             String executionEngine,
                                             SSId ssId,
                                             CDMId primaryCDM,
                                             List<SecondaryCDM> secondaryCDMs,
                                             String packageType,
                                             String packageId,
                                             boolean preload,
                                             String primaryProcess,
                                             List<TraitId> traitIds,
                                             List<PrePostProcessPluginId> preProcPlugins,
                                             List<PrePostProcessPluginId> postProcPlugins,
                                             Date timestamp,
                                             String userId) {
        return new KnowledgeModuleImpl(
                KMIdImpl.create(kmId),
                kmStatus,
                CDSHookImpl.create(cdsHook),
                executionEngine,
                SSIdImpl.create(ssId),
                CDMIdImpl.create(primaryCDM),
                SecondaryCDMImpl.create(secondaryCDMs),
                packageType,
                packageId,
                preload,
                primaryProcess,
                TraitIdImpl.create(traitIds),
                PrePostProcessPluginIdImpl.create(preProcPlugins),
                PrePostProcessPluginIdImpl.create(postProcPlugins),
                timestamp,
                userId);
    }

    public static KnowledgeModuleImpl create(KnowledgeModule km) {
        if (km == null) {
            return null;
        }
        if (km instanceof KnowledgeModuleImpl knowledgeModuleImpl) {
            return knowledgeModuleImpl;
        }
        return create(
                km.getKMId(),
                km.getStatus(),
                km.getCDSHook(),
                km.getExecutionEngine(),
                km.getSSId(),
                km.getPrimaryCDM(),
                km.getSecondaryCDMs(),
                km.getPackageType(),
                km.getPackageId(),
                km.isPreload(),
                km.getPrimaryProcess(),
                km.getTraitIds(),
                km.getPreProcessPluginIds(),
                km.getPostProcessPluginIds(),
                km.getTimestamp(),
                km.getUserId());
    }

    public static List<KnowledgeModuleImpl> create(List<KnowledgeModule> kms) {
        if (kms == null) {
            return null;
        }
        var kmis = new ArrayList<KnowledgeModuleImpl>();
        for (var km : kms) {
            kmis.add(create(km));
        }
        return kmis;
    }

    @Override
    public KMId getKMId() {
        return kmId;
    }

    @Override
    public KMStatus getStatus() {
        return status;
    }

    @Override
    public CDSHook getCDSHook() {
        return cdsHook;
    }

    @Override
    public String getExecutionEngine() {
        return executionEngine;
    }

    @Override
    public SSId getSSId() {
        return ssId;
    }

    @Override
    public CDMId getPrimaryCDM() {
        return primaryCDM;
    }

    @Override
    public List<SecondaryCDM> getSecondaryCDMs() {
        return secondaryCDMs;
    }

    @Override
    public String getPackageType() {
        return packageType;
    }

    @Override
    public String getPackageId() {
        return packageId;
    }

    @Override
    public boolean isPreload() {
        return preload;
    }

    @Override
    public String getPrimaryProcess() {
        return primaryProcess;
    }

    @Override
    public List<TraitId> getTraitIds() {
        return traitIds;
    }

    @Override
    public List<PrePostProcessPluginId> getPreProcessPluginIds() {
        return preProcessPluginIds;
    }

    @Override
    public List<PrePostProcessPluginId> getPostProcessPluginIds() {
        return postProcessPluginIds;
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
