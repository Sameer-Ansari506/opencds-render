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

package org.opencds.config.file;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.config.api.ConfigData;
import org.opencds.config.api.KnowledgeRepository;
import org.opencds.config.api.KnowledgeRepositoryService;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.file.ReadOnlyFileDaoImpl;
import org.opencds.config.api.dao.util.FileUtil;
import org.opencds.config.api.strategy.AbstractConfigStrategy;
import org.opencds.config.api.strategy.ConfigCapability;
import org.opencds.config.file.dao.CdsHooksClientFileDao;
import org.opencds.config.file.dao.ConceptDeterminationMethodFileDao;
import org.opencds.config.file.dao.ExecutionEngineFileDao;
import org.opencds.config.file.dao.KnowledgeModuleFileDao;
import org.opencds.config.file.dao.PluginPackageFileDao;
import org.opencds.config.file.dao.SemanticSignifierFileDao;
import org.opencds.config.file.dao.SupportingDataFileDao;
import org.opencds.config.service.CdsHooksClientServiceImpl;
import org.opencds.config.service.ConceptDeterminationMethodServiceImpl;
import org.opencds.config.service.ConceptServiceImpl;
import org.opencds.config.service.ExecutionEngineServiceImpl;
import org.opencds.config.service.KnowledgeModuleServiceImpl;
import org.opencds.config.service.KnowledgePackageServiceImpl;
import org.opencds.config.service.PluginPackageServiceImpl;
import org.opencds.config.service.SemanticSignifierServiceImpl;
import org.opencds.config.service.SupportingDataPackageServiceImpl;
import org.opencds.config.service.SupportingDataServiceImpl;

import java.nio.file.Paths;
import java.util.HashSet;
import java.util.List;

public class FileConfigStrategy extends AbstractConfigStrategy {
    private static final Log log = LogFactory.getLog(FileConfigStrategy.class);

    public FileConfigStrategy() {
        super(new HashSet<>(List.of(ConfigCapability.RELOAD)), "SIMPLE_FILE");
    }

    @Override
    public KnowledgeRepository getKnowledgeRepository(ConfigData configData, CacheService cacheService) {
        var path = configData.getConfigLocation();
        log.debug("Resolving configuration on path: " + path.toString());
        var resourceUtil = new FileUtil();

        var cdmService = new ConceptDeterminationMethodServiceImpl(
                new ConceptDeterminationMethodFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), CDMS)),
                cacheService);

        var eeService = new ExecutionEngineServiceImpl(
                new ExecutionEngineFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), EXECUTION_ENGINES)),
                cacheService);

        var ppService = new PluginPackageServiceImpl(
                new PluginPackageFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), PLUGIN_DIR)),
                new ReadOnlyFileDaoImpl(
                        resourceUtil,
                        Paths.get(path.toString(), PLUGIN_DIR, PACKAGES)),
                cacheService);

        var sdpService = new SupportingDataPackageServiceImpl(
                new ReadOnlyFileDaoImpl(
                        resourceUtil,
                        Paths.get(path.toString(), SUPPORTING_DATA_DIR, PACKAGES)),
                cacheService);

        var sdService = new SupportingDataServiceImpl(
                new SupportingDataFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), SUPPORTING_DATA_DIR)),
                sdpService,
                cacheService);

        var kpService = new KnowledgePackageServiceImpl(
                eeService,
                new ReadOnlyFileDaoImpl(
                        resourceUtil,
                        Paths.get(path.toString(), KNOWLEDGE_PACKAGE_DIR)),
                cacheService);

        var kmService = new KnowledgeModuleServiceImpl(
                new KnowledgeModuleFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), KNOWLEDGE_MODULES)),
                kpService,
                sdService,
                cacheService);

        var ssService = new SemanticSignifierServiceImpl(
                new SemanticSignifierFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), SEMANTIC_SIGNIFIERS)),
                cacheService);

        var conceptService = new ConceptServiceImpl(cdmService, kmService, cacheService);

        var chkClientService = new CdsHooksClientServiceImpl(
                new CdsHooksClientFileDao(
                        resourceUtil,
                        Paths.get(path.toString(), CDS_HOOKS_CLIENTS)),
                cacheService);

        return new KnowledgeRepositoryService(
                cdmService,
                conceptService,
                eeService,
                kmService,
                kpService,
                ppService,
                ssService,
                sdService,
                sdpService,
                chkClientService,
                cacheService);
    }
}
