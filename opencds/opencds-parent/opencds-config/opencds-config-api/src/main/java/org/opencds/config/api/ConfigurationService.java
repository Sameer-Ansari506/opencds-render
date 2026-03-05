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

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.common.exceptions.OpenCDSRuntimeException;
import org.opencds.common.utilities.ClassUtil;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.strategy.ConfigStrategy;

import java.util.Set;

/**
 * {@link ConfigurationService} is responsible for interacting with the
 * underlying {@link ConfigStrategy} to perform the following operations:
 * <ol>
 * <li>Build a link to the configuration for the system.</li>
 * <li>Inject the required dependencies into the services this service provides.
 * </li>
 * </ol>
 * <p>
 * The {@link ConfigStrategy} instance is responsible for providing the DAOs
 * used by the services.
 *
 * @author phillip
 */
public class ConfigurationService {
    private static final Log log = LogFactory.getLog(ConfigurationService.class);
    private final ConfigStrategy configStrategy;
    private final Class<? extends CacheService> cacheServiceClass;
    private final ConfigData configData;

    private KnowledgeRepository knowledgeRepository;

    public KnowledgeRepository getKnowledgeRepository() {
        return knowledgeRepository;
    }

    /**
     * The {@link Set} of {@link ConfigStrategy} instances specify the possible
     * configurations this instance of OpenCDS will support. The
     * <tt>configType</tt> and <tt>configPath</tt> may be injected via, e.g.,
     * Spring allowing (externalized) configuration to be specified at startup.
     *
     * @param configStrategies the {@link Set} of {@link ConfigStrategy}
     * @param cacheServiceClass     the {@link CacheService}
     * @param configData       the {@link ConfigData}
     */
    public ConfigurationService(Set<ConfigStrategy> configStrategies,
                                Class<? extends CacheService> cacheServiceClass,
                                ConfigData configData) {
//        initPluginSandbox();
        if (configStrategies == null || configStrategies.isEmpty()) {
            throw new IllegalArgumentException("At least one configuration strategy must be provided.");
        }
        this.cacheServiceClass = cacheServiceClass;
        this.configData = configData;
        ConfigStrategy strategy = null;
        for (ConfigStrategy configStrategy : configStrategies) {
            if (configStrategy.supports(configData.getConfigType())) {
                strategy = configStrategy;
                break;
            }
        }
        if (strategy == null) {
            throw new OpenCDSRuntimeException("Unsupported configuration type: " + configData.getConfigType());
        }
        configStrategy = strategy;
        loadConfiguration();
        log.info("Configuration loaded.");
    }

    private void loadConfiguration() {
        var cacheService = ClassUtil.newInstance(cacheServiceClass);
        var knowledgeRepository = configStrategy.getKnowledgeRepository(configData, cacheService);
        knowledgeRepository.getKnowledgePackageService().preloadKnowledgePackages(knowledgeRepository.getKnowledgeModuleService().getAll());
        this.knowledgeRepository = knowledgeRepository;
    }

    public boolean reloadConfiguration() {
        if (configStrategy.isReloadable()) {
            loadConfiguration();
            log.info("Configuration reloaded");
            return true;
        }
        log.info("Configuration is not reloadable.  (Strategy: " + configStrategy + ")");
        return false;
    }

    public boolean isReloadable() {
        return configStrategy.isReloadable();
    }
}
