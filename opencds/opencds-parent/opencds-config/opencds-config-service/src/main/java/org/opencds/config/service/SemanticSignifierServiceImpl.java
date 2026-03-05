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
import org.opencds.common.interfaces.ResultSetBuilder;
import org.opencds.common.utilities.ClassUtil;
import org.opencds.config.api.FactListsBuilder;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.SemanticSignifierDao;
import org.opencds.config.api.model.SSId;
import org.opencds.config.api.model.SemanticSignifier;
import org.opencds.config.api.service.SemanticSignifierService;
import org.opencds.config.api.ss.EntryPoint;
import org.opencds.config.api.ss.ExitPoint;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public class SemanticSignifierServiceImpl implements SemanticSignifierService {
    private static final Log log = LogFactory.getLog(SemanticSignifierServiceImpl.class);
    private static final CacheRegion<SSId, SemanticSignifier> SEMANTIC_SIGNIFIER =
            CacheRegion.create(SSId.class, SemanticSignifier.class);
    private static final CacheRegion<SSId, EntryPoint> ENTRY_POINT =
            CacheRegion.create(SSId.class, EntryPoint.class);
    private static final CacheRegion<SSId, ExitPoint> EXIT_POINT =
            CacheRegion.create(SSId.class, ExitPoint.class);
    private static final CacheRegion<SSId, FactListsBuilder> FACT_LISTS_BUILDER =
            CacheRegion.create(SSId.class, FactListsBuilder.class);
    private static final CacheRegion<SSId, ResultSetBuilder> RESULT_SET_BUILDER =
            CacheRegion.create(SSId.class, ResultSetBuilder.class);

    private final SemanticSignifierDao dao;
    private final CacheService cacheService;

    public SemanticSignifierServiceImpl(SemanticSignifierDao dao, CacheService cacheService) {
        this.dao = dao;
        this.cacheService = cacheService;
        List<SemanticSignifier> allSS = this.dao.getAll();
        init(allSS);
    }

    private void init(List<SemanticSignifier> allSS) {
        cacheService.putAll(SEMANTIC_SIGNIFIER, buildPairs(allSS));
        cacheService.putAll(ENTRY_POINT,  buildEntryPointPairs(allSS));
        cacheService.putAll(EXIT_POINT,  buildExitPointPairs(allSS));
        cacheService.putAll(FACT_LISTS_BUILDER, buildFactListsBuilderPairs(allSS));
        cacheService.putAll(RESULT_SET_BUILDER, buildResultSetBuilderPairs(allSS));

    }

	@Override
    public SemanticSignifier find(SSId ssId) {
        return cacheService.get(SEMANTIC_SIGNIFIER, ssId);
    }

    @Override
    public List<SemanticSignifier> getAll() {
        return List.copyOf(cacheService.getAllValues(SEMANTIC_SIGNIFIER));
    }

    @Override
    public void persist(SemanticSignifier ss) {
        dao.persist(ss);
        cacheService.put(SEMANTIC_SIGNIFIER, ss.getSSId(), ss);
        init(this.dao.getAll());
    }

    @Override
    public void persist(List<SemanticSignifier> sses) {
        dao.persist(sses);
        cacheService.putAll(SEMANTIC_SIGNIFIER, buildPairs(sses));
        init(this.dao.getAll());
    }

    @Override
    public void delete(SSId ssId) {
        SemanticSignifier ss = find(ssId);
        if (ss != null) {
            dao.delete(ss);
            cacheService.evict(SEMANTIC_SIGNIFIER, ss.getSSId());
            cacheService.evict(FACT_LISTS_BUILDER, ss.getSSId());
            cacheService.evict(RESULT_SET_BUILDER, ss.getSSId());
        }
    }

    @Override
    public <T, EP extends EntryPoint<T>> EP getEntryPoint(SSId ssId) {
    	return (EP) cacheService.get(ENTRY_POINT, ssId);
    }

    @Override
    public ExitPoint getExitPoint(SSId ssId) {
    	return cacheService.get(EXIT_POINT, ssId);
    }

    @Override
    public FactListsBuilder getFactListsBuilder(SSId ssId) {
        return cacheService.get(FACT_LISTS_BUILDER, ssId);
    }

    @Override
    public <T, RSB extends ResultSetBuilder<T>> RSB getResultSetBuilder(SSId ssId) {
        return (RSB) cacheService.get(RESULT_SET_BUILDER, ssId);
    }

    private Map<SSId, SemanticSignifier> buildPairs(List<SemanticSignifier> all) {
        return all.stream()
                .map(ss -> Map.entry(ss.getSSId(), ss))
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private <MDL, EP extends EntryPoint<MDL>> Map<SSId, EP> buildEntryPointPairs(List<SemanticSignifier> allSS) {
        return allSS.stream()
                .map(ss -> Map.entry(ss.getSSId(), ClassUtil.<EP>newInstance(ss.getEntryPoint())))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }

	private Map<SSId, ExitPoint> buildExitPointPairs(List<SemanticSignifier> allSS) {
        return allSS.stream()
                .map(ss -> Map.entry(ss.getSSId(), ClassUtil.<ExitPoint>newInstance(ss.getExitPoint())))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private Map<SSId, FactListsBuilder> buildFactListsBuilderPairs(List<SemanticSignifier> all) {
        return all.stream()
                .map(ss -> Map.entry(ss.getSSId(), ClassUtil.<FactListsBuilder>newInstance(ss.getFactListsBuilder())))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private <T, RSB extends ResultSetBuilder<T>> Map<SSId, RSB> buildResultSetBuilderPairs(List<SemanticSignifier> all) {
        return all.stream()
                .map(ss -> Map.entry(ss.getSSId(), ClassUtil.<RSB>newInstance(ss.getResultSetBuilder())))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }
}
