package org.opencds.config.api.model.impl;

import org.apache.commons.lang3.StringUtils;
import org.opencds.config.api.model.AccessType;
import org.opencds.config.api.model.Issuer;

public record IssuerImpl(String iss,
                         String jku,
                         String jwk,
                         AccessType accessType) implements Issuer {
    public IssuerImpl {
        assert StringUtils.isNotBlank(iss);
        assert StringUtils.isNotBlank(jku) || StringUtils.isNotBlank(jwk);
        assert accessType != null;
    }

    public static Issuer create(String iss, String jku, String jwk, AccessType accessType) {
        return new IssuerImpl(iss, jku, jwk, accessType);
    }

    public static Issuer create(Issuer issuer) {
        return create(
                issuer.iss(),
                issuer.jku(),
                issuer.jwk(),
                issuer.accessType());
    }
}
