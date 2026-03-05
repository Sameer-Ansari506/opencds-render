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

package org.opencds.config.mapper.util;

import jakarta.xml.bind.JAXBContext;
import jakarta.xml.bind.JAXBException;
import jakarta.xml.bind.Marshaller;
import jakarta.xml.bind.Unmarshaller;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.config.api.model.CdsHooksClient;
import org.opencds.config.api.model.ConceptDeterminationMethod;
import org.opencds.config.api.model.ExecutionEngine;
import org.opencds.config.api.model.KnowledgeModule;
import org.opencds.config.api.model.PluginPackage;
import org.opencds.config.api.model.SemanticSignifier;
import org.opencds.config.api.model.SupportingData;
import org.opencds.config.mapper.CdsHooksClientMapper;
import org.opencds.config.mapper.ConceptDeterminationMethodMapper;
import org.opencds.config.mapper.ExecutionEngineMapper;
import org.opencds.config.mapper.KnowledgeModuleMapper;
import org.opencds.config.mapper.PluginPackageMapper;
import org.opencds.config.mapper.SemanticSignifierMapper;
import org.opencds.config.mapper.SupportingDataMapper;
import org.opencds.config.schema.CdsHooksClients;
import org.opencds.config.schema.ConceptDeterminationMethods;
import org.opencds.config.schema.ExecutionEngines;
import org.opencds.config.schema.KnowledgeModules;
import org.opencds.config.schema.PluginPackages;
import org.opencds.config.schema.SemanticSignifiers;
import org.opencds.config.schema.SupportingDataList;

import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;
import java.util.function.Function;
import java.util.function.Supplier;

public class RestConfigUtil {
    private static final Log log = LogFactory.getLog(RestConfigUtil.class);
    private static final String CONFIG_SCHEMA_URL = "org.opencds.config.schema";
    private final JAXBContext jaxbContext;

    public RestConfigUtil() {
        try {
            this.jaxbContext = JAXBContext.newInstance(CONFIG_SCHEMA_URL);
        } catch (JAXBException e) {
            throw new RuntimeException(e);
        }
    }

    public void marshalCdms(List<ConceptDeterminationMethod> cdms, OutputStream os) {
        try {
            var marshaller = jaxbContext.createMarshaller();
            marshaller.setProperty(Marshaller.JAXB_FORMATTED_OUTPUT, Boolean.TRUE);
            marshaller.marshal(ConceptDeterminationMethodMapper.external(cdms), os);
        } catch (Exception e) {
            log.warn("Resource is not an instance of ConceptDeterminationMethods");
        }
    }

    public List<ConceptDeterminationMethod> unmarshalCdms(InputStream is) {
        return unmarshal(
                (ConceptDeterminationMethods cdms) ->
                        ConceptDeterminationMethodMapper.internal(cdms),
                is,
                List::of);
    }

    public ConceptDeterminationMethod unmarshalCdm(InputStream is) {
        return unmarshal(
                (org.opencds.config.schema.ConceptDeterminationMethod cdm) ->
                        ConceptDeterminationMethodMapper.internal(cdm),
                is,
                () -> null);
    }

    public List<ExecutionEngine> unmarshalExecutionEngines(InputStream is) {
        return unmarshal(
                (ExecutionEngines ee) -> ExecutionEngineMapper.internal(ee),
                is,
                List::of);
    }

    public List<KnowledgeModule> unmarshalKnowledgeModules(InputStream is) {
        return unmarshal(
                (KnowledgeModules kms) -> KnowledgeModuleMapper.internal(kms),
                is,
                List::of);
    }

    public List<SemanticSignifier> unmarshalSemanticSignifiers(InputStream is) {
        return unmarshal(
                (SemanticSignifiers ss) -> SemanticSignifierMapper.internal(ss),
                is,
                List::of);
    }

    public SupportingData unmarshalSupportingData(InputStream is) {
        return unmarshal(
                (org.opencds.config.schema.SupportingData sd) -> SupportingDataMapper.internal(sd),
                is,
                () -> null);
    }

    public List<SupportingData> unmarshalSupportingDataList(InputStream is) {
        return unmarshal(
                (SupportingDataList sdl) -> SupportingDataMapper.internal(sdl),
                is,
                List::of);
    }

    public PluginPackage unmarshalPluginPackage(InputStream is) {
        return unmarshal(
                (org.opencds.config.schema.PluginPackage pp) -> PluginPackageMapper.internal(pp),
                is,
                () -> null);
    }

    public List<PluginPackage> unmarshalPluginPackages(InputStream is) {
        return unmarshal(
                (PluginPackages pp) -> PluginPackageMapper.internal(pp),
                is,
                List::of);
    }

    public List<CdsHooksClient> unmarshalCdsHooksClients(InputStream is) {
        return unmarshal(
                (CdsHooksClients c) -> CdsHooksClientMapper.internal(c),
                is,
                List::of);
    }

    public <X, T> T unmarshal(Function<X, T> mapper,
                              InputStream is,
                              Supplier<T> defaultValueSupplier) {
        try {
            //noinspection unchecked
            return mapper.apply((X) unmarshaller().unmarshal(is));
        } catch (Exception e) {
            log.warn("Resource is not an expected instance.");
        } finally {
            log.info("Loaded resource");
        }
        return defaultValueSupplier.get();
    }

    private Unmarshaller unmarshaller() throws JAXBException {
        return jaxbContext.createUnmarshaller();
    }
}
