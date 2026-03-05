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

package org.opencds.config.api;

import org.opencds.common.cache.CacheRegion;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.model.PluginId;
import org.opencds.config.api.service.CdsHooksClientService;
import org.opencds.config.api.service.ConceptDeterminationMethodService;
import org.opencds.config.api.service.ConceptService;
import org.opencds.config.api.service.ExecutionEngineService;
import org.opencds.config.api.service.KnowledgeModuleService;
import org.opencds.config.api.service.KnowledgePackageService;
import org.opencds.config.api.service.PluginPackageService;
import org.opencds.config.api.service.SemanticSignifierService;
import org.opencds.config.api.service.SupportingDataPackageService;
import org.opencds.config.api.service.SupportingDataService;
import org.opencds.plugin.api.PluginDataCache;
import org.opencds.plugin.support.PluginDataCacheImpl;

public class KnowledgeRepositoryService implements KnowledgeRepository {
    private static final CacheRegion<PluginId, PluginDataCache> PLUGIN_DATA =
            CacheRegion.create(PluginId.class, PluginDataCache.class);

    private final ConceptDeterminationMethodService conceptDeterminationMethodService;
    private final ConceptService conceptService;
    private final ExecutionEngineService executionEngineService;
    private final KnowledgeModuleService knowledgeModuleService;
    private final KnowledgePackageService knowledgePackageService;
    private final PluginPackageService pluginPackageService;
    private final SemanticSignifierService semanticSignifierService;
    private final SupportingDataService supportingDataService;
    private final SupportingDataPackageService supportingDataPackageService;
    private final CdsHooksClientService cdsHooksClientService;
    private final CacheService cacheService;

    public KnowledgeRepositoryService(ConceptDeterminationMethodService conceptDeterminationMethodService,
                                      ConceptService conceptService,
                                      ExecutionEngineService executionEngineService,
                                      KnowledgeModuleService knowledgeModuleService,
                                      KnowledgePackageService knowledgePackageService,
                                      PluginPackageService pluginPackageService,
                                      SemanticSignifierService semanticSignifierService,
                                      SupportingDataService supportingDataService,
                                      SupportingDataPackageService supportingDataPackageService,
                                      CdsHooksClientService cdsHooksClientService,
                                      CacheService cacheService) {
        this.conceptDeterminationMethodService = conceptDeterminationMethodService;
        this.conceptService = conceptService;
        this.executionEngineService = executionEngineService;
        this.knowledgeModuleService = knowledgeModuleService;
        this.knowledgePackageService = knowledgePackageService;
        this.pluginPackageService = pluginPackageService;
        this.semanticSignifierService = semanticSignifierService;
        this.supportingDataService = supportingDataService;
        this.supportingDataPackageService = supportingDataPackageService;
        this.cdsHooksClientService = cdsHooksClientService;
        this.cacheService = cacheService;
    }

    @Override
    public ConceptDeterminationMethodService getConceptDeterminationMethodService() {
        return conceptDeterminationMethodService;
    }

    @Override
    public ConceptService getConceptService() {
        return conceptService;
    }

    @Override
    public ExecutionEngineService getExecutionEngineService() {
        return executionEngineService;
    }

    @Override
    public KnowledgeModuleService getKnowledgeModuleService() {
        return knowledgeModuleService;
    }

    @Override
    public KnowledgePackageService getKnowledgePackageService() {
        return knowledgePackageService;
    }

    @Override
    public SemanticSignifierService getSemanticSignifierService() {
        return semanticSignifierService;
    }

    @Override
    public SupportingDataService getSupportingDataService() {
        return supportingDataService;
    }

    @Override
    public SupportingDataPackageService getSupportingDataPackageService() {
        return supportingDataPackageService;
    }

    @Override
    public CdsHooksClientService getCdsHooksClientService() {
        return cdsHooksClientService;
    }

    @Override
    public PluginPackageService getPluginPackageService() {
        return pluginPackageService;
    }

    @Override
    public PluginDataCache getPluginDataCache(PluginId pluginId) {
        var pluginDataCache = cacheService.get(PLUGIN_DATA, pluginId);
        if (pluginDataCache == null) {
            cacheService.put(PLUGIN_DATA, pluginId, new PluginDataCacheImpl());
        }
        return cacheService.get(PLUGIN_DATA, pluginId);
    }
}
