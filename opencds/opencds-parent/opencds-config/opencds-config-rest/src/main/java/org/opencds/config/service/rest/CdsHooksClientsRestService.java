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

package org.opencds.config.service.rest;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.xml.bind.JAXBElement;
import org.apache.commons.lang3.StringUtils;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.config.api.ConfigurationService;
import org.opencds.config.api.model.CdsHooksClient;
import org.opencds.config.mapper.CdsHooksClientMapper;
import org.opencds.config.schema.CDSHooksClient;
import org.opencds.config.schema.CdsHooksClients;
import org.opencds.config.schema.Link;
import org.opencds.config.schema.ObjectFactory;
import org.opencds.config.service.rest.util.Responses;

@Path("cdshooksclients")
public class CdsHooksClientsRestService {
    private static final String SELF = "self";
    private static final Log log = LogFactory.getLog(CdsHooksClientsRestService.class);
    private final ConfigurationService configurationService;

    public CdsHooksClientsRestService(ConfigurationService configurationService) {
        this.configurationService = configurationService;
    }

    @GET
    @Produces(MediaType.APPLICATION_XML)
    public CdsHooksClients getCdsHooksClients(@Context UriInfo uriInfo) {
        var clients = CdsHooksClientMapper.external(configurationService.getKnowledgeRepository()
                .getCdsHooksClientService().getAll());
        clients.getCdsHooksClient()
                .forEach(client -> {
                    var link = new Link();
                    link.setRel(SELF);
                    link.setHref(uriInfo.getAbsolutePathBuilder().path(client.getId())
                            .build()
                            .toString());
                    client.setLink(link);
                });
        return clients;
    }

    @POST
    @Consumes(MediaType.APPLICATION_XML)
    public Response createCdsHooksClient(@Context UriInfo uriInfo,
                                         JAXBElement<CDSHooksClient> jaxbElement) {
        var client = jaxbElement.getValue();
        if (found(client.getId())) {
            return Responses.conflict(
                    "CdsHooksClient already exists: id= " + client.getId());
        }
        try {
            configurationService.getKnowledgeRepository().getCdsHooksClientService()
                    .persist(CdsHooksClientMapper.internal(client));
        } catch (Exception e) {
            return Responses.internalServerError(e.getMessage());
        }
        return Responses.created(uriInfo, client.getId());
    }

    @PUT
    @Consumes(MediaType.APPLICATION_XML)
    public Response putCdsHooksClient(JAXBElement<CDSHooksClient> jaxbElement) {
        var client = jaxbElement.getValue();
        try {
            configurationService.getKnowledgeRepository().getCdsHooksClientService()
                    .persist(CdsHooksClientMapper.internal(client));
        } catch (Exception e) {
            log.error(e.getMessage(), e);
            return Responses.internalServerError(e.getMessage());
        }
        return Responses.noContent();
    }

    // /cdshooksclients/<clientId>
    @GET
    @Path("{clientId}")
    @Produces(MediaType.APPLICATION_XML)
    public JAXBElement<CDSHooksClient> getCdsHooksClient(@Context UriInfo uriInfo,
                                                          @PathParam("clientId") String clientId) {
        var client = find(clientId);
        if (client == null) {
            throw new NotFoundException("CdsHooksClient not found: id= " + clientId);
        }
        var external = CdsHooksClientMapper.external(client);
        Link link = new Link();
        link.setRel(SELF);
        link.setHref(uriInfo.getAbsolutePath().toString());
        external.setLink(link);
        return new ObjectFactory().createCdsHooksClient(external);
    }

    @PUT
    @Path("{clientId}")
    @Consumes(MediaType.APPLICATION_XML)
    public Response updateCdsHooksClientId(@Context UriInfo uriInfo,
                                           @PathParam("clientId") String clientId,
                                           JAXBElement<CDSHooksClient> jaxbElement) {
        boolean created = false;
        if (!found(clientId)) {
            created = true;
        }
        var client = jaxbElement.getValue();
        var clientInternal = CdsHooksClientMapper.internal(client);
        // TODO: Push deeper
        if (!StringUtils.equalsIgnoreCase(clientId, clientInternal.id())) {
            return Responses.badRequest("clientId of request and document do not match.");
        }
        try {
            configurationService.getKnowledgeRepository().getCdsHooksClientService().persist(clientInternal);
        } catch (Exception e) {
            return Responses.internalServerError(e.getMessage());
        }
        if (created) {
            return Responses.created(uriInfo, client.getId());
        } else {
            return Responses.ok();
        }
    }

    @DELETE
    @Path("{clientId}")
    public Response deleteCdsHooksClient(@PathParam("clientId") String clientId) {
        if (!found(clientId)) {
            throw new NotFoundException("CdsHooksClient not found: id= " + clientId);
        }
        try {
            configurationService.getKnowledgeRepository().getCdsHooksClientService().delete(clientId);
        } catch (Exception e) {
            return Responses.internalServerError(e.getMessage());
        }
        return Responses.noContent();
    }

    private boolean found(String clientId) {
        return find(clientId) != null;
    }

    private CdsHooksClient find(String clientId) {
        return configurationService.getKnowledgeRepository().getCdsHooksClientService().find(clientId);
    }
}
