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

import org.opencds.common.cache.CacheRegion;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.KnowledgeModuleDao;
import org.opencds.config.api.model.KMId;
import org.opencds.config.api.model.KnowledgeModule;
import org.opencds.config.api.model.impl.KMIdImpl;
import org.opencds.config.api.service.KnowledgeModuleService;
import org.opencds.config.api.service.KnowledgePackageService;
import org.opencds.config.api.service.SupportingDataService;
import org.opencds.config.api.util.EntityIdentifierUtil;

import java.io.InputStream;
import java.util.List;
import java.util.Map;
import java.util.Observable;
import java.util.Optional;
import java.util.function.Predicate;
import java.util.stream.Collectors;

public class KnowledgeModuleServiceImpl extends Observable implements KnowledgeModuleService {
    private static final CacheRegion<KMId, KnowledgeModule> KNOWLEDGE_MODULE =
            CacheRegion.create(KMId.class, KnowledgeModule.class);

    private final KnowledgeModuleDao dao;
    private final KnowledgePackageService knowledgePackageService;
    private final SupportingDataService supportingDataService;
    private final CacheService cacheService;


    public KnowledgeModuleServiceImpl(KnowledgeModuleDao dao, KnowledgePackageService knowledgePackageService,
                                      SupportingDataService supportingDataService, CacheService cacheService) {
        this.dao = dao;
        this.knowledgePackageService = knowledgePackageService;
        this.supportingDataService = supportingDataService;
        this.cacheService = cacheService;
        cacheService.putAll(KNOWLEDGE_MODULE, buildPairs(this.dao.getAll()));
    }

    @Override
    public KnowledgeModule find(KMId kmId) {
        return cacheService.get(KNOWLEDGE_MODULE, kmId);
    }

    @Override
    public KnowledgeModule find(String stringKmId) {
        return find(KMIdImpl.create(EntityIdentifierUtil.makeEI(stringKmId)));
    }

    /**
     * Retrieve the first KnowledgeModule that matches the predicate.
     */
    @Override
    public KnowledgeModule find(Predicate<? super KnowledgeModule> predicate) {
        return cacheService.getAllValues(KNOWLEDGE_MODULE).stream()
                .filter(predicate)
                .findFirst()
                .orElse(null);
    }

    public List<KnowledgeModule> getAll(Predicate<? super KnowledgeModule> predicate) {
        return cacheService.getAllValues(KNOWLEDGE_MODULE).stream()
                .filter(predicate)
                .collect(Collectors.toList());
    }

    @Override
    public List<KnowledgeModule> getAll() {
        return List.copyOf(cacheService.getAllValues(KNOWLEDGE_MODULE));
    }

    @Override
    public void persist(KnowledgeModule km) {
        dao.persist(km);
        cacheService.put(KNOWLEDGE_MODULE, km.getKMId(), km);
        // will create or update the ConceptService for this KM
        tellObservers(km);
    }

    @Override
    public void persist(List<KnowledgeModule> internal) {
        internal.forEach(this::persist);
    }

    @Override
    public void delete(KMId kmid) {
        KnowledgeModule km = find(kmid);
        if (km != null) {
            dao.delete(km);
            cacheService.evict(KNOWLEDGE_MODULE, km.getKMId());
            knowledgePackageService.deletePackage(km);
            supportingDataService.deleteAll(km.getKMId());
            // will delete the cached ConceptService associated with this KM
            tellObservers(km);
        }
    }

    @Override
    public InputStream getKnowledgePackage(KMId kmId) {
        return Optional.ofNullable(find(kmId))
                .map(knowledgePackageService::getPackageInputStream)
                .orElse(null);
    }

    @Override
    public void deleteKnowledgePackage(KMId kmId) {
        KnowledgeModule km = find(kmId);
        if (km != null) {
            knowledgePackageService.deletePackage(km);
        }
    }

    @Override
    public void persistKnowledgePackage(KMId kmId, InputStream knowledgePackage) {
        KnowledgeModule km = find(kmId);
        if (km != null) {
            knowledgePackageService.persistPackageInputStream(km, knowledgePackage);
        }
    }

    private void tellObservers(KnowledgeModule km) {
        setChanged();
        notifyObservers(km);
    }

    private Map<KMId, KnowledgeModule> buildPairs(List<KnowledgeModule> all) {
        return all.stream()
                .map(km -> Map.entry(km.getKMId(), km))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }
}
