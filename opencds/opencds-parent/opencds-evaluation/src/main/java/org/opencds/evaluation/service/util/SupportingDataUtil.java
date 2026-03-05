/*
 * Copyright 2016-2020 OpenCDS.org
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

package org.opencds.evaluation.service.util;

import org.opencds.config.api.KnowledgeRepository;
import org.opencds.config.api.model.KMId;
import org.opencds.config.api.model.KnowledgeModule;
import org.opencds.config.api.model.SupportingData;
import org.opencds.config.api.service.SupportingDataPackageService;
import org.opencds.config.api.util.EntityIdentifierUtil;
import org.opencds.plugin.api.SupportingDataPackage;

import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import java.util.stream.Collectors;

public class SupportingDataUtil {

    /**
     * Retrieves all relevant SupportingData, i.e., SDs that are associated with
     * the KnowledgeModule or SDs that have no associated KM.
     * <p>
     * See documentation referenced by OP-41.
     *
     * @param knowledgeRepository
     * @param knowledgeModule
     * @return
     */
    public static Map<String, org.opencds.plugin.api.SupportingData> getSupportingData(
            KnowledgeRepository knowledgeRepository,
            KnowledgeModule knowledgeModule) {
        return filterByKM(
                knowledgeModule.getKMId(),
                knowledgeRepository.getSupportingDataService().getAll()).
                stream()
                .map(sd -> Map.entry(
                        sd.getIdentifier(),
                        org.opencds.plugin.api.SupportingData.create(
                                sd.getIdentifier(),
                                EntityIdentifierUtil.makeEIString(sd.getKMId()),
                                EntityIdentifierUtil.makeEIString(sd.getLoadedBy()),
                                sd.getPackageId(),
                                sd.getPackageType(),
                                sd.getTimestamp(),
                                supportingDataPackageSupplier(knowledgeRepository.getSupportingDataPackageService(), sd)
                        )))
                .collect(Collectors.toUnmodifiableMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    private static Supplier<SupportingDataPackage> supportingDataPackageSupplier(SupportingDataPackageService supportingDataPackageService, SupportingData sd) {
        return () -> new SupportingDataPackage(
                () -> supportingDataPackageService.getFile(sd),
                () -> supportingDataPackageService.getPackageBytes(sd));
    }

    /**
     * Inclusion filter by SupportingData by KMId, or SDs that have no
     * associated KMId.
     *
     * @param kmId
     * @param sds
     * @return
     */
    private static List<SupportingData> filterByKM(KMId kmId, List<SupportingData> sds) {
        return sds.stream()
                .filter(sd -> sd.getKMId() == null || (sd.getKMId() != null && sd.getKMId().equals(kmId)))
                .toList();
    }

}
