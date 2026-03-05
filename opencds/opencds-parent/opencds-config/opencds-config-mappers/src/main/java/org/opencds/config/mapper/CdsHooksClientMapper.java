package org.opencds.config.mapper;

import org.opencds.config.api.model.CdsHooksClient;
import org.opencds.config.api.model.impl.CdsHooksClientImpl;
import org.opencds.config.schema.CDSHooksClient;
import org.opencds.config.schema.CdsHooksClients;

import java.util.List;

public class CdsHooksClientMapper {
    public static List<CdsHooksClient> internal(CdsHooksClients clients) {
        if (clients == null) {
            return null;
        }
        return clients.getCdsHooksClient().stream()
                .map(CdsHooksClientMapper::internal)
                .toList();
    }

    public static CdsHooksClient internal(CDSHooksClient hooksClient) {
        if (hooksClient == null) {
            return null;
        }
        return CdsHooksClientImpl.create(
                hooksClient.getId(),
                hooksClient.getDescription(),
                IssuersMapper.internal(hooksClient.getIssuers()),
                hooksClient.getTenant());
    }

    public static CDSHooksClient external(CdsHooksClient hooksClient) {
        if (hooksClient == null) {
            return null;
        }
        var cdsHooksClient = new CDSHooksClient();
        cdsHooksClient.setId(hooksClient.id());
        cdsHooksClient.setDescription(hooksClient.description());
        cdsHooksClient.setIssuers(IssuersMapper.external(hooksClient.issuers()));
        cdsHooksClient.setTenant(hooksClient.tenant());
        return cdsHooksClient;
    }

    public static CdsHooksClients external(List<CdsHooksClient> hooksClients) {
        if (hooksClients == null) {
            return null;
        }
        var clients = new CdsHooksClients();
        hooksClients.stream()
                .map(CdsHooksClientMapper::external)
                .forEach(e -> clients.getCdsHooksClient().add(e));
        return clients;
    }
}
