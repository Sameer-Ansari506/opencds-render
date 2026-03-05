package org.opencds.config.api.model.impl;

import org.apache.commons.lang3.StringUtils;
import org.opencds.config.api.model.CdsHooksClient;
import org.opencds.config.api.model.Issuer;

import java.util.List;
import java.util.Objects;

public record CdsHooksClientImpl(String id,
                                 String description,
                                 List<Issuer> issuers,
                                 String tenant) implements CdsHooksClient {
    public CdsHooksClientImpl {
        assert StringUtils.isNotBlank(id);
        assert issuers != null && !issuers.isEmpty();
        assert Objects.isNull(tenant) || StringUtils.isNotBlank(tenant);
    }

    public static CdsHooksClient create(String id,
                                        String description,
                                        List<Issuer> issuers,
                                        String tenant) {
        return new CdsHooksClientImpl(id, description, issuers, tenant);
    }

    public static CdsHooksClient create(CdsHooksClient ce) {
        if (ce == null) {
            return null;
        }
        if (ce instanceof CdsHooksClientImpl) {
            return ce;
        }
        return create(
                ce.id(),
                ce.description(),
                ce.issuers().stream()
                        .map(IssuerImpl::create)
                        .toList(),
                ce.tenant());
    }
}
