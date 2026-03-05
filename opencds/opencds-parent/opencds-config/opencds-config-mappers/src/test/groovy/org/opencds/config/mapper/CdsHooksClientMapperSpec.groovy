package org.opencds.config.mapper

import org.opencds.config.api.model.AccessType
import org.opencds.config.schema.CDSHooksClient
import org.opencds.config.schema.CdsHooksClients
import org.opencds.config.schema.Issuer
import org.opencds.config.schema.Issuers
import spock.lang.Specification

class CdsHooksClientMapperSpec extends Specification {
    def 'test internal with Clients'() {
        given:
        var id1 = 'id1'
        var desc1 = 'description-1'
        var tenant1 = 'tenant-1'
        var issValue1 = 'iss-value-1'
        var issValue2 = 'iss-value-2'
        var jkuValue1 = 'jku-value-1'
        var jkuValue2 = null
        var jwkValue1 = null
        var jwkValue2 = 'jku-value-2'
        var schemaClients = new CdsHooksClients(
                cdsHooksClient: [
                        new CDSHooksClient(
                                id: id1,
                                description: desc1,
                                issuers: new Issuers(
                                        issuer: [
                                                new Issuer(iss: issValue1, jku: jkuValue1, jwk: jwkValue1, accessType: org.opencds.config.schema.AccessType.ALLOW),
                                                new Issuer(iss: issValue2, jku: jkuValue2, jwk: jwkValue2, accessType: org.opencds.config.schema.AccessType.DENY)
                                        ]),
                                tenant: tenant1
                        )
                ])

        when:
        var internal = CdsHooksClientMapper.internal(schemaClients)

        then:
        noExceptionThrown()
        internal
        internal.size() == 1
        internal[0].id() == id1
        internal[0].issuers()
        internal[0].issuers().size() == 2
        internal[0].issuers()[0].iss() == issValue1
        internal[0].issuers()[0].jku() == jkuValue1
        internal[0].issuers()[0].jwk() == jwkValue1
        internal[0].issuers()[0].accessType() == AccessType.ALLOW
        internal[0].issuers()[1].iss() == issValue2
        internal[0].issuers()[1].jku() == jkuValue2
        internal[0].issuers()[1].jwk() == jwkValue2
        internal[0].issuers()[1].accessType() == AccessType.DENY
        internal[0].tenant() == tenant1

        when:
        var external = CdsHooksClientMapper.external(internal)

        then:
        noExceptionThrown()
        external
        external.getCdsHooksClient()
        external.getCdsHooksClient().size() == 1
        external.getCdsHooksClient()[0].id == id1
        external.getCdsHooksClient()[0].description == desc1
        external.getCdsHooksClient()[0].issuers
        external.getCdsHooksClient()[0].issuers.issuer
        external.getCdsHooksClient()[0].issuers.issuer.size() == 2
        external.getCdsHooksClient()[0].issuers.issuer[0].iss == issValue1
        external.getCdsHooksClient()[0].issuers.issuer[0].jku == jkuValue1
        external.getCdsHooksClient()[0].issuers.issuer[0].jwk == jwkValue1
        external.getCdsHooksClient()[0].issuers.issuer[0].accessType == org.opencds.config.schema.AccessType.ALLOW
        external.getCdsHooksClient()[0].issuers.issuer[1].iss == issValue2
        external.getCdsHooksClient()[0].issuers.issuer[1].jku == jkuValue2
        external.getCdsHooksClient()[0].issuers.issuer[1].jwk == jwkValue2
        external.getCdsHooksClient()[0].issuers.issuer[1].accessType == org.opencds.config.schema.AccessType.DENY
        external.getCdsHooksClient()[0].tenant == tenant1
    }
}
