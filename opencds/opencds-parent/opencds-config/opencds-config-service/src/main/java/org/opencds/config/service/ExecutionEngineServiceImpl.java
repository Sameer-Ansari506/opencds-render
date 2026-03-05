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

package org.opencds.config.service;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.common.cache.CacheRegion;
import org.opencds.common.utilities.ClassUtil;
import org.opencds.config.api.ExecutionEngineAdapter;
import org.opencds.config.api.ExecutionEngineContext;
import org.opencds.config.api.KnowledgeLoader;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.ExecutionEngineDao;
import org.opencds.config.api.model.ExecutionEngine;
import org.opencds.config.api.service.ExecutionEngineService;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

public class ExecutionEngineServiceImpl implements ExecutionEngineService {
    private static final Log log = LogFactory.getLog(ExecutionEngineServiceImpl.class);
    private static final CacheRegion<String, ExecutionEngine> EXECUTION_ENGINE =
            CacheRegion.create(String.class, ExecutionEngine.class);
    private static final CacheRegion<ExecutionEngine, ExecutionEngineAdapter> EXECUTION_ENGINE_ADAPTER =
            CacheRegion.create(ExecutionEngine.class, ExecutionEngineAdapter.class);
    private static final CacheRegion<ExecutionEngine, Object> EXECUTION_ENGINE_INSTANCE =
            CacheRegion.create(ExecutionEngine.class, Object.class);
    private static final CacheRegion<ExecutionEngine, KnowledgeLoader> KNOWLEDGE_LOADER =
            CacheRegion.create(ExecutionEngine.class, KnowledgeLoader.class);

    private final ExecutionEngineDao dao;
    private final CacheService cacheService;

    public ExecutionEngineServiceImpl(ExecutionEngineDao dao, CacheService cacheService) {
        this.dao = dao;
        this.cacheService = cacheService;
        this.cacheService.putAll(EXECUTION_ENGINE, buildPairs(this.dao.getAll()));
    }

    @Override
    public ExecutionEngine find(String identifier) {
        return cacheService.get(EXECUTION_ENGINE, identifier);
    }

    @Override
    public List<ExecutionEngine> getAll() {
        return List.copyOf(cacheService.getAllValues(EXECUTION_ENGINE));
    }

    @Override
    public void persist(ExecutionEngine ee) {
        dao.persist(ee);
        cacheService.put(EXECUTION_ENGINE, ee.getIdentifier(), ee);
    }

    @Override
    public void persist(List<ExecutionEngine> ees) {
        dao.persist(ees);
        cacheService.putAll(EXECUTION_ENGINE, buildPairs(ees));
    }

    @Override
    public void delete(String identifier) {
        ExecutionEngine ee = find(identifier);
        if (ee != null) {
            dao.delete(ee);
            cacheService.evict(EXECUTION_ENGINE, ee.getIdentifier());
        }
    }

    private Map<String, ExecutionEngine> buildPairs(List<ExecutionEngine> all) {
        Map<String, ExecutionEngine> cacheables = new HashMap<>();
        for (ExecutionEngine ee : all) {
            cacheables.put(ee.getIdentifier(), ee);
        }
        return cacheables;
    }

    @Override
    @Deprecated(forRemoval = true)
    public <T> T getExecutionEngineInstance(ExecutionEngine engine) {
        return Optional.ofNullable((T) cacheService.get(EXECUTION_ENGINE_INSTANCE, engine))
                .orElseGet(() -> {
                    T instance = ClassUtil.newInstance(engine.getIdentifier());
                    cacheService.put(EXECUTION_ENGINE_INSTANCE, engine, instance);
                    return instance;
                });
    }

    @Override
    public <I, O, P, E extends ExecutionEngineAdapter<I, O, P>> E getExecutionEngineAdapter(ExecutionEngine engine) {
        return Optional.ofNullable((E) cacheService.get(EXECUTION_ENGINE_ADAPTER, engine))
                .orElseGet(() -> {
                    if (engine.getAdapter() == null) {
                        return null;
                    }
                    E instance = ClassUtil.newInstance(engine.getAdapter());
                    cacheService.put(EXECUTION_ENGINE_ADAPTER, engine, instance);
                    return instance;
                });
    }

    @Override
    public <I, O, C extends ExecutionEngineContext<I, O>> C createContext(ExecutionEngine engine) {
        return ClassUtil.newInstance(engine.getContext());
    }

    @Override
    public <I, O, KL extends KnowledgeLoader<I, O>> KL getKnowledgeLoader(ExecutionEngine engine) {
        return Optional.ofNullable((KL) cacheService.get(KNOWLEDGE_LOADER, engine))
                .orElseGet(() -> {
                    var kLoader = Optional.ofNullable(engine.getKnowledgeLoader())
                            .orElseGet(engine::getIdentifier);
                    KL instance = ClassUtil.newInstance(kLoader);
                    cacheService.put(KNOWLEDGE_LOADER, engine, instance);
                    return instance;
                });
    }
}
