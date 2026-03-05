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

import org.apache.commons.lang3.tuple.Pair;
import org.opencds.common.cache.CacheRegion;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.ConceptDeterminationMethodDao;
import org.opencds.config.api.model.CDMId;
import org.opencds.config.api.model.ConceptDeterminationMethod;
import org.opencds.config.api.model.SecondaryCDM;
import org.opencds.config.api.model.SupportMethod;
import org.opencds.config.api.service.ConceptDeterminationMethodService;

import java.util.List;
import java.util.Map;
import java.util.Observable;
import java.util.function.Function;
import java.util.stream.Collectors;

public class ConceptDeterminationMethodServiceImpl extends Observable implements ConceptDeterminationMethodService {
    private static final CacheRegion<CDMId, ConceptDeterminationMethod> CDM =
            CacheRegion.create(CDMId.class, ConceptDeterminationMethod.class);

    private final ConceptDeterminationMethodDao dao;
    private final CacheService cacheService;


    public ConceptDeterminationMethodServiceImpl(ConceptDeterminationMethodDao dao, CacheService cacheService) {
        this.dao = dao;
        this.cacheService = cacheService;
        this.cacheService.putAll(CDM, buildPairs(this.dao.getAll()));
    }

    @Override
    public ConceptDeterminationMethod find(CDMId cdmId) {
        return cacheService.get(CDM, cdmId);
    }

    @Override
    public List<ConceptDeterminationMethod> getAll() {
        return List.copyOf(cacheService.getAllValues(CDM));
    }

    @Override
    public void persist(ConceptDeterminationMethod cdm) {
        dao.persist(cdm);
        cacheService.put(CDM, cdm.getCDMId(), cdm);
        // will reload all ConceptServices for all KMs
        tellObservers();
    }

    @Override
    public void persist(List<ConceptDeterminationMethod> internal) {
        dao.persist(internal);
        cacheService.putAll(CDM, buildPairs(internal));
        tellObservers();
    }

    @Override
    public void delete(CDMId cdmId) {
        ConceptDeterminationMethod cdm = find(cdmId);
        if (cdm != null) {
            dao.delete(cdm);
            cacheService.evict(CDM, cdm.getCDMId());
            tellObservers();
        }
    }

    @Override
    public Map<ConceptDeterminationMethod, SupportMethod> find(List<SecondaryCDM> secondaryCDMs) {
        return secondaryCDMs.stream()
                .map(sec -> Pair.of(find(sec.getCDMId()), sec.getSupportMethod()))
                .filter(pair -> pair.getLeft() != null)
                .collect(Collectors.toUnmodifiableMap(Pair::getLeft, Pair::getRight));
    }

    private void tellObservers() {
        setChanged();
        notifyObservers();
    }

    private Map<CDMId, ConceptDeterminationMethod> buildPairs(List<ConceptDeterminationMethod> cdms) {
        return cdms.stream()
                .collect(Collectors.toUnmodifiableMap(
                        ConceptDeterminationMethod::getCDMId,
                        Function.identity()));
    }
}
