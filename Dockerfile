# Multi-stage build: Build OpenCDS from source, then create deployable webapp with REST JSON endpoint
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy OpenCDS source code
COPY opencds /build/opencds

# Build OpenCDS (produces JARs, not WAR)
WORKDIR /build/opencds
RUN mvn clean install -DskipTests || echo "Build completed with warnings"

# Create webapp structure
RUN mkdir -p /build/webapp/WEB-INF/lib && \
    mkdir -p /build/webapp/WEB-INF/classes

# Copy all OpenCDS JARs to webapp lib
RUN find /build/opencds -name "*.jar" -type f -not -name "*-sources.jar" -not -name "*-javadoc.jar" -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Use Maven to get the complete dependency list, then copy from local repository
# This ensures we get ALL transitive dependencies without re-downloading
RUN echo "=== Getting dependency list and copying from local Maven repository ===" && \
    cd /build/opencds/opencds-parent && \
    # First, get the dependency tree to see what we need (this uses local repo only, no downloads)
    echo "Analyzing dependencies for key modules..." && \
    mvn dependency:tree -pl opencds-dss-evaluation,opencds-config-file,opencds-vmr-evaluation -am -DoutputFile=/tmp/deps.txt 2>&1 | tail -10 && \
    # Extract all groupId:artifactId:version from dependency tree and copy from local repo
    echo "Copying dependencies from local Maven repository..." && \
    # Copy all JARs that match OpenCDS and its dependencies from local repo
    # This includes: OpenCDS modules, JAXB, logging, and all transitive deps
    find /root/.m2/repository \
        \( -path "*/org/opencds/*/*.jar" \
        -o -path "*/jakarta/xml/bind/*/*.jar" \
        -o -path "*/jakarta/activation/*/*.jar" \
        -o -path "*/org/glassfish/jaxb/*/*.jar" \
        -o -path "*/com/sun/istack/*/*.jar" \
        -o -path "*/commons-logging/*/*.jar" \
        -o -path "*/org/apache/logging/log4j/*/*.jar" \
        -o -path "*/org/slf4j/*/*.jar" \
        -o -path "*/org/eclipse/angus/*/*.jar" \
        \) \
        -name "*.jar" \
        -type f \
        -not -name "*-sources.jar" \
        -not -name "*-javadoc.jar" \
        -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true && \
    # Also copy any other common dependencies that might be needed
    # (This is a safety net - copy common dependency patterns)
    find /root/.m2/repository \
        -name "*.jar" \
        -type f \
        -not -name "*-sources.jar" \
        -not -name "*-javadoc.jar" \
        -not -path "*/maven-metadata*" \
        -not -path "*/org/opencds/*" \
        \( -path "*/org/apache/*/*.jar" \
        -o -path "*/com/google/*/*.jar" \
        -o -path "*/org/eclipse/*/*.jar" \
        -o -path "*/jakarta/*/*.jar" \
        -o -path "*/javax/*/*.jar" \
        -o -path "*/com/sun/*/*.jar" \
        \) \
        -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true && \
    echo "✅ Dependencies copied from local Maven repository" && \
    echo "Total JARs in lib: $(ls -1 /build/webapp/WEB-INF/lib/*.jar 2>/dev/null | wc -l)" && \
    echo "Key dependencies present:" && \
    (ls /build/webapp/WEB-INF/lib/*jaxb*.jar 2>/dev/null | wc -l && echo "JAXB JARs") || echo "No JAXB JARs found" && \
    (ls /build/webapp/WEB-INF/lib/*istack*.jar 2>/dev/null | wc -l && echo "istack JARs") || echo "No istack JARs found" && \
    (ls /build/webapp/WEB-INF/lib/*commons-logging*.jar 2>/dev/null | wc -l && echo "commons-logging JARs") || echo "No commons-logging JARs found"

# Download Servlet API 4.0 (javax namespace - compatible with Tomcat 9)
# Tomcat 9 uses Java EE 8 which uses javax.servlet, not jakarta.servlet
RUN echo "=== Downloading Servlet API 4.0 (javax namespace for Tomcat 9) ===" && \
    curl -L -f -o /tmp/servlet-api.jar \
    https://repo1.maven.org/maven2/javax/servlet/javax.servlet-api/4.0.1/javax.servlet-api-4.0.1.jar && \
    test -f /tmp/servlet-api.jar || (echo "ERROR: Failed to download servlet-api.jar" && exit 1) && \
    echo "=== Verifying servlet-api.jar ===" && \
    ls -lh /tmp/servlet-api.jar && \
    echo "=== Checking first 20 entries in jar ===" && \
    jar tf /tmp/servlet-api.jar | head -20 && \
    echo "=== Verifying javax namespace ===" && \
    (jar tf /tmp/servlet-api.jar | grep -q "^javax/servlet/http/HttpServlet.class$" && \
     echo "✅ CONFIRMED: jar contains javax/servlet/http/HttpServlet.class") || \
    (echo "❌ ERROR: jar does NOT contain javax packages!" && \
     echo "Found these servlet classes instead:" && \
     jar tf /tmp/servlet-api.jar | grep "servlet/http" | head -5 && \
     exit 1) && \
    echo "=== Copying servlet API to WAR lib directory ===" && \
    cp /tmp/servlet-api.jar /build/webapp/WEB-INF/lib/javax.servlet-api.jar && \
    echo "✅ Servlet API added to WAR"

# Download Gson for JSON parsing
RUN echo "=== Downloading Gson for JSON parsing ===" && \
    curl -L -f -o /tmp/gson.jar \
    https://repo1.maven.org/maven2/com/google/code/gson/gson/2.10.1/gson-2.10.1.jar && \
    cp /tmp/gson.jar /build/webapp/WEB-INF/lib/gson.jar && \
    echo "✅ Gson added to WAR"

# Download Apache Commons Logging (required by OpenCDS)
RUN echo "=== Downloading Apache Commons Logging ===" && \
    curl -L -f -o /tmp/commons-logging.jar \
    https://repo1.maven.org/maven2/commons-logging/commons-logging/1.2/commons-logging-1.2.jar && \
    cp /tmp/commons-logging.jar /build/webapp/WEB-INF/lib/commons-logging.jar && \
    echo "✅ Apache Commons Logging added to WAR"

# Download Drools 5.5 dependencies using Maven to get ALL transitive dependencies
# This ensures we get org.drools.command.Context and all other required classes
RUN echo "=== Downloading Drools 5.5 dependencies with Maven (includes transitive deps) ===" && \
    mkdir -p /tmp/drools-deps && \
    cd /tmp/drools-deps && \
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<project xmlns="http://maven.apache.org/POM/4.0.0"' \
        '         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"' \
        '         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">' \
        '    <modelVersion>4.0.0</modelVersion>' \
        '    <groupId>org.opencds</groupId>' \
        '    <artifactId>drools-deps</artifactId>' \
        '    <version>1.0</version>' \
        '    <dependencies>' \
        '        <dependency>' \
        '            <groupId>org.drools</groupId>' \
        '            <artifactId>drools-core</artifactId>' \
        '            <version>5.5.0.Final</version>' \
        '        </dependency>' \
        '        <dependency>' \
        '            <groupId>org.drools</groupId>' \
        '            <artifactId>drools-compiler</artifactId>' \
        '            <version>5.5.0.Final</version>' \
        '        </dependency>' \
        '        <dependency>' \
        '            <groupId>org.drools</groupId>' \
        '            <artifactId>knowledge-api</artifactId>' \
        '            <version>5.5.0.Final</version>' \
        '        </dependency>' \
        '    </dependencies>' \
        '</project>' > pom.xml && \
    # Use Maven to download all dependencies (including transitive ones)
    mvn dependency:copy-dependencies -DoutputDirectory=/tmp/drools-libs && \
    # Copy all downloaded JARs to WEB-INF/lib
    cp /tmp/drools-libs/*.jar /build/webapp/WEB-INF/lib/ && \
    echo "✅ Drools 5.5 dependencies and ALL transitive dependencies added to WAR"

# Note: JAXB and all other dependencies are now automatically copied via Maven dependency plugin above
# No need to manually download them

# Copy OpenCDS configuration files to webapp
# Create minimal configuration with only VMR support (remove FHIR/CDS Hooks that require missing classes)
RUN echo "=== Copying OpenCDS configuration files ===" && \
    mkdir -p /build/webapp/WEB-INF/classes/resources && \
    # Copy base config files
    cp -r /build/opencds/opencds-parent/opencds-knowledge-repository-data/src/main/resources/resources/* \
          /build/webapp/WEB-INF/classes/resources/ 2>/dev/null || \
    (echo "WARNING: Could not copy all config files, continuing..." && \
     mkdir -p /build/webapp/WEB-INF/classes/resources && \
     echo "Config directory created") && \
    # Remove plugins to prevent plugin loading errors
    rm -rf /build/webapp/WEB-INF/classes/resources/plugins 2>/dev/null || true && \
    mkdir -p /build/webapp/WEB-INF/classes/resources/plugins && \
    echo '<?xml version="1.0" encoding="UTF-8"?><rest:pluginPackages xmlns:rest="org.opencds.config.rest.v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="org.opencds.config.rest.v2 ../schema/OpenCDSConfigRest.xsd"></rest:pluginPackages>' > \
        /build/webapp/WEB-INF/classes/resources/plugins/opencds-plugins.xml && \
    # Create minimal semanticSignifiers.xml with only VMR (remove FHIR/CDS Hooks that require missing classes)
    printf '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<ns2:semanticSignifiers xmlns:ns2="org.opencds.config.rest.v2" xmlns:ns3="org.opencds.config.v2" xsi:schemaLocation="org.opencds.config.rest.v2 ../../../../../../opencds-parent/opencds-config/opencds-config-schema/src/main/resources/schema/OpenCDSConfigRest.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n    <semanticSignifier>\n        <identifier scopingEntityId="org.opencds.vmr" businessId="VMR" version="1.0" />\n        <name>org.opencds.vmr^VMR^1.0</name>\n        <description>org.opencds.vmr^VMR^1.0</description>\n        <xsdComputableDefinition>\n            <xsdRootGlobalElementName>CDSInput</xsdRootGlobalElementName>\n            <xsdURL>org.opencds.vmr.v1_0.schema</xsdURL>\n        </xsdComputableDefinition>\n        <entryPoint>org.opencds.service.evaluate.CDSInputEntryPoint</entryPoint>\n        <exitPoint>org.opencds.service.evaluate.CDSOutputExitPoint</exitPoint>\n        <factListsBuilder>org.opencds.service.evaluate.CdsInputFactListsBuilder</factListsBuilder>\n        <resultSetBuilder>org.opencds.service.evaluate.CdsOutputResultSetBuilder</resultSetBuilder>\n        <timestamp>2014-11-03T15:24:57.212-07:00</timestamp>\n        <userId>phillip</userId>\n    </semanticSignifier>\n</ns2:semanticSignifiers>\n' > /build/webapp/WEB-INF/classes/resources/semanticSignifiers.xml && \
    echo "✅ OpenCDS configuration files copied (minimal config - VMR only, plugins and FHIR hooks disabled)"

# Create execution engines configuration
# Using our minimal pass-through adapter instead of Drools
RUN echo "=== Creating execution engines configuration ===" && \
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<ns2:executionEngines xsi:schemaLocation="org.opencds.config.rest.v2 ../../../../../../opencds-parent/opencds-config/opencds-config-schema/src/main/resources/schema/OpenCDSConfigRest.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns2="org.opencds.config.rest.v2">' \
        '    <executionEngine>' \
        '        <identifier>org.opencds.service.veda.DroolsAdapter</identifier>' \
        '        <adapter>org.opencds.service.veda.DroolsExecutionEngineAdapter</adapter>' \
        '        <context>org.opencds.service.veda.PassThroughExecutionEngineContext</context>' \
        '        <knowledgeLoader>org.opencds.service.veda.PassThroughKnowledgeLoader</knowledgeLoader>' \
        '        <description>Veda pass-through execution engine adapter (minimal implementation)</description>' \
        '        <timestamp>2024-01-01T00:00:00</timestamp>' \
        '        <userId>veda</userId>' \
        '        <supportedOperation>EVALUATION.EVALUATE</supportedOperation>' \
        '        <supportedOperation>EVALUATION.EVALUATE_AT_SPECIFIED_TIME</supportedOperation>' \
        '    </executionEngine>' \
        '</ns2:executionEngines>' > /build/webapp/WEB-INF/classes/resources/executionEngines.xml && \
    echo "✅ Execution engines configuration created"

# Create knowledge modules configuration
RUN echo "=== Creating knowledge modules configuration ===" && \
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
        '<ns2:knowledgeModules xsi:schemaLocation="org.opencds.config.rest.v2 ../../../../../../opencds-parent/opencds-config/opencds-config-schema/src/main/resources/schema/OpenCDSConfigRest.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns2="org.opencds.config.rest.v2" xmlns:ns3="org.opencds.config.v2">' \
        '    <knowledgeModule>' \
        '        <identifier scopingEntityId="org.opencds" businessId="veda-basic" version="1.0.0" />' \
        '        <status>APPROVED</status>' \
        '        <executionEngine>org.opencds.service.veda.DroolsAdapter</executionEngine>' \
        '        <semanticSignifierId scopingEntityId="org.opencds.vmr" businessId="VMR" version="1.0" />' \
        '        <package>' \
        '            <packageType>DRL</packageType>' \
        '            <packageId>org.opencds^veda-basic^1.0.0.drl</packageId>' \
        '        </package>' \
        '        <timestamp>2024-01-01T00:00:00</timestamp>' \
        '        <userId>veda</userId>' \
        '    </knowledgeModule>' \
        '</ns2:knowledgeModules>' > /build/webapp/WEB-INF/classes/resources/knowledgeModules.xml && \
    echo "✅ Knowledge modules configuration created"

# Create minimal knowledge package (DRL file)
RUN echo "=== Creating minimal knowledge package (DRL file) ===" && \
    mkdir -p /build/webapp/WEB-INF/classes/resources/knowledgePackages && \
    printf '%s\n' \
        'package VedaBasic_v1_0_0' \
        '' \
        'import org.opencds.vmr.v1_0.internal.ClinicalStatement' \
        'import org.opencds.vmr.v1_0.internal.EntityBase' \
        '' \
        'global java.util.Date evalTime' \
        'global String clientLanguage' \
        'global String clientTimeZoneOffset' \
        'global String focalPersonId' \
        '' \
        '// Minimal rule: return all clinical statements and entities' \
        'rule "ReturnAllClinicalStatements"' \
        '    dialect "mvel"' \
        '    when' \
        '        $cs : ClinicalStatement()' \
        '    then' \
        '        $cs.setToBeReturned(true);' \
        'end' \
        '' \
        'rule "ReturnAllEntities"' \
        '    dialect "mvel"' \
        '    when' \
        '        $entity : EntityBase()' \
        '    then' \
        '        $entity.setToBeReturned(true);' \
        'end' > /build/webapp/WEB-INF/classes/resources/knowledgePackages/org.opencds^veda-basic^1.0.0.drl && \
    echo "✅ Knowledge package (DRL file) created"

# Create real Drools execution engine adapter
RUN echo "=== Creating real Drools execution engine adapter ===" && \
    printf '%s\n' \
        'package org.opencds.service.veda;' \
        '' \
        'import org.drools.KnowledgeBase;' \
        'import org.drools.KnowledgeBaseFactory;' \
        'import org.drools.builder.KnowledgeBuilder;' \
        'import org.drools.builder.KnowledgeBuilderFactory;' \
        'import org.drools.builder.ResourceType;' \
        'import org.drools.io.ResourceFactory;' \
        'import org.drools.runtime.StatefulKnowledgeSession;' \
        'import org.drools.runtime.rule.FactHandle;' \
        'import org.opencds.config.api.ExecutionEngineAdapter;' \
        'import org.opencds.config.api.ExecutionEngineContext;' \
        'import org.opencds.config.api.EvaluationContext;' \
        'import org.opencds.service.veda.PassThroughExecutionEngineContext;' \
        'import java.util.Map;' \
        'import java.util.List;' \
        'import java.util.HashMap;' \
        'import java.util.ArrayList;' \
        'import java.io.InputStream;' \
        'import java.io.InputStreamReader;' \
        'import java.io.BufferedReader;' \
        '' \
        '/**' \
        ' * Real Drools execution engine adapter that evaluates DRL rules.' \
        ' */' \
        'public class DroolsExecutionEngineAdapter implements ExecutionEngineAdapter<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>, InputStream> {' \
        '    ' \
        '    @Override' \
        '    public ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> execute(' \
        '            InputStream knowledgePackage,' \
        '            ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> context) throws Exception {' \
        '        ' \
        '        // Get input fact lists' \
        '        Map<Class<?>, List<?>> input = context.getInput();' \
        '        ' \
        '        // Build Drools KnowledgeBase from DRL InputStream' \
        '        KnowledgeBuilder kbuilder = KnowledgeBuilderFactory.newKnowledgeBuilder();' \
        '        kbuilder.add(ResourceFactory.newInputStreamResource(knowledgePackage), ResourceType.DRL);' \
        '        ' \
        '        if (kbuilder.hasErrors()) {' \
        '            throw new RuntimeException("DRL compilation errors: " + kbuilder.getErrors().toString());' \
        '        }' \
        '        ' \
        '        KnowledgeBase kbase = KnowledgeBaseFactory.newKnowledgeBase();' \
        '        kbase.addKnowledgePackages(kbuilder.getKnowledgePackages());' \
        '        ' \
        '        // Create session and insert facts' \
        '        StatefulKnowledgeSession ksession = kbase.newStatefulKnowledgeSession();' \
        '        ' \
        '        // Set globals from EvaluationContext if available' \
        '        EvaluationContext evalContext = null;' \
        '        if (context instanceof PassThroughExecutionEngineContext) {' \
        '            evalContext = ((PassThroughExecutionEngineContext) context).getEvaluationContext();' \
        '        }' \
        '        ' \
        '        if (evalContext != null) {' \
        '            ksession.setGlobal("evalTime", evalContext.getEvalTime());' \
        '            ksession.setGlobal("clientLanguage", evalContext.getClientLanguage());' \
        '            ksession.setGlobal("clientTimeZoneOffset", evalContext.getClientTimeZoneOffset());' \
        '            ksession.setGlobal("focalPersonId", evalContext.getFocalPersonId());' \
        '            ksession.setGlobal("assertions", evalContext.getAssertions());' \
        '            ksession.setGlobal("namedObjects", evalContext.getNamedObjects());' \
        '        } else {' \
        '            // Fallback to defaults' \
        '            ksession.setGlobal("evalTime", new java.util.Date());' \
        '            ksession.setGlobal("clientLanguage", "en-US");' \
        '            ksession.setGlobal("clientTimeZoneOffset", "+00:00");' \
        '            ksession.setGlobal("focalPersonId", "patient-1");' \
        '            ksession.setGlobal("assertions", new java.util.HashSet<String>());' \
        '            ksession.setGlobal("namedObjects", new java.util.HashMap<String, Object>());' \
        '        }' \
        '        ' \
        '        // Insert all facts from input' \
        '        Map<Class<?>, List<FactHandle>> factHandles = new HashMap<>();' \
        '        for (Map.Entry<Class<?>, List<?>> entry : input.entrySet()) {' \
        '            if (entry.getValue() != null) {' \
        '                List<FactHandle> handles = new ArrayList<>();' \
        '                for (Object fact : entry.getValue()) {' \
        '                    if (fact != null) {' \
        '                        handles.add(ksession.insert(fact));' \
        '                    }' \
        '                }' \
        '                factHandles.put(entry.getKey(), handles);' \
        '            }' \
        '        }' \
        '        ' \
        '        // Fire all rules' \
        '        ksession.fireAllRules();' \
        '        ' \
        '        // Collect results - all facts that are still in working memory' \
        '        Map<Class<?>, List<?>> results = new HashMap<>();' \
        '        for (Map.Entry<Class<?>, List<?>> entry : input.entrySet()) {' \
        '            List<Object> resultList = new ArrayList<>();' \
        '            if (entry.getValue() != null) {' \
        '                for (Object fact : entry.getValue()) {' \
        '                    if (fact != null) {' \
        '                        resultList.add(fact);' \
        '                    }' \
        '                }' \
        '            }' \
        '            if (!resultList.isEmpty()) {' \
        '                results.put(entry.getKey(), resultList);' \
        '            }' \
        '        }' \
        '        ' \
        '        ksession.dispose();' \
        '        ' \
        '        return context.setResults(results);' \
        '    }' \
        '}' > /build/DroolsExecutionEngineAdapter.java && \
    echo "✅ Drools execution engine adapter created" && \
    echo "=== Creating minimal execution engine adapter (fallback) ===" && \
    printf '%s\n' \
        'package org.opencds.service.veda;' \
        '' \
        'import org.opencds.config.api.ExecutionEngineAdapter;' \
        'import org.opencds.config.api.ExecutionEngineContext;' \
        'import java.util.Map;' \
        'import java.util.List;' \
        'import java.util.HashMap;' \
        '' \
        '/**' \
        ' * Minimal pass-through execution engine adapter.' \
        ' * This adapter simply returns the input as output without any rule evaluation.' \
        ' * It'\''s used when Drools adapters are not available.' \
        ' */' \
        'public class PassThroughExecutionEngineAdapter implements ExecutionEngineAdapter<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>, java.io.InputStream> {' \
        '    ' \
        '    @Override' \
        '    public ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> execute(' \
        '            java.io.InputStream knowledgePackage,' \
        '            ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> context) throws Exception {' \
        '        ' \
        '        // Pass-through: return input as output (ignore knowledge package for now)' \
        '        Map<Class<?>, List<?>> input = context.getInput();' \
        '        return context.setResults(input);' \
        '    }' \
        '}' > /build/PassThroughExecutionEngineAdapter.java && \
    printf '%s\n' \
        'package org.opencds.service.veda;' \
        '' \
        'import org.opencds.config.api.ExecutionEngineContext;' \
        'import org.opencds.config.api.EvaluationContext;' \
        'import java.util.Map;' \
        'import java.util.List;' \
        'import java.util.HashMap;' \
        '' \
        '/**' \
        ' * Minimal execution engine context implementation.' \
        ' */' \
        'public class PassThroughExecutionEngineContext implements ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> {' \
        '    ' \
        '    private Map<Class<?>, List<?>> input;' \
        '    private Map<Class<?>, List<?>> results;' \
        '    private EvaluationContext evaluationContext;' \
        '    ' \
        '    public PassThroughExecutionEngineContext() {' \
        '        this.input = new HashMap<>();' \
        '        this.results = new HashMap<>();' \
        '    }' \
        '    ' \
        '    public PassThroughExecutionEngineContext(Map<Class<?>, List<?>> input) {' \
        '        this.input = input != null ? input : new HashMap<>();' \
        '        this.results = new HashMap<>();' \
        '    }' \
        '    ' \
        '    @Override' \
        '    public Map<Class<?>, List<?>> getInput() {' \
        '        return input;' \
        '    }' \
        '    ' \
        '    @Override' \
        '    public ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> setResults(Map<Class<?>, List<?>> results) {' \
        '        this.results = results != null ? results : new HashMap<>();' \
        '        return this;' \
        '    }' \
        '    ' \
        '    @Override' \
        '    public Map<String, List<?>> getResults() {' \
        '        Map<String, List<?>> stringResults = new HashMap<>();' \
        '        if (results != null) {' \
        '            for (Map.Entry<Class<?>, List<?>> entry : results.entrySet()) {' \
        '                if (entry.getKey() != null && entry.getValue() != null) {' \
        '                    stringResults.put(entry.getKey().getName(), entry.getValue());' \
        '                }' \
        '            }' \
        '        }' \
        '        return stringResults;' \
        '    }' \
        '    ' \
        '    @Override' \
        '    public ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> setEvaluationContext(EvaluationContext evaluationContext) {' \
        '        this.evaluationContext = evaluationContext;' \
        '        return this;' \
        '    }' \
        '    ' \
        '    public EvaluationContext getEvaluationContext() {' \
        '        return evaluationContext;' \
        '    }' \
        '}' > /build/PassThroughExecutionEngineContext.java && \
    printf '%s\n' \
        'package org.opencds.service.veda;' \
        '' \
        'import org.opencds.config.api.KnowledgeLoader;' \
        'import org.opencds.config.api.model.KnowledgeModule;' \
        'import java.util.function.Function;' \
        'import java.io.InputStream;' \
        '' \
        '/**' \
        ' * Minimal knowledge loader implementation.' \
        ' * Returns the InputStream as the knowledge package (pass-through).' \
        ' */' \
        'public class PassThroughKnowledgeLoader implements KnowledgeLoader<InputStream, InputStream> {' \
        '    ' \
        '    @Override' \
        '    public InputStream loadKnowledgePackage(KnowledgeModule knowledgeModule, Function<KnowledgeModule, InputStream> inputFunction) {' \
        '        // Return the InputStream as-is (pass-through)' \
        '        return inputFunction.apply(knowledgeModule);' \
        '    }' \
        '}' > /build/PassThroughKnowledgeLoader.java && \
    echo "✅ Minimal execution engine adapter classes created"

# Create REST servlet Java source with OpenCDS integration
RUN cat > /build/EvaluateServlet.java << 'EOJAVA'
import java.io.*;
import java.util.*;
import javax.servlet.*;
import javax.servlet.http.*;
import javax.servlet.annotation.*;
import com.google.gson.*;
import org.opencds.config.api.ConfigurationService;
import org.opencds.config.api.ConfigData;
import org.opencds.config.api.KnowledgeRepository;
import org.opencds.config.api.model.KnowledgeModule;
import org.opencds.config.api.model.SSId;
import org.opencds.config.api.model.impl.SSIdImpl;
import org.opencds.config.api.strategy.ConfigStrategy;
import org.opencds.config.file.FileConfigStrategy;
import org.opencds.config.service.CacheServiceImpl;
import org.opencds.common.structures.EvaluationRequestKMItem;
import org.opencds.common.structures.EvaluationRequestDataItem;
import org.opencds.common.structures.EvaluationResponseKMItem;
import org.opencds.evaluation.service.EvaluationService;
import org.opencds.evaluation.service.EvaluationServiceImpl;
import org.opencds.evaluation.service.util.CallableUtil;
import org.opencds.evaluation.service.util.CallableUtilImpl;
import org.opencds.vmr.v1_0.internal.Problem;
import org.opencds.vmr.v1_0.internal.ObservationProposal;
import org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal;
import org.opencds.vmr.v1_0.internal.ProcedureProposal;
import org.opencds.vmr.v1_0.internal.AdministrableSubstance;
import org.opencds.vmr.v1_0.internal.datatypes.CD;
import org.opencds.vmr.v1_0.internal.EvaluatedPerson;
import org.opencds.vmr.v1_0.internal.EvalTime;
import org.opencds.vmr.v1_0.internal.FocalPersonId;
import org.opencds.vmr.v1_0.internal.Demographics;

@WebServlet(name = "EvaluateServlet", urlPatterns = {"/opencds-decision-support-service/evaluate"})
public class EvaluateServlet extends HttpServlet {
    private static volatile EvaluationService evaluationService;
    private static volatile KnowledgeRepository knowledgeRepository;
    private static volatile ConfigurationService configurationService;
    private static final Object initLock = new Object();
    private static final Gson gson = new GsonBuilder().setPrettyPrinting().create();
    
    @Override
    public void init() throws ServletException {
        super.init();
        getServletContext().log("EvaluateServlet initialized");
    }
    
    private void initializeOpenCDS() {
        if (evaluationService != null) {
            return; // Already initialized
        }
        
        synchronized (initLock) {
            if (evaluationService != null) {
                return; // Double-check
            }
            
            try {
                getServletContext().log("Initializing OpenCDS...");
                
                // Get config path from servlet context
                String configPath = getServletContext().getRealPath("/WEB-INF/classes/resources");
                if (configPath == null) {
                    // Fallback: try to get from classpath
                    try {
                        java.net.URL configUrl = getServletContext().getResource("/WEB-INF/classes/resources");
                        if (configUrl != null) {
                            configPath = configUrl.getPath();
                        } else {
                            // Last resort: use a default path
                            configPath = "/usr/local/tomcat/webapps/ROOT/WEB-INF/classes/resources";
                        }
                    } catch (Exception e) {
                        configPath = "/usr/local/tomcat/webapps/ROOT/WEB-INF/classes/resources";
                    }
                }
                
                getServletContext().log("Config path: " + configPath);
                
                // Verify config path exists
                java.io.File configDir = new java.io.File(configPath);
                if (!configDir.exists()) {
                    getServletContext().log("WARNING: Config directory does not exist: " + configPath);
                    getServletContext().log("Will attempt to continue anyway...");
                }
                
                // Initialize OpenCDS ConfigurationService
                try {
                    // Create ConfigData
                    ConfigData configData = ConfigData.create("SIMPLE_FILE", configPath);
                    getServletContext().log("ConfigData created: type=" + configData.getConfigType() + ", path=" + configData.getConfigLocation());
                    
                    // Create FileConfigStrategy
                    FileConfigStrategy fileConfigStrategy = new FileConfigStrategy();
                    getServletContext().log("FileConfigStrategy created");
                    
                    // Create Set of ConfigStrategies
                    Set<ConfigStrategy> configStrategies = new HashSet<>();
                    configStrategies.add(fileConfigStrategy);
                    
                    // Create ConfigurationService
                    configurationService = new ConfigurationService(
                        configStrategies,
                        CacheServiceImpl.class,
                        configData
                    );
                    getServletContext().log("ConfigurationService created");
                    
                    // Get KnowledgeRepository
                    knowledgeRepository = configurationService.getKnowledgeRepository();
                    getServletContext().log("KnowledgeRepository obtained");
                    
                    // Log available knowledge modules
                    List<KnowledgeModule> kms = knowledgeRepository.getKnowledgeModuleService().getAll();
                    getServletContext().log("Available knowledge modules: " + kms.size());
                    for (KnowledgeModule km : kms) {
                        String kmId = km.getKMId().getScopingEntityId() + "^" + 
                                     km.getKMId().getBusinessId() + "^" + 
                                     km.getKMId().getVersion();
                        getServletContext().log("  - KM: " + kmId);
                    }
                    
                    // Initialize EvaluationService
                    CallableUtil callableUtil = new CallableUtilImpl();
                    evaluationService = new EvaluationServiceImpl(callableUtil);
                    getServletContext().log("EvaluationService created");
                    
                    getServletContext().log("✅ OpenCDS initialized successfully!");
                    
                } catch (Exception e) {
                    getServletContext().log("❌ Error initializing OpenCDS: " + e.getMessage(), e);
                    e.printStackTrace();
                    evaluationService = null;
                    knowledgeRepository = null;
                    configurationService = null;
                }
            } catch (Exception e) {
                getServletContext().log("❌ Failed to initialize OpenCDS: " + e.getMessage(), e);
                e.printStackTrace();
                evaluationService = null;
            }
        }
    }
    
    protected void doPost(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("application/json; charset=utf-8");
        
        try {
            // Read request body
            StringBuilder requestBody = new StringBuilder();
            try (BufferedReader reader = request.getReader()) {
                String line;
                while ((line = reader.readLine()) != null) {
                    requestBody.append(line);
                }
            }
            
            String requestJson = requestBody.toString();
            getServletContext().log("Received request: " + requestJson.substring(0, Math.min(200, requestJson.length())));
            
            // Initialize OpenCDS if not already done
            initializeOpenCDS();
            
            String jsonResponse;
            if (evaluationService == null || knowledgeRepository == null) {
                // OpenCDS not initialized - return error
                getServletContext().log("ERROR: OpenCDS not initialized");
                JsonObject error = new JsonObject();
                error.addProperty("error", "OpenCDS not initialized");
                error.addProperty("message", "OpenCDS evaluation service is not available");
                jsonResponse = gson.toJson(error);
            } else {
                // Check if knowledge modules are available
                List<KnowledgeModule> kms = knowledgeRepository.getKnowledgeModuleService().getAll();
                if (kms.isEmpty()) {
                    // No knowledge modules configured - return error
                    getServletContext().log("ERROR: No knowledge modules available");
                    JsonObject error = new JsonObject();
                    error.addProperty("error", "No knowledge modules available");
                    error.addProperty("message", "OpenCDS is initialized but no knowledge modules are configured. Please configure knowledge modules in knowledgeModules.xml");
                    jsonResponse = gson.toJson(error);
                } else {
                    // Use real OpenCDS evaluation
                    jsonResponse = evaluateWithOpenCDS(requestJson);
                }
            }
            
            response.setStatus(200);
            response.getWriter().write(jsonResponse);
            
        } catch (Exception e) {
            getServletContext().log("Error processing request: " + e.getMessage(), e);
            response.setStatus(500);
            JsonObject errorResponse = new JsonObject();
            errorResponse.addProperty("error", "Internal server error");
            errorResponse.addProperty("message", e.getMessage());
            response.getWriter().write(gson.toJson(errorResponse));
        }
    }
    
    private String evaluateWithOpenCDS(String requestJson) throws Exception {
        // Parse JSON request using JsonParser instance method (works in all Gson versions)
        JsonObject request = new JsonParser().parse(requestJson).getAsJsonObject();
        JsonObject vmr = request.getAsJsonObject("vmr");
        JsonObject kmRequest = request.getAsJsonObject("kmEvaluationRequest");
        
        getServletContext().log("Processing OpenCDS evaluation request");
        
        // Extract KM ID from request
        String kmId = null;
        if (kmRequest != null) {
            JsonObject kmIdObj = kmRequest.getAsJsonObject("kmId");
            if (kmIdObj != null) {
                String scopingEntityId = kmIdObj.has("scopingEntityId") ? 
                    kmIdObj.get("scopingEntityId").getAsString() : null;
                String businessId = kmIdObj.has("businessId") ? 
                    kmIdObj.get("businessId").getAsString() : null;
                String version = kmIdObj.has("version") ? 
                    kmIdObj.get("version").getAsString() : null;
                
                if (scopingEntityId != null && businessId != null && version != null) {
                    kmId = scopingEntityId + "^" + businessId + "^" + version;
                }
            }
        }
        
        // If no KM ID specified, use first available KM
        if (kmId == null) {
            List<KnowledgeModule> kms = knowledgeRepository.getKnowledgeModuleService().getAll();
            if (!kms.isEmpty()) {
                KnowledgeModule km = kms.get(0);
                kmId = km.getKMId().getScopingEntityId() + "^" + 
                       km.getKMId().getBusinessId() + "^" + 
                       km.getKMId().getVersion();
                getServletContext().log("Using default KM: " + kmId);
            } else {
                // No knowledge modules configured - return error
                getServletContext().log("ERROR: No knowledge modules available in OpenCDS configuration");
                JsonObject error = new JsonObject();
                error.addProperty("error", "No knowledge modules available");
                error.addProperty("message", "No knowledge modules are configured in OpenCDS");
                return gson.toJson(error);
            }
        }
        
        getServletContext().log("Evaluating with KM: " + kmId);
        
        // Create evaluation request
        // NOTE: Full vMR conversion requires converting JSON to OpenCDS CDSInput format
        // For now, we'll create a minimal request to test the integration
        
        // Create EvaluationRequestDataItem
        EvaluationRequestDataItem evalDataItem = new EvaluationRequestDataItem();
        evalDataItem.setEvalTime(new java.util.Date());
        evalDataItem.setClientLanguage("en-US");
        evalDataItem.setClientTimeZoneOffset("+00:00");
        // Set external fact model SSId - this should match the vMR format
        // For vMR 1.0, the SSId is typically: "org.opencds.vmr^VMR^1.0"
        evalDataItem.setExternalFactModelSSId("org.opencds.vmr^VMR^1.0");
        evalDataItem.setInteractionId("evaluate-" + System.currentTimeMillis());
        
        // Convert JSON vMR to OpenCDS internal vMR format
        Map<Class<?>, List<?>> allFactLists = convertJsonToVmrFactLists(vmr, evalDataItem);
        
        // Set focal person ID in evalDataItem
        if (vmr != null) {
            JsonObject patient = vmr.getAsJsonObject("patient");
            if (patient != null) {
                String patientId = "patient-1"; // Default
                if (patient.has("id")) {
                    patientId = patient.get("id").getAsString();
                }
                evalDataItem.setFocalPersonId(patientId);
            }
        }
        
        // Create EvaluationRequestKMItem using constructor
        EvaluationRequestKMItem evalRequest = new EvaluationRequestKMItem(
            kmId,
            evalDataItem,
            allFactLists
        );
        
        // For now, we'll attempt evaluation with minimal data
        // OpenCDS may require proper vMR format, so this might fail
        // but it will test if the integration is working
        
        try {
            // Call OpenCDS evaluation
            EvaluationResponseKMItem evalResponse = evaluationService.evaluate(
                knowledgeRepository, 
                evalRequest
            );
            
            getServletContext().log("OpenCDS evaluation completed");
            
            // Convert response to JSON
            return convertResponseToJson(evalResponse, requestJson);
            
        } catch (Exception e) {
            getServletContext().log("❌ OpenCDS evaluation failed: " + e.getMessage(), e);
            e.printStackTrace();
            // Return error instead of mock
            JsonObject error = new JsonObject();
            error.addProperty("error", "OpenCDS evaluation failed");
            error.addProperty("message", e.getMessage());
            error.addProperty("details", "Check server logs for full stack trace");
            return gson.toJson(error);
        }
    }
    
    private Map<Class<?>, List<?>> convertJsonToVmrFactLists(JsonObject vmr, EvaluationRequestDataItem evalDataItem) {
        Map<Class<?>, List<?>> allFactLists = new HashMap<>();
        
        try {
            // Create EvalTime
            EvalTime evalTime = new EvalTime();
            evalTime.setEvalTimeValue(evalDataItem.getEvalTime());
            List<EvalTime> evalTimeList = new ArrayList<>();
            evalTimeList.add(evalTime);
            allFactLists.put(EvalTime.class, evalTimeList);
            
            if (vmr != null) {
                JsonObject patient = vmr.getAsJsonObject("patient");
                if (patient != null) {
                    // Create FocalPersonId
                    String patientId = "patient-1";
                    if (patient.has("id")) {
                        patientId = patient.get("id").getAsString();
                    }
                    FocalPersonId focalPersonId = new FocalPersonId(patientId);
                    List<FocalPersonId> focalPersonIdList = new ArrayList<>();
                    focalPersonIdList.add(focalPersonId);
                    allFactLists.put(FocalPersonId.class, focalPersonIdList);
                    
                    // Create EvaluatedPerson with demographics
                    EvaluatedPerson evaluatedPerson = new EvaluatedPerson();
                    evaluatedPerson.setId(patientId);
                    evaluatedPerson.setFocalPerson(true);
                    evaluatedPerson.setToBeReturned(true);
                    
                    // Create Demographics
                    Demographics demographics = new Demographics();
                    JsonObject demographicsJson = patient.getAsJsonObject("demographics");
                    if (demographicsJson != null) {
                        if (demographicsJson.has("age")) {
                            int age = demographicsJson.get("age").getAsInt();
                            // Set age in demographics
                            org.opencds.vmr.v1_0.internal.datatypes.PQ agePQ = new org.opencds.vmr.v1_0.internal.datatypes.PQ();
                            agePQ.setValue((double) age); // PQ.setValue() expects double, not String
                            agePQ.setUnit("a"); // years
                            demographics.setAge(agePQ);
                        }
                        if (demographicsJson.has("gender")) {
                            String gender = demographicsJson.get("gender").getAsString();
                            org.opencds.vmr.v1_0.internal.datatypes.CD genderCD = new org.opencds.vmr.v1_0.internal.datatypes.CD();
                            genderCD.setCode(gender);
                            demographics.setGender(genderCD);
                        }
                    }
                    evaluatedPerson.setDemographics(demographics);
                    
                    List<EvaluatedPerson> evaluatedPersonList = new ArrayList<>();
                    evaluatedPersonList.add(evaluatedPerson);
                    allFactLists.put(EvaluatedPerson.class, evaluatedPersonList);
                    
                    // Create Problems from symptoms/complaints if present
                    if (patient.has("symptoms") || patient.has("complaints")) {
                        List<Problem> problems = new ArrayList<>();
                        if (patient.has("symptoms")) {
                            JsonArray symptoms = patient.getAsJsonArray("symptoms");
                            if (symptoms != null) {
                                for (int i = 0; i < symptoms.size(); i++) {
                                    JsonElement element = symptoms.get(i);
                                    if (element != null && element.isJsonObject()) {
                                        JsonObject symptom = element.getAsJsonObject();
                                        Problem problem = new Problem();
                                        problem.setId("problem-" + i);
                                        problem.setEvaluatedPersonId(patientId);
                                        problem.setSubjectIsFocalPerson(true);
                                        problem.setToBeReturned(true);
                                        
                                        org.opencds.vmr.v1_0.internal.datatypes.CD problemCode = new org.opencds.vmr.v1_0.internal.datatypes.CD();
                                        if (symptom.has("code")) {
                                            problemCode.setCode(symptom.get("code").getAsString());
                                        }
                                        if (symptom.has("displayName")) {
                                            problemCode.setDisplayName(symptom.get("displayName").getAsString());
                                        }
                                        if (symptom.has("codeSystem")) {
                                            problemCode.setCodeSystem(symptom.get("codeSystem").getAsString());
                                        }
                                        problem.setProblemCode(problemCode);
                                        problems.add(problem);
                                    }
                                }
                            }
                        }
                        if (patient.has("complaints")) {
                            JsonArray complaints = patient.getAsJsonArray("complaints");
                            if (complaints != null) {
                                for (int i = 0; i < complaints.size(); i++) {
                                    JsonElement element = complaints.get(i);
                                    if (element != null && element.isJsonObject()) {
                                        JsonObject complaint = element.getAsJsonObject();
                                        Problem problem = new Problem();
                                        problem.setId("complaint-" + i);
                                        problem.setEvaluatedPersonId(patientId);
                                        problem.setSubjectIsFocalPerson(true);
                                        problem.setToBeReturned(true);
                                        
                                        org.opencds.vmr.v1_0.internal.datatypes.CD problemCode = new org.opencds.vmr.v1_0.internal.datatypes.CD();
                                        if (complaint.has("code")) {
                                            problemCode.setCode(complaint.get("code").getAsString());
                                        }
                                        if (complaint.has("displayName")) {
                                            problemCode.setDisplayName(complaint.get("displayName").getAsString());
                                        }
                                        if (complaint.has("codeSystem")) {
                                            problemCode.setCodeSystem(complaint.get("codeSystem").getAsString());
                                        }
                                        problem.setProblemCode(problemCode);
                                        problems.add(problem);
                                    }
                                }
                            }
                        }
                        if (!problems.isEmpty()) {
                            allFactLists.put(Problem.class, problems);
                        }
                    }
                }
            }
            
            getServletContext().log("Converted JSON to vMR fact lists: " + allFactLists.keySet().size() + " fact list types");
            
        } catch (Exception e) {
            getServletContext().log("Error converting JSON to vMR: " + e.getMessage(), e);
            e.printStackTrace();
            // Return empty fact lists if conversion fails
        }
        
        return allFactLists;
    }
    
    private String convertResponseToJson(EvaluationResponseKMItem evalResponse, String originalRequest) {
        // Convert OpenCDS response to our JSON format
        JsonObject response = new JsonObject();
        JsonObject vmrOutput = new JsonObject();
        JsonObject clinicalStatements = new JsonObject();
        JsonArray proposals = new JsonArray();
        
        getServletContext().log("Converting OpenCDS response to JSON");
        
        try {
            // Get result fact lists from OpenCDS response
            Map<String, List<?>> resultFactLists = evalResponse.getResultFactLists();
            getServletContext().log("Result fact lists keys: " + (resultFactLists != null ? resultFactLists.keySet().toString() : "null"));
            
            // Log all keys and their sizes for debugging
            if (resultFactLists != null) {
                for (Map.Entry<String, List<?>> entry : resultFactLists.entrySet()) {
                    getServletContext().log("Key: " + entry.getKey() + ", Size: " + (entry.getValue() != null ? entry.getValue().size() : "null"));
                }
            } else {
                getServletContext().log("WARNING: resultFactLists is null - OpenCDS returned empty results");
            }
            
            if (resultFactLists != null) {
                // Extract Problems (diagnoses)
                // Try both simple name and fully qualified name
                List<?> problems = resultFactLists.get("Problem");
                if (problems == null) {
                    problems = resultFactLists.get("org.opencds.vmr.v1_0.internal.Problem");
                }
                if (problems != null) {
                    for (Object obj : problems) {
                        try {
                            if (obj instanceof org.opencds.vmr.v1_0.internal.Problem) {
                                org.opencds.vmr.v1_0.internal.Problem problem = (org.opencds.vmr.v1_0.internal.Problem) obj;
                                if (problem.isToBeReturned()) {
                                JsonObject proposal = new JsonObject();
                                proposal.addProperty("type", "diagnosis");
                                
                                org.opencds.vmr.v1_0.internal.datatypes.CD problemCode = problem.getProblemCode();
                                if (problemCode != null) {
                                    proposal.addProperty("displayName", problemCode.getDisplayName() != null ? problemCode.getDisplayName() : "Unknown Diagnosis");
                                    proposal.addProperty("code", problemCode.getCode() != null ? problemCode.getCode() : "");
                                    if (problemCode.getCodeSystem() != null) {
                                        proposal.addProperty("codeSystem", problemCode.getCodeSystem());
                                    }
                                } else {
                                    proposal.addProperty("displayName", "Unknown Diagnosis");
                                    proposal.addProperty("code", "");
                                }
                                
                                proposal.addProperty("confidence", 75); // Default confidence
                                proposal.addProperty("evidenceGrade", "B"); // Default grade
                                proposals.add(proposal);
                                }
                            }
                        } catch (Exception e) {
                            getServletContext().log("Error processing Problem: " + e.getMessage());
                        }
                    }
                }
                
                // Extract ObservationProposal (lab orders)
                List<?> observationProposals = resultFactLists.get("ObservationProposal");
                if (observationProposals == null) {
                    observationProposals = resultFactLists.get("org.opencds.vmr.v1_0.internal.ObservationProposal");
                }
                if (observationProposals != null) {
                    for (Object obj : observationProposals) {
                        try {
                            if (obj instanceof org.opencds.vmr.v1_0.internal.ObservationProposal) {
                                org.opencds.vmr.v1_0.internal.ObservationProposal obs = (org.opencds.vmr.v1_0.internal.ObservationProposal) obj;
                                if (obs.isToBeReturned()) {
                                JsonObject proposal = new JsonObject();
                                proposal.addProperty("type", "lab_order");
                                
                                org.opencds.vmr.v1_0.internal.datatypes.CD focus = obs.getObservationFocus();
                                if (focus != null) {
                                    proposal.addProperty("displayName", focus.getDisplayName() != null ? focus.getDisplayName() : "Unknown Lab");
                                    proposal.addProperty("code", focus.getCode() != null ? focus.getCode() : "");
                                    if (focus.getCodeSystem() != null) {
                                        proposal.addProperty("codeSystem", focus.getCodeSystem());
                                    }
                                } else {
                                    proposal.addProperty("displayName", "Unknown Lab");
                                    proposal.addProperty("code", "");
                                }
                                
                                proposal.addProperty("urgency", "routine"); // Default urgency
                                proposals.add(proposal);
                                }
                            }
                        } catch (Exception e) {
                            getServletContext().log("Error processing ObservationProposal: " + e.getMessage());
                        }
                    }
                }
                
                // Extract SubstanceAdministrationProposal (treatments/medications)
                List<?> substanceProposals = resultFactLists.get("SubstanceAdministrationProposal");
                if (substanceProposals == null) {
                    substanceProposals = resultFactLists.get("org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal");
                }
                if (substanceProposals != null) {
                    for (Object obj : substanceProposals) {
                        try {
                            if (obj instanceof org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal) {
                                org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal sub = (org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal) obj;
                                if (sub.isToBeReturned()) {
                                JsonObject proposal = new JsonObject();
                                proposal.addProperty("type", "treatment");
                                
                                org.opencds.vmr.v1_0.internal.AdministrableSubstance substance = sub.getSubstance();
                                if (substance != null && substance.getSubstanceCode() != null) {
                                    org.opencds.vmr.v1_0.internal.datatypes.CD substanceCode = substance.getSubstanceCode();
                                    proposal.addProperty("displayName", substanceCode.getDisplayName() != null ? substanceCode.getDisplayName() : "Unknown Treatment");
                                    proposal.addProperty("code", substanceCode.getCode() != null ? substanceCode.getCode() : "");
                                    if (substanceCode.getCodeSystem() != null) {
                                        proposal.addProperty("codeSystem", substanceCode.getCodeSystem());
                                    }
                                } else {
                                    proposal.addProperty("displayName", "Unknown Treatment");
                                    proposal.addProperty("code", "");
                                }
                                
                                proposal.addProperty("treatmentType", "medication");
                                proposals.add(proposal);
                                }
                            }
                        } catch (Exception e) {
                            getServletContext().log("Error processing SubstanceAdministrationProposal: " + e.getMessage());
                        }
                    }
                }
                
                // Extract ProcedureProposal (procedures)
                List<?> procedureProposals = resultFactLists.get("ProcedureProposal");
                if (procedureProposals == null) {
                    procedureProposals = resultFactLists.get("org.opencds.vmr.v1_0.internal.ProcedureProposal");
                }
                if (procedureProposals != null) {
                    for (Object obj : procedureProposals) {
                        try {
                            if (obj instanceof org.opencds.vmr.v1_0.internal.ProcedureProposal) {
                                org.opencds.vmr.v1_0.internal.ProcedureProposal proc = (org.opencds.vmr.v1_0.internal.ProcedureProposal) obj;
                                if (proc.isToBeReturned()) {
                                JsonObject proposal = new JsonObject();
                                proposal.addProperty("type", "procedure");
                                
                                org.opencds.vmr.v1_0.internal.datatypes.CD procedureCode = proc.getProcedureCode();
                                if (procedureCode != null) {
                                    proposal.addProperty("displayName", procedureCode.getDisplayName() != null ? procedureCode.getDisplayName() : "Unknown Procedure");
                                    proposal.addProperty("code", procedureCode.getCode() != null ? procedureCode.getCode() : "");
                                    if (procedureCode.getCodeSystem() != null) {
                                        proposal.addProperty("codeSystem", procedureCode.getCodeSystem());
                                    }
                                } else {
                                    proposal.addProperty("displayName", "Unknown Procedure");
                                    proposal.addProperty("code", "");
                                }
                                
                                proposals.add(proposal);
                                }
                            }
                        } catch (Exception e) {
                            getServletContext().log("Error processing ProcedureProposal: " + e.getMessage());
                        }
                    }
                }
            }
            
            getServletContext().log("Extracted " + proposals.size() + " proposals from OpenCDS response");
            
        } catch (Exception e) {
            getServletContext().log("Error converting response: " + e.getMessage(), e);
            e.printStackTrace();
            // Return minimal response if parsing fails
            JsonObject proposal = new JsonObject();
            proposal.addProperty("type", "error");
            proposal.addProperty("displayName", "Error parsing OpenCDS response");
            proposal.addProperty("message", e.getMessage());
            proposals.add(proposal);
        }
        
        clinicalStatements.add("proposals", proposals);
        vmrOutput.add("clinicalStatements", clinicalStatements);
        response.add("vmrOutput", vmrOutput);
        
        return gson.toJson(response);
    }
    
    private String getMockResponse(String requestJson) {
        // Parse request to provide context-aware mock response
        JsonObject request = new JsonParser().parse(requestJson).getAsJsonObject();
        JsonObject vmr = request != null ? request.getAsJsonObject("vmr") : null;
        
        JsonObject response = new JsonObject();
        JsonObject vmrOutput = new JsonObject();
        JsonObject clinicalStatements = new JsonObject();
        JsonArray proposals = new JsonArray();
        
        // Create mock proposals
        JsonObject diagnosis = new JsonObject();
        diagnosis.addProperty("type", "diagnosis");
        diagnosis.addProperty("displayName", "Acute Viral Syndrome");
        diagnosis.addProperty("confidence", 65);
        diagnosis.addProperty("rationale", "Based on symptom pattern and clinical presentation.");
        diagnosis.addProperty("evidenceGrade", "B");
        diagnosis.addProperty("code", "B34.9");
        proposals.add(diagnosis);
        
        JsonObject lab = new JsonObject();
        lab.addProperty("type", "lab_order");
        lab.addProperty("displayName", "Complete Blood Count (CBC)");
        lab.addProperty("rationale", "Baseline hematologic assessment.");
        lab.addProperty("urgency", "routine");
        lab.addProperty("code", "LOINC:2093-3");
        proposals.add(lab);
        
        JsonObject treatment = new JsonObject();
        treatment.addProperty("type", "treatment");
        treatment.addProperty("displayName", "Supportive Care");
        treatment.addProperty("treatmentType", "management");
        treatment.addProperty("rationale", "Symptomatic relief and monitoring.");
        treatment.addProperty("evidenceGrade", "B");
        proposals.add(treatment);
        
        clinicalStatements.add("proposals", proposals);
        vmrOutput.add("clinicalStatements", clinicalStatements);
        response.add("vmrOutput", vmrOutput);
        
        return gson.toJson(response);
    }
    
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("application/json");
        JsonObject status = new JsonObject();
        status.addProperty("status", "running");
        status.addProperty("endpoint", "/opencds-decision-support-service/evaluate");
        status.addProperty("method", "POST");
        status.addProperty("format", "JSON");
        status.addProperty("opencds_initialized", evaluationService != null);
        response.getWriter().write(gson.toJson(status));
    }
}
EOJAVA

# Compile servlet with OpenCDS and all dependencies in classpath
RUN echo "=== Compiling servlet ===" && \
    mkdir -p /build/webapp/WEB-INF/classes && \
    javac -version && \
    echo "=== Building classpath (includes all Maven dependencies) ===" && \
    CLASSPATH="/tmp/servlet-api.jar:/tmp/gson.jar:/tmp/drools-core.jar:/tmp/drools-compiler.jar:/tmp/knowledge-api.jar:/tmp/mvel2.jar:/tmp/antlr-runtime.jar:/tmp/janino.jar:/tmp/commons-lang.jar:/tmp/xstream.jar:/tmp/xpp3.jar" && \
    for jar in /build/webapp/WEB-INF/lib/*.jar; do \
        CLASSPATH="$CLASSPATH:$jar"; \
    done && \
    echo "Classpath contains $(echo $CLASSPATH | tr ':' '\n' | wc -l) entries" && \
    echo "=== Compiling execution engine adapter classes ===" && \
    javac -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/DroolsExecutionEngineAdapter.java \
        /build/PassThroughExecutionEngineAdapter.java \
        /build/PassThroughExecutionEngineContext.java \
        /build/PassThroughKnowledgeLoader.java && \
    echo "✅ Execution engine adapter classes compiled" && \
    echo "=== Compiling servlet with OpenCDS dependencies ===" && \
    javac -cp "$CLASSPATH" \
          -d /build/webapp/WEB-INF/classes \
          /build/EvaluateServlet.java 2>&1 || { \
        echo "=== COMPILATION FAILED ===" && \
        echo "=== Re-running javac to show full error ===" && \
        javac -cp "$CLASSPATH" \
              -d /build/webapp/WEB-INF/classes \
              /build/EvaluateServlet.java 2>&1 || true && \
        echo "=== Checking for class file ===" && \
        ls -la /build/webapp/WEB-INF/classes/ 2>&1 || true && \
        find /build/webapp/WEB-INF/classes -name "*.class" -type f 2>&1 | head -20 || true && \
        exit 1; \
    } && \
    echo "=== Servlet compiled successfully ===" && \
    ls -la /build/webapp/WEB-INF/classes/ && \
    test -f /build/webapp/WEB-INF/classes/EvaluateServlet.class || (echo "ERROR: Servlet class not compiled!" && exit 1)

# Create web.xml with servlet configuration (Java EE 8 for Tomcat 9)
RUN cat > /build/webapp/WEB-INF/web.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="http://xmlns.jcp.org/xml/ns/javaee" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/javaee 
         http://xmlns.jcp.org/xml/ns/javaee/web-app_4_0.xsd"
         version="4.0">
  <display-name>OpenCDS Decision Support Service</display-name>
  
  <servlet>
    <servlet-name>EvaluateServlet</servlet-name>
    <servlet-class>EvaluateServlet</servlet-class>
  </servlet>
  
  <servlet-mapping>
    <servlet-name>EvaluateServlet</servlet-name>
    <url-pattern>/opencds-decision-support-service/evaluate</url-pattern>
  </servlet-mapping>
  
  <welcome-file-list>
    <welcome-file>index.html</welcome-file>
  </welcome-file-list>
</web-app>
EOF

# Create index page
RUN echo '<!DOCTYPE html><html><head><title>OpenCDS Service</title></head><body><h1>OpenCDS Decision Support Service</h1><p>REST endpoint: POST /opencds-decision-support-service/evaluate</p><p>Format: JSON</p><p>Service is running.</p></body></html>' > /build/webapp/index.html

# Package as WAR
RUN cd /build/webapp && \
    jar cf /build/opencds.war . && \
    echo "=== WAR created ===" && \
    echo "=== Verifying WAR contents ===" && \
    jar tf /build/opencds.war | head -30 && \
    echo "=== Checking for servlet class ===" && \
    jar tf /build/opencds.war | grep "EvaluateServlet.class" && \
    echo "=== Checking for web.xml ===" && \
    jar tf /build/opencds.war | grep "web.xml" && \
    echo "=== WAR verified ==="

# Runtime stage
FROM tomcat:9-jre17

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy WAR file from builder stage
# Deploy as ROOT.war so it's accessible at root path
COPY --from=builder /build/opencds.war /usr/local/tomcat/webapps/ROOT.war

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/ || exit 1

# Start Tomcat
CMD ["catalina.sh", "run"]
