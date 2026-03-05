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

import org.apache.commons.lang3.StringUtils;
import org.apache.commons.lang3.tuple.Pair;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.common.cache.CacheRegion;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.model.CDMId;
import org.opencds.config.api.model.Concept;
import org.opencds.config.api.model.ConceptDeterminationMethod;
import org.opencds.config.api.model.ConceptView;
import org.opencds.config.api.model.KMId;
import org.opencds.config.api.model.KnowledgeModule;
import org.opencds.config.api.model.SupportMethod;
import org.opencds.config.api.model.impl.ConceptViewImpl;
import org.opencds.config.api.service.ConceptDeterminationMethodService;
import org.opencds.config.api.service.ConceptService;
import org.opencds.config.api.service.KnowledgeModuleService;

import java.util.Collection;
import java.util.Collections;
import java.util.Deque;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Observable;
import java.util.Observer;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class ConceptServiceImpl implements ConceptService, Observer {
    private static final Log log = LogFactory.getLog(ConceptServiceImpl.class);
    private static final CacheRegion<KMId, KMConceptService> KM_CONCEPT_SERVICE =
            CacheRegion.create(KMId.class, KMConceptService.class);
    private static final CacheRegion<Concept, ConceptMaps> CONCEPTS =
            CacheRegion.create(Concept.class, ConceptMaps.class);
    private static final CacheRegion<CDMId, ConceptMaps> CONCEPT_MAP_BY_CDMID =
            CacheRegion.create(CDMId.class, ConceptMaps.class);

    private final ConceptDeterminationMethodService conceptDeterminationMethodService;
    private final KnowledgeModuleService knowledgeModuleService;
    private final CacheService cacheService;

    public ConceptServiceImpl(ConceptDeterminationMethodService conceptDeterminationMethodService,
                              KnowledgeModuleService knowledgeModuleService, CacheService cacheService) {
        this.conceptDeterminationMethodService = conceptDeterminationMethodService;
        ((Observable) conceptDeterminationMethodService).addObserver(this);
        log.debug("Added this as observer to service: " + conceptDeterminationMethodService);
        this.knowledgeModuleService = knowledgeModuleService;
//        ((Observable) knowledgeModuleService).addObserver(this);
        log.debug("Added this as observer to service: " + knowledgeModuleService);
        this.cacheService = cacheService;
        // initially load all of them.
        loadConceptMaps();
        loadAllConceptServices(knowledgeModuleService.getAll(), false);
    }

    /**
     * Builds and caches each source {@link Concept} to a {@link List} of target {@link Concept}s
     * as {@link ConceptMap} (as a list of conceptMaps in {@link ConceptMaps}
     */
    private void loadConceptMaps() {
        conceptDeterminationMethodService.getAll()
                .forEach(this::resolveConceptMaps);
    }

    private void reloadConceptMaps() {
        cacheService.evictAll(CONCEPTS);
    }

    private void deleteConceptService(KnowledgeModule knowledgeModule) {
        if (cacheService.containsKey(KM_CONCEPT_SERVICE, knowledgeModule.getKMId())) {
            log.debug("Evicting cached Concept Service");
            cacheService.evict(KM_CONCEPT_SERVICE, knowledgeModule.getKMId());
        }
    }

    private void reloadAllConceptServices(List<KnowledgeModule> knowledgeModules) {
        loadAllConceptServices(knowledgeModules, true);
    }

    private void reloadConceptServiceForKM(KnowledgeModule knowledgeModule) {
        deleteConceptService(knowledgeModule);
        cacheConceptServiceByKM(knowledgeModule);
        log.debug("Reloaded concept service cache for KM: " + knowledgeModule.getKMId());
    }

    @Override
    public List<ConceptView> getConceptViews(String codeSystem, String code) {
        if (log.isDebugEnabled())
            log.debug("Finding concept in conceptMaps: codeSystem= " + codeSystem + ", code= " + code);
        return cacheService.getAllKeys(CONCEPTS).stream()
                .filter(c -> StringUtils.equalsIgnoreCase(c.getCodeSystem(), codeSystem))
                .filter(c -> StringUtils.equalsIgnoreCase(c.getCode(), code))
                .map(c -> cacheService.get(CONCEPTS, c))
                .map(ConceptMaps::conceptMaps)
                .flatMap(Collection::stream)
                .map(cm -> ConceptViewImpl.create(cm.toConcept(), cm.cdmCode()))
                .map(cvi -> (ConceptView) cvi)
                .toList();
    }

    @Override
    public ConceptService byKM(KnowledgeModule knowledgeModule) {
        return Optional.ofNullable(knowledgeModule)
                .map(KnowledgeModule::getKMId)
                .map(kmId -> cacheService.get(KM_CONCEPT_SERVICE, kmId))
                .orElseGet(() -> cacheConceptServiceByKM(knowledgeModule));
    }

    @Override
    public void update(Observable o, Object arg) {
        log.debug("Called by object: " + o);
        if (arg == null) {
            reloadConceptMaps();
            reloadAllConceptServices(knowledgeModuleService.getAll());
            log.debug("Reloaded all ConceptServices");
        } else if (arg instanceof KnowledgeModule km) {
            // we check whether the KM was removed
            if (knowledgeModuleService.find(km.getKMId()) == null) {
                deleteConceptService(km);
                log.debug("Deleted concept service for KM: " + km.getKMId());
            } else {
                reloadConceptServiceForKM(km);
                log.debug("Reloaded concept service for KM: " + km.getKMId());
            }
        }
    }

    private void loadAllConceptServices(List<KnowledgeModule> knowledgeModules, boolean purge) {
        // TODO: Purge (rework reload)
        knowledgeModules.forEach(this::cacheConceptServiceByKM);
    }

    private KMConceptService cacheConceptServiceByKM(KnowledgeModule knowledgeModule) {
        var conceptMaps = buildKMSpecificConceptMaps(knowledgeModule);
        log.debug("KM " + knowledgeModule.getKMId() + " gets conceptMap: " + conceptMaps.hashCode());
        KMConceptService cs = new KMConceptService(conceptMaps);
        cacheService.put(KM_CONCEPT_SERVICE, knowledgeModule.getKMId(), cs);
//        KM_CONCEPT_SERVICE
        return cs;
    }

    /**
     * Build the concept maps.
     * <p>
     * If the KM doesn't have an associated Primary CDM:
     * <ul>
     * <li>the cache is checked for the ALL_CONCEPTS conceptMaps</li>
     * <ul>
     * <li>if this exists, then the ALL_CONCEPTS conceptMaps are returned.</li>
     * <li>if not, then the ALL_CONCEPTS is created and cached, and then
     * returned.</li>
     * </ul>
     * <li>any secondary CDMs are ignored in this case</li> </ul>
     * <p>
     * If the KM has an associated Primary CDM, a new conceptMaps is built and
     * returned.
     * <p>
     * The returned value is an unmodifiable map (from Collections).
     */
    private Map<Concept, ConceptMaps> buildKMSpecificConceptMaps(KnowledgeModule km) {
        return Optional.ofNullable(km)
                .map(KnowledgeModule::getPrimaryCDM)
                .map(primaryCDMId -> applyOperations(conceptMapByCDMId(primaryCDMId), buildOperationsDeque(km)))
                .map(this::buildConceptMaps)
                .orElseGet(() -> cacheService.getAll(CONCEPTS));
    }

    private Map<Concept, ConceptMaps> buildConceptMaps(Map<Concept, Set<ConceptMap>> conceptSetMap) {
        return conceptSetMap.entrySet().stream()
                .map(e -> Map.entry(
                        e.getKey(),
                        ConceptMaps.create(e.getValue())))
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        Map.Entry::getValue));
    }

    private Deque<Operation> buildOperationsDeque(KnowledgeModule km) {
        return Optional.ofNullable(km)
                .map(KnowledgeModule::getSecondaryCDMs)
                .stream()
                .flatMap(Collection::stream)
                .map(sec -> Pair.of(
                        sec,
                        conceptDeterminationMethodService.find(sec.getCDMId())))
                .filter(pair -> {
                    if (pair.getRight() == null) {
                        log.error("secondaryCDM specified by KM does not exist: km='" + km.getKMId() +
                                "', secondaryCDM='" + pair.getLeft() + "'");
                        return false;
                    }
                    return true;
                })
                .map(pair -> Pair.of(
                        pair.getLeft(),
                        conceptMapByCDMId(pair.getRight().getCDMId())))
                .map(pair -> Operation.create(
                        pair.getLeft().getSupportMethod(),
                        pair.getRight()))
                .collect(Collectors.toCollection(LinkedList::new));
    }

    private Map<Concept, Set<ConceptMap>> conceptMapByCDMId(CDMId primaryCDMId) {
        return cacheService.get(CONCEPT_MAP_BY_CDMID, primaryCDMId).conceptMaps().stream()
                .map(cm -> Map.entry(cm.fromConcept(), cm))
                .collect(Collectors.groupingBy(Map.Entry::getKey,
                        Collectors.mapping(Map.Entry::getValue, Collectors.toSet())));
    }

    private Map<Concept, Set<ConceptMap>> applyOperations(Map<Concept, Set<ConceptMap>> primaries,
                                                          Deque<Operation> operations) {
        if (operations.isEmpty()) {
            return primaries;
        }
        var op = operations.pollFirst();
        return applyOperations(applyOperation(primaries, op), operations);
    }

    private Map<Concept, Set<ConceptMap>> applyOperation(Map<Concept, Set<ConceptMap>> primaries,
                                                         Operation operation) {
        return switch (operation.supportMethod()) {
            case ADDITIVE -> add(primaries, operation.secondaries());
            case REPLACEMENT -> replace(primaries, operation.secondaries());
            case RETRACTIVE -> retract(primaries, operation.secondaries());
        };
    }

    private Map<Concept, Set<ConceptMap>> add(Map<Concept, Set<ConceptMap>> primaries,
                                              Map<Concept, Set<ConceptMap>> secondaries) {
        return primaries.entrySet().stream()
                .map(entry -> {
                    if (secondaries.containsKey(entry.getKey())) {
                        var secondaryCM = secondaries.get(entry.getKey());
                        return Map.entry(entry.getKey(),
                                Stream.concat(
                                                entry.getValue().stream(),
                                                secondaryCM.stream())
                                        .collect(Collectors.toUnmodifiableSet()));
                    }
                    return entry;
                })
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private Map<Concept, Set<ConceptMap>> replace(Map<Concept, Set<ConceptMap>> primaries,
                                                  Map<Concept, Set<ConceptMap>> secondaries) {
        return primaries.entrySet().stream()
                .map(entry -> Optional.of(secondaries)
                        .filter(secs -> secs.containsKey(entry.getKey()))
                        .map(secs -> Map.entry(entry.getKey(), secs.get(entry.getKey())))
                        .orElse(entry))
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private Map<Concept, Set<ConceptMap>> retract(Map<Concept, Set<ConceptMap>> primaries,
                                                  Map<Concept, Set<ConceptMap>> secondaries) {
        return primaries.entrySet().stream()
                .map(primaryEntry -> {
                    var secondaryConceptMaps = secondaries.getOrDefault(primaryEntry.getKey(), Set.of());
                    return Map.entry(
                            primaryEntry.getKey(),
                            primaryEntry.getValue().stream()
                                    .filter(cm -> !secondaryConceptMaps.contains(cm))
                                    .collect(Collectors.toSet()));
                })
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private record Operation(SupportMethod supportMethod,
                             Map<Concept, Set<ConceptMap>> secondaries) {
        private Operation {
            assert supportMethod != null;
            secondaries = secondaries == null ? Map.of() : secondaries;
        }

        public static Operation create(SupportMethod supportMethod,
                                       Map<Concept, Set<ConceptMap>> secondaries) {
            return new Operation(supportMethod, secondaries);
        }
    }

    /*
     * Extract the concepts from the mappings; flatten out the hierarchy for the
     * given CDM Once the ConceptMappings are extracted, we no longer need the
     * CDM.
     */
    private void resolveConceptMaps(ConceptDeterminationMethod cdm) {
        log.debug("Resolving concept for CDM : " + cdm.getCDMId());
        buildConceptMapsByFromConcept(cdm);
        buildConceptMapsByCDMId(cdm);
    }

    private void buildConceptMapsByFromConcept(ConceptDeterminationMethod cdm) {
        var cdmCode = cdm.getCDMId().getCode();
        Optional.ofNullable(cdm.getConceptMappings())
                .stream().parallel()
                .flatMap(Collection::stream)
                .flatMap(mapping ->
                        mapping.getFromConcepts().stream()
                                .map(fromConcept -> ConceptMap.create(
                                        mapping.getToConcept(),
                                        fromConcept,
                                        cdmCode)))
                .map(conceptMap -> Map.entry(conceptMap.fromConcept, conceptMap))
                .collect(Collectors.groupingByConcurrent(
                        Map.Entry::getKey,
                        Collectors.mapping(Map.Entry::getValue, Collectors.toSet())
                )).entrySet().stream()
                .collect(Collectors.toMap(Map.Entry::getKey, e -> ConceptMaps.create(e.getValue())))
                .forEach((fromConcept, conceptMaps) ->
                        cacheService.put(CONCEPTS, fromConcept, conceptMaps));
    }

    private void buildConceptMapsByCDMId(ConceptDeterminationMethod cdm) {
        Optional.ofNullable(cacheService.getAll(CONCEPTS))
                .map(Map::entrySet)
                .map(Collection::stream)
                .map(stream -> stream.map(Map.Entry::getValue)
                        .map(ConceptMaps::conceptMaps)
                        .flatMap(Collection::stream)
                        .collect(Collectors.toSet()))
                .map(ConceptMaps::create)
                .ifPresent(conceptMaps -> cacheService.put(
                        CONCEPT_MAP_BY_CDMID,
                        cdm.getCDMId(),
                        conceptMaps));
    }

    public record ConceptMaps(Set<ConceptMap> conceptMaps) {
        public ConceptMaps {
            conceptMaps = conceptMaps == null ? Set.of() : Collections.unmodifiableSet(conceptMaps);
        }

        public static ConceptMaps create(Set<ConceptMap> conceptMapSet) {
            return new ConceptMaps(conceptMapSet);
        }
    }

    public record ConceptMap(Concept toConcept,
                             Concept fromConcept,
                             String cdmCode) {
        public static ConceptMap create(Concept toConcept, Concept fromConcept, String cdmCode) {
            return new ConceptMap(toConcept, fromConcept, cdmCode);
        }
    }

    public static class KMConceptService implements ConceptService {
        private final Map<Concept, ConceptMaps> conceptMaps;

        public KMConceptService(Map<Concept, ConceptMaps> conceptMaps) {
            this.conceptMaps = conceptMaps;
        }

        public List<ConceptView> getConceptViews(String codeSystem, String code) {
            if (log.isDebugEnabled())
                log.debug("Finding concept in conceptMaps: codeSystem= " + codeSystem + ", code= " + code);
            return conceptMaps.keySet().stream()
                    .filter(c -> StringUtils.equalsIgnoreCase(c.getCodeSystem(), codeSystem))
                    .filter(c -> StringUtils.equalsIgnoreCase(c.getCode(), code))
                    .map(conceptMaps::get)
                    .map(ConceptMaps::conceptMaps)
                    .flatMap(Collection::stream)
                    .map(cm -> ConceptViewImpl.create(cm.toConcept(), cm.cdmCode()))
                    .map(cvi -> (ConceptView) cvi)
                    .toList();
        }

        @Override
        public ConceptService byKM(KnowledgeModule knowledgeModule) {
            return this;
        }
    }

}
