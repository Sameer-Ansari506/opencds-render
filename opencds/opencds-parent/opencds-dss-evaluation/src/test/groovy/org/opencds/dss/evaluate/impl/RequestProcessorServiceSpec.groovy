package org.opencds.dss.evaluate.impl

import org.omg.dss.common.EntityIdentifier
import org.omg.dss.common.ItemIdentifier
import org.omg.dss.common.SemanticPayload
import org.omg.dss.evaluation.requestresponse.DataRequirementItemData
import spock.lang.Specification

import java.util.zip.GZIPOutputStream

class RequestProcessorServiceSpec extends Specification {
    def "getInputPayload with base64-encoded gzipped payload"() {
        given:
        var service = new RequestProcessorService()
        var dridata = new DataRequirementItemData()
        dridata.data = new SemanticPayload()
        dridata.driId = new ItemIdentifier()
        dridata.driId.containingEntityId = new EntityIdentifier()
        dridata.driId.containingEntityId.businessId = 'gzip'
        dridata.data.getBase64EncodedPayload().add(gzip(DATA.bytes))

        when:
        var response = service.getInputPayload(dridata)

        then:
        notThrown(Exception)
        new String(response) == DATA
    }

    def "getInputPayload with base64-encoded payload"() {
        given:
        var service = new RequestProcessorService()
        var dridata = new DataRequirementItemData()
        dridata.data = new SemanticPayload()
        dridata.driId = new ItemIdentifier()
        dridata.driId.containingEntityId = new EntityIdentifier()
        dridata.driId.containingEntityId.businessId = ''
        dridata.data.getBase64EncodedPayload().add(DATA.bytes)

        when:
        var response = service.getInputPayload(dridata)

        then:
        notThrown(Exception)
        new String(response) == DATA
    }

    private static byte[] gzip(byte[] data) {
        try (var baos = new ByteArrayOutputStream();
             var gzos = new GZIPOutputStream(baos)) {
            gzos.write(data, 0, data.length)
            gzos.finish()
            baos.flush()
            return baos.toByteArray()
        }
    }

    private static final String DATA = '{"test":1,"payload":2}'
}
