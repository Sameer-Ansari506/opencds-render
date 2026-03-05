package org.opencds.config.file

import org.opencds.config.api.dao.util.FileUtil
import org.opencds.config.api.service.KnowledgeModuleService
import org.opencds.config.file.dao.ConceptDeterminationMethodFileDao
import org.opencds.config.service.CacheServiceImpl
import org.opencds.config.service.ConceptDeterminationMethodServiceImpl
import org.opencds.config.service.ConceptServiceImpl
import spock.lang.Specification

import java.nio.file.Paths

class ConceptServiceImplSpec extends Specification {
    private static final PATH = '../opencds-config-client/src/test/resources/'
    private static ConceptServiceImpl service
    private static KnowledgeModuleService kmService

    def setupSpec() {
        var cacheService = new CacheServiceImpl()
        var path = Paths.get(PATH)
        var cdmService = new ConceptDeterminationMethodServiceImpl(
                new ConceptDeterminationMethodFileDao(
                        new FileUtil(),
                        path
                ),
                cacheService)
        kmService = Mock(KnowledgeModuleService)
        1 * kmService.getAll() >> []
        service = new ConceptServiceImpl(cdmService, kmService, cacheService)
    }

    def 'test getConceptViews'() {
        given:
        var system = '2.16.840.1.113883.6.285'
        var code = '98960'

        and:
        0 * _._

        when:
        var view = service.getConceptViews(system, code)
        view.stream()
                .forEach(System.err::println)

        then:
        noExceptionThrown()
        view
        view.size() == 5
        view.subList(0, 5).cdmCode == ['C2511'] * 5
        view.subList(0, 5).toConcept.codeSystem as Set == ['2.16.840.1.113883.3.795.12.1.1'] * 5 as Set
        view.subList(0, 5).toConcept.code as Set == ['C2931', 'C2947', 'C2924', 'C2952', 'C2927'] as Set
    }
}
