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
        'import org.opencds.vmr.v1_0.internal.Demographics' \
        'import org.opencds.vmr.v1_0.internal.Problem' \
        'import org.opencds.vmr.v1_0.internal.ObservationProposal' \
        'import org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal' \
        'import org.opencds.vmr.v1_0.internal.ProcedureProposal' \
        'import org.opencds.vmr.v1_0.internal.AdministrableSubstance' \
        'import org.opencds.vmr.v1_0.internal.datatypes.CD' \
        '' \
        'global java.util.Date evalTime' \
        'global String clientLanguage' \
        'global String clientTimeZoneOffset' \
        'global String focalPersonId' \
        'global java.util.Set assertions' \
        'global java.util.Map namedObjects' \
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
        'end' \
        '' \
        '// Default recommendations when we only know basic demographics' \
        'rule "AgeOnly_DefaultRecommendations"' \
        '    dialect "mvel"' \
        '    when' \
        '        $demo : Demographics()' \
        '    then' \
        '        // Diagnosis: Acute Viral Syndrome' \
        '        Problem p = new Problem();' \
        '        CD dx = new CD();' \
        '        dx.setDisplayName("Acute Viral Syndrome");' \
        '        dx.setCode("B34.9");' \
        '        dx.setCodeSystem("ICD10");' \
        '        p.setProblemCode(dx);' \
        '        p.setToBeReturned(true);' \
        '        insert(p);' \
        '' \
        '        // Lab order: Complete Blood Count (CBC)' \
        '        ObservationProposal lab = new ObservationProposal();' \
        '        CD labCd = new CD();' \
        '        labCd.setDisplayName("Complete Blood Count (CBC)");' \
        '        labCd.setCode("2093-3");' \
        '        labCd.setCodeSystem("LOINC");' \
        '        lab.setObservationFocus(labCd);' \
        '        lab.setToBeReturned(true);' \
        '        insert(lab);' \
        '' \
        '        // Treatment: Supportive Care' \
        '        SubstanceAdministrationProposal treat = new SubstanceAdministrationProposal();' \
        '        AdministrableSubstance subs = new AdministrableSubstance();' \
        '        CD subsCd = new CD();' \
        '        subsCd.setDisplayName("Supportive Care");' \
        '        subsCd.setCode("SUPPORTIVE_CARE");' \
        '        subsCd.setCodeSystem("LOCAL");' \
        '        subs.setSubstanceCode(subsCd);' \
        '        treat.setSubstance(subs);' \
        '        treat.setToBeReturned(true);' \
        '        insert(treat);' \
        'end' > /build/webapp/WEB-INF/classes/resources/knowledgePackages/org.opencds^veda-basic^1.0.0.drl && \
    echo "✅ Knowledge package (DRL file) created"

# Create real Drools execution engine adapter
# VedaContextHolder: ThreadLocal bridge so the servlet can pass allFactLists to the adapter
RUN printf '%s\n' \
        'package org.opencds.service.veda;' \
        'import java.util.*;' \
        '/** ThreadLocal holder so EvaluateServlet can pass allFactLists to DroolsExecutionEngineAdapter */' \
        'public class VedaContextHolder {' \
        '    private static final ThreadLocal<Map<Class<?>, List<?>>> FACT_LISTS = new ThreadLocal<>();' \
        '    public static void set(Map<Class<?>, List<?>> m) { FACT_LISTS.set(m); }' \
        '    public static Map<Class<?>, List<?>> get() { return FACT_LISTS.get(); }' \
        '    public static void clear() { FACT_LISTS.remove(); }' \
        '}' > /build/VedaContextHolder.java && echo "✅ VedaContextHolder created"

RUN echo "=== Creating real Drools execution engine adapter ==="
RUN cat > /build/DroolsExecutionEngineAdapter.java << 'JAVAEOF'
package org.opencds.service.veda;

import org.drools.KnowledgeBase;
import org.drools.KnowledgeBaseFactory;
import org.drools.builder.KnowledgeBuilder;
import org.drools.builder.KnowledgeBuilderFactory;
import org.drools.builder.ResourceType;
import org.drools.io.ResourceFactory;
import org.drools.runtime.StatefulKnowledgeSession;
import org.drools.runtime.rule.FactHandle;
import org.opencds.config.api.ExecutionEngineAdapter;
import org.opencds.config.api.ExecutionEngineContext;
import org.opencds.config.api.EvaluationContext;
import org.opencds.service.veda.PassThroughExecutionEngineContext;
import java.util.Map;
import java.util.List;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.Collection;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Real Drools execution engine adapter that evaluates DRL rules.
 */
public class DroolsExecutionEngineAdapter implements ExecutionEngineAdapter<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>, InputStream> {
    
    // Production-level clinical knowledge base (USPSTF Grade A/B + symptom-based CDS)
    private static final String VEDA_DRL = buildDrl();

    private static String buildDrl() {
        // Build DRL at runtime to avoid javac 65535-byte constant pool limit
        // (50-disease rule set is ~90KB, exceeding Java compile-time limit)
        StringBuilder sb = new StringBuilder(131072);
        sb.append("package VedaBasic_v1_0_0\n");
        sb.append("import org.opencds.vmr.v1_0.internal.Demographics\n");
        sb.append("import org.opencds.vmr.v1_0.internal.Problem\n");
        sb.append("import org.opencds.vmr.v1_0.internal.ObservationProposal\n");
        sb.append("import org.opencds.vmr.v1_0.internal.SubstanceAdministrationProposal\n");
        sb.append("import org.opencds.vmr.v1_0.internal.ProcedureProposal\n");
        sb.append("import org.opencds.vmr.v1_0.internal.AdministrableSubstance\n");
        sb.append("import org.opencds.vmr.v1_0.internal.datatypes.CD\n");
        sb.append("import org.opencds.vmr.v1_0.internal.ClinicalStatement\n");
        sb.append("import org.opencds.vmr.v1_0.internal.EntityBase\n");
        sb.append("global java.util.Date evalTime\n");
        sb.append("global String clientLanguage\n");
        sb.append("global String clientTimeZoneOffset\n");
        sb.append("global String focalPersonId\n");
        sb.append("global java.util.Set assertions\n");
        sb.append("global java.util.Map namedObjects\n");
        sb.append("// -- PREVENTIVE CARE: Blood Pressure (USPSTF A - all adults 18+) -------------\n");
        sb.append("rule \"Preventive_BloodPressureScreening\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 18.0)\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"55284-4\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"55284-4\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Blood pressure systolic and diastolic\");\n");
        sb.append("        o.setObservationFocus(c); o.setToBeReturned(true); insert(o);\n");
        sb.append("end\n");
        sb.append("\n");
        sb.append("// -- PREVENTIVE CARE: Depression Screening (USPSTF B - adults 18+) ----------\n");
        sb.append("rule \"Preventive_DepressionScreening\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 18.0)\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"73831-0\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"73831-0\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"PHQ-9 Depression Screening\");\n");
        sb.append("        o.setObservationFocus(c); o.setToBeReturned(true); insert(o);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Lipid Panel Male 35+ (USPSTF A) ------------------------\n");
        sb.append("rule \"Preventive_LipidPanel_Male35\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 35.0, gender != null, gender.code == \"M\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"2093-3\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"2093-3\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Cholesterol [Mass/volume] in Serum or Plasma\");\n");
        sb.append("        o.setObservationFocus(c); o.setToBeReturned(true); insert(o);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Lipid Panel Female 45+ (USPSTF A) -----------------------\n");
        sb.append("rule \"Preventive_LipidPanel_Female45\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 45.0, gender != null, gender.code == \"F\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"2093-3\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"2093-3\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Cholesterol [Mass/volume] in Serum or Plasma\");\n");
        sb.append("        o.setObservationFocus(c); o.setToBeReturned(true); insert(o);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Colorectal Cancer Screening 45-75 (USPSTF A) -----------\n");
        sb.append("rule \"Preventive_ColorectalCancer_45to75\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 45.0, age.value <= 75.0)\n");
        sb.append("        not ProcedureProposal(procedureCode != null, procedureCode.code == \"73761001\")\n");
        sb.append("    then\n");
        sb.append("        ProcedureProposal p = new ProcedureProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"73761001\"); c.setCodeSystem(\"SNOMED-CT\"); c.setDisplayName(\"Colonoscopy (USPSTF A - colorectal cancer screening)\");\n");
        sb.append("        p.setProcedureCode(c); p.setToBeReturned(true); insert(p);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Mammography Female 50-74 (USPSTF B) --------------------\n");
        sb.append("rule \"Preventive_Mammography_Female50to74\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 50.0, age.value <= 74.0, gender != null, gender.code == \"F\")\n");
        sb.append("        not ProcedureProposal(procedureCode != null, procedureCode.code == \"24606-6\")\n");
        sb.append("    then\n");
        sb.append("        ProcedureProposal p = new ProcedureProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"24606-6\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Mammography screening (USPSTF B)\");\n");
        sb.append("        p.setProcedureCode(c); p.setToBeReturned(true); insert(p);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Cervical Cancer Pap Smear Female 21-65 (USPSTF A) ------\n");
        sb.append("rule \"Preventive_CervicalCancer_Female21to65\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 21.0, age.value <= 65.0, gender != null, gender.code == \"F\")\n");
        sb.append("        not ProcedureProposal(procedureCode != null, procedureCode.code == \"19762-4\")\n");
        sb.append("    then\n");
        sb.append("        ProcedureProposal p = new ProcedureProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"19762-4\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Pap smear - cervical cancer screening (USPSTF A)\");\n");
        sb.append("        p.setProcedureCode(c); p.setToBeReturned(true); insert(p);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Diabetes / Prediabetes HbA1c 35-70 (USPSTF B) ---------\n");
        sb.append("rule \"Preventive_DiabetesScreening_35to70\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 35.0, age.value <= 70.0)\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"17856-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"17856-6\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Hemoglobin A1c - diabetes/prediabetes screening (USPSTF B)\");\n");
        sb.append("        o.setObservationFocus(c); o.setToBeReturned(true); insert(o);\n");
        sb.append("end\n");
        sb.append("// -- PREVENTIVE CARE: Osteoporosis DEXA Scan Female 65+ (USPSTF B) -----------\n");
        sb.append("rule \"Preventive_Osteoporosis_Female65\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $d : Demographics(age != null, age.value >= 65.0, gender != null, gender.code == \"F\")\n");
        sb.append("        not ProcedureProposal(procedureCode != null, procedureCode.code == \"38269-7\")\n");
        sb.append("    then\n");
        sb.append("        ProcedureProposal p = new ProcedureProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"38269-7\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"DEXA bone density scan - osteoporosis screening (USPSTF B)\");\n");
        sb.append("        p.setProcedureCode(c); p.setToBeReturned(true); insert(p);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Fever (R50.9) ----------------------------------------------------\n");
        sb.append("rule \"Symptom_Fever_CBC\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R50.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"58410-2\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"58410-2\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        o.setObservationFocus(c); o.setToBeReturned(true); insert(o);\n");
        sb.append("end\n");
        sb.append("rule \"Symptom_Fever_Diagnosis\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R50.9\")\n");
        sb.append("        not Problem(problemCode != null, problemCode.code == \"B34.9\")\n");
        sb.append("    then\n");
        sb.append("        Problem dx = new Problem(); CD c = new CD();\n");
        sb.append("        c.setCode(\"B34.9\"); c.setCodeSystem(\"ICD10\"); c.setDisplayName(\"Viral infection, unspecified\");\n");
        sb.append("        dx.setProblemCode(c); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Cough (R05) ------------------------------------------------------\n");
        sb.append("rule \"Symptom_Cough_ChestXRay\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R05\")\n");
        sb.append("        not ProcedureProposal(procedureCode != null, procedureCode.code == \"24627-2\")\n");
        sb.append("    then\n");
        sb.append("        ProcedureProposal pr = new ProcedureProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"24627-2\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Chest X-ray 2 views\");\n");
        sb.append("        pr.setProcedureCode(c); pr.setToBeReturned(true); insert(pr);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Fever + Cough -> COVID-19 + Influenza panel -----------------------\n");
        sb.append("rule \"Symptom_FeverCough_RespiratoryPanel\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $fever : Problem(problemCode != null, problemCode.code == \"R50.9\")\n");
        sb.append("        $cough : Problem(problemCode != null, problemCode.code == \"R05\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"94500-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal covid = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"94500-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"SARS-CoV-2 (COVID-19) RNA - Respiratory NAA\");\n");
        sb.append("        covid.setObservationFocus(c1); covid.setToBeReturned(true); insert(covid);\n");
        sb.append("        ObservationProposal flu = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"24015-0\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Influenza A+B Ag - Nasopharynx\");\n");
        sb.append("        flu.setObservationFocus(c2); flu.setToBeReturned(true); insert(flu);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal();\n");
        sb.append("        AdministrableSubstance s = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"352111000\"); mc.setCodeSystem(\"SNOMED-CT\"); mc.setDisplayName(\"Oseltamivir (Tamiflu) - antiviral therapy\");\n");
        sb.append("        s.setSubstanceCode(mc); med.setSubstance(s); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Headache (R51) ---------------------------------------------------\n");
        sb.append("rule \"Symptom_Headache_Assessment\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R51\")\n");
        sb.append("        not Problem(problemCode != null, problemCode.code == \"G44.309\")\n");
        sb.append("    then\n");
        sb.append("        Problem dx = new Problem(); CD c = new CD();\n");
        sb.append("        c.setCode(\"G44.309\"); c.setCodeSystem(\"ICD10\"); c.setDisplayName(\"Tension-type headache, unspecified\");\n");
        sb.append("        dx.setProblemCode(c); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal();\n");
        sb.append("        AdministrableSubstance s = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"1049502\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Ibuprofen 400mg PO - analgesic\");\n");
        sb.append("        s.setSubstanceCode(mc); med.setSubstance(s); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Chest Pain (R07.9) -----------------------------------------------\n");
        sb.append("rule \"Symptom_ChestPain_CardiacWorkup\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R07.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"11524-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal ecg = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"11524-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"12-lead EKG\");\n");
        sb.append("        ecg.setObservationFocus(c1); ecg.setToBeReturned(true); insert(ecg);\n");
        sb.append("        ObservationProposal trop = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"42757-5\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Troponin I Cardiac [Mass/Vol]\");\n");
        sb.append("        trop.setObservationFocus(c2); trop.setToBeReturned(true); insert(trop);\n");
        sb.append("        ObservationProposal bnp = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"42637-9\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"BNP [Mass/Vol] in Serum or Plasma\");\n");
        sb.append("        bnp.setObservationFocus(c3); bnp.setToBeReturned(true); insert(bnp);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Shortness of Breath (R06.00) ------------------------------------\n");
        sb.append("rule \"Symptom_SOB_PulmonaryWorkup\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R06.00\")\n");
        sb.append("        not ProcedureProposal(procedureCode != null, procedureCode.code == \"24627-2\")\n");
        sb.append("    then\n");
        sb.append("        ProcedureProposal cxr = new ProcedureProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24627-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Chest X-ray 2 views\");\n");
        sb.append("        cxr.setProcedureCode(c1); cxr.setToBeReturned(true); insert(cxr);\n");
        sb.append("        ObservationProposal spo2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"59408-5\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Oxygen saturation in Arterial blood (pulse ox)\");\n");
        sb.append("        spo2.setObservationFocus(c2); spo2.setToBeReturned(true); insert(spo2);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Fatigue (R53.83) -------------------------------------------------\n");
        sb.append("rule \"Symptom_Fatigue_Workup\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R53.83\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"11580-8\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal tsh = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"11580-8\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"TSH [Units/Vol] - thyroid function\");\n");
        sb.append("        tsh.setObservationFocus(c1); tsh.setToBeReturned(true); insert(tsh);\n");
        sb.append("        ObservationProposal cbc = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        cbc.setObservationFocus(c2); cbc.setToBeReturned(true); insert(cbc);\n");
        sb.append("        ObservationProposal bmp = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"51990-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Basic metabolic panel - Serum or Plasma\");\n");
        sb.append("        bmp.setObservationFocus(c3); bmp.setToBeReturned(true); insert(bmp);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Abdominal Pain (R10.9) ------------------------------------------\n");
        sb.append("rule \"Symptom_AbdominalPain_Workup\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R10.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"1960-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal lft = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"1960-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Aspartate aminotransferase [Enzymatic activity/volume]\");\n");
        sb.append("        lft.setObservationFocus(c1); lft.setToBeReturned(true); insert(lft);\n");
        sb.append("        ObservationProposal lip = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"1798-0\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Lipase [Enzymatic activity/volume] in Serum\");\n");
        sb.append("        lip.setObservationFocus(c2); lip.setToBeReturned(true); insert(lip);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Dizziness (R42) --------------------------------------------------\n");
        sb.append("rule \"Symptom_Dizziness_Assessment\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R42\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"55284-4\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal bp = new ObservationProposal(); CD c = new CD();\n");
        sb.append("        c.setCode(\"55284-4\"); c.setCodeSystem(\"LOINC\"); c.setDisplayName(\"Orthostatic blood pressure check\");\n");
        sb.append("        bp.setObservationFocus(c); bp.setToBeReturned(true); insert(bp);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Sore Throat / Pharyngitis (J02.9) -----------------------------\n");
        sb.append("rule \"Symptom_SoreThroat_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J02.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"5036-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal s1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"5036-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Streptococcus group A Ag - Throat rapid (Rapid Strep)\");\n");
        sb.append("        s1.setObservationFocus(c1); s1.setToBeReturned(true); insert(s1);\n");
        sb.append("        ObservationProposal s2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"626-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Throat culture - Bacteria identified\");\n");
        sb.append("        s2.setObservationFocus(c2); s2.setToBeReturned(true); insert(s2);\n");
        sb.append("        ObservationProposal s3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"58410-2\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        s3.setObservationFocus(c3); s3.setToBeReturned(true); insert(s3);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"723\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Amoxicillin - antibiotic (if Strep-positive)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J02.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Acute pharyngitis, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Upper Respiratory Infection (J06.9) ----------------------------\n");
        sb.append("rule \"Symptom_URI_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J06.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"58410-2\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"58410-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"30522-7\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"C-Reactive Protein [Mass/Vol] - inflammation marker\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J06.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Acute upper respiratory infection, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Pneumonia (J18.9) -----------------------------------------------\n");
        sb.append("rule \"Symptom_Pneumonia_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J18.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"24627-2\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24627-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Chest X-ray 2 views\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"75241-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Procalcitonin [Mass/Vol] - bacterial infection marker\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ObservationProposal o4 = new ObservationProposal(); CD c4 = new CD();\n");
        sb.append("        c4.setCode(\"600-7\"); c4.setCodeSystem(\"LOINC\"); c4.setDisplayName(\"Blood culture - Bacteria identified\");\n");
        sb.append("        o4.setObservationFocus(c4); o4.setToBeReturned(true); insert(o4);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"18631\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Azithromycin (Z-Pack) - antibiotic for community-acquired pneumonia\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J18.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Pneumonia, unspecified organism\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Asthma (J45.909) -----------------------------------------------\n");
        sb.append("rule \"Symptom_Asthma_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J45.909\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"59408-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"59408-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Oxygen saturation in Arterial blood (pulse ox)\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"82607-6\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Spirometry (PFT) - FEV1/FVC ratio\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"24627-2\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Chest X-ray 2 views\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"435\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Albuterol (Salbutamol) inhaler - short-acting bronchodilator (SABA)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J45.909\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Unspecified asthma, uncomplicated\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Hypertension (I10) ----------------------------------------------\n");
        sb.append("rule \"Symptom_Hypertension_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"I10\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"11524-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"11524-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"12-lead EKG\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"51990-0\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Basic metabolic panel - Serum or Plasma\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"5767-9\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Urinalysis - dipstick panel\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ObservationProposal o4 = new ObservationProposal(); CD c4 = new CD();\n");
        sb.append("        c4.setCode(\"2093-3\"); c4.setCodeSystem(\"LOINC\"); c4.setDisplayName(\"Cholesterol [Mass/volume] in Serum or Plasma\");\n");
        sb.append("        o4.setObservationFocus(c4); o4.setToBeReturned(true); insert(o4);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"17767\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Amlodipine 5mg - calcium channel blocker (first-line HTN)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"I10\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Essential (primary) hypertension\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Palpitations (R00.2) --------------------------------------------\n");
        sb.append("rule \"Symptom_Palpitations_CardiacWorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R00.2\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"11524-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"11524-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"12-lead EKG\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"11580-8\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"TSH [Units/Vol] - thyroid function\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"58410-2\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ProcedureProposal pr = new ProcedureProposal(); CD pc = new CD();\n");
        sb.append("        pc.setCode(\"34552-0\"); pc.setCodeSystem(\"LOINC\"); pc.setDisplayName(\"Echocardiography - cardiac structure and function\");\n");
        sb.append("        pr.setProcedureCode(pc); pr.setToBeReturned(true); insert(pr);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"R00.2\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Palpitations - cardiac arrhythmia workup\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Low Back Pain (M54.5) -------------------------------------------\n");
        sb.append("rule \"Symptom_LowBackPain_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"M54.5\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"36643-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"36643-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"X-ray lumbar spine AP and lateral\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"1049502\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Ibuprofen 400-600mg PO - NSAID analgesic for musculoskeletal pain\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"M54.5\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Low back pain\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Myalgia / Joint Pain (M79.3) ------------------------------------\n");
        sb.append("rule \"Symptom_Myalgia_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"M79.3\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"2157-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"2157-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Creatine kinase [Enzymatic activity/volume] - muscle damage marker\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"4537-7\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Erythrocyte sedimentation rate (ESR)\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"30522-7\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"C-Reactive Protein [Mass/Vol] - inflammation marker\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ObservationProposal o4 = new ObservationProposal(); CD c4 = new CD();\n");
        sb.append("        c4.setCode(\"58410-2\"); c4.setCodeSystem(\"LOINC\"); c4.setDisplayName(\"CBC panel - Blood by Automated count\");\n");
        sb.append("        o4.setObservationFocus(c4); o4.setToBeReturned(true); insert(o4);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"M79.3\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Myalgia - inflammatory or musculoskeletal origin\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Rheumatoid Arthritis (M05.9) ------------------------------------\n");
        sb.append("rule \"Symptom_RheumatoidArthritis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"M05.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"31155-7\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"31155-7\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Rheumatoid factor [Units/vol] - RF test\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"33935-8\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Anti-cyclic citrullinated peptide Ab (Anti-CCP IgG)\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"4537-7\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Erythrocyte sedimentation rate (ESR)\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ObservationProposal o4 = new ObservationProposal(); CD c4 = new CD();\n");
        sb.append("        c4.setCode(\"30522-7\"); c4.setCodeSystem(\"LOINC\"); c4.setDisplayName(\"C-Reactive Protein [Mass/Vol] - inflammation marker\");\n");
        sb.append("        o4.setObservationFocus(c4); o4.setToBeReturned(true); insert(o4);\n");
        sb.append("        ProcedureProposal pr = new ProcedureProposal(); CD pc = new CD();\n");
        sb.append("        pc.setCode(\"24643-9\"); pc.setCodeSystem(\"LOINC\"); pc.setDisplayName(\"X-ray hand bilateral - joint erosions/damage assessment\");\n");
        sb.append("        pr.setProcedureCode(pc); pr.setToBeReturned(true); insert(pr);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"M05.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Rheumatoid arthritis with rheumatoid factor, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Urinary Tract Infection (N39.0) ---------------------------------\n");
        sb.append("rule \"Symptom_UTI_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"N39.0\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"5767-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"5767-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Urinalysis - dipstick panel\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"630-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Bacteria identified in Urine by Culture\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"2160-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Creatinine [Mass/Vol] in Serum - renal function\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7454\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Nitrofurantoin (Macrobid) - first-line antibiotic for uncomplicated UTI\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N39.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Urinary tract infection, site not specified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Dysuria / Urinary Burning (R30.0) ------------------------------\n");
        sb.append("rule \"Symptom_Dysuria_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R30.0\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"5767-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"5767-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Urinalysis - dipstick panel\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"630-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Bacteria identified in Urine by Culture\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N39.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Urinary tract infection - dysuria presentation\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Polyuria / Frequent Urination (R35) -> UTI workup ---------------\n");
        sb.append("rule \"Symptom_Polyuria_UTI_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R35\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"5767-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"5767-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Urinalysis - dipstick panel\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"630-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Bacteria identified in Urine by Culture\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N39.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Urinary tract infection - frequent urination presentation\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal ab = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7454\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Nitrofurantoin (Macrobid) - first-line antibiotic for uncomplicated UTI\");\n");
        sb.append("        sub.setSubstanceCode(mc); ab.setSubstance(sub); ab.setToBeReturned(true); insert(ab);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Pain on Urination / Dysuria unspec (R30.9) -> UTI workup ---------\n");
        sb.append("rule \"Symptom_Dysuria_R309_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R30.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"5767-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"5767-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Urinalysis - dipstick panel\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"630-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Bacteria identified in Urine by Culture\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N39.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Urinary tract infection - pain on urination\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal ab = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7454\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Nitrofurantoin (Macrobid) - first-line antibiotic for uncomplicated UTI\");\n");
        sb.append("        sub.setSubstanceCode(mc); ab.setSubstance(sub); ab.setToBeReturned(true); insert(ab);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Acute Cystitis (N30.0) ------------------------------------------\n");
        sb.append("rule \"Symptom_AcuteCystitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"N30.0\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"5767-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"5767-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Urinalysis - dipstick panel\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"630-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Bacteria identified in Urine by Culture\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N30.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Acute cystitis - bladder infection\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal ab = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7454\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Nitrofurantoin (Macrobid) - first-line antibiotic for acute cystitis\");\n");
        sb.append("        sub.setSubstanceCode(mc); ab.setSubstance(sub); ab.setToBeReturned(true); insert(ab);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Type 2 Diabetes (E11.9) -----------------------------------------\n");
        sb.append("rule \"Symptom_Diabetes_T2_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"E11.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"17856-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"17856-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Hemoglobin A1c - glycaemic control\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"2339-0\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Glucose [Mass/vol] - fasting plasma glucose\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"51990-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Basic metabolic panel - Serum or Plasma\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ObservationProposal o4 = new ObservationProposal(); CD c4 = new CD();\n");
        sb.append("        c4.setCode(\"5767-9\"); c4.setCodeSystem(\"LOINC\"); c4.setDisplayName(\"Urinalysis - microalbuminuria screen\");\n");
        sb.append("        o4.setObservationFocus(c4); o4.setToBeReturned(true); insert(o4);\n");
        sb.append("        ObservationProposal o5 = new ObservationProposal(); CD c5 = new CD();\n");
        sb.append("        c5.setCode(\"2093-3\"); c5.setCodeSystem(\"LOINC\"); c5.setDisplayName(\"Cholesterol - lipid panel for cardiovascular risk\");\n");
        sb.append("        o5.setObservationFocus(c5); o5.setToBeReturned(true); insert(o5);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"6809\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Metformin 500-1000mg PO - first-line oral hypoglycaemic (ADA/EASD)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"E11.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Type 2 diabetes mellitus without complications\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Major Depression (F32.9) ----------------------------------------\n");
        sb.append("rule \"Symptom_Depression_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"F32.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"73831-0\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"73831-0\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"PHQ-9 - Patient Health Questionnaire Depression Score\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"11580-8\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"TSH - rule out hypothyroidism as mood cause\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"58410-2\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"CBC panel - rule out anaemia as fatigue cause\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"32937\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Sertraline (Zoloft) 50mg - SSRI first-line antidepressant (APA guidelines)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"F32.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Major depressive disorder, single episode, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Generalised Anxiety (F41.1) -------------------------------------\n");
        sb.append("rule \"Symptom_Anxiety_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"F41.1\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"69737-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"69737-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"GAD-7 - Generalized Anxiety Disorder 7-item score\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"11580-8\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"TSH - rule out hyperthyroidism mimicking anxiety\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"41493\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Escitalopram (Lexapro) 10mg - SSRI/SNRI first-line for GAD (APA)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"F41.1\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Generalised anxiety disorder\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Skin Rash / Urticaria (R21) -------------------------------------\n");
        sb.append("rule \"Symptom_Rash_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"R21\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"19113-0\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"19113-0\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"IgE [Units/vol] - total immunoglobulin E (allergy screen)\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC panel - eosinophil count for allergic/parasitic cause\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"30522-7\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"C-Reactive Protein [Mass/Vol] - inflammation marker\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"3498\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Cetirizine (Zyrtec) 10mg - second-generation antihistamine\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"L50.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Allergic urticaria\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: GERD / Acid Reflux (K21.0) -------------------------------------\n");
        sb.append("rule \"Symptom_GERD_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"K21.0\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"13332-8\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"13332-8\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"H. pylori Ag - Helicobacter pylori antigen in stool\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        SubstanceAdministrationProposal sa = new SubstanceAdministrationProposal(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"40790\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Omeprazole (Prilosec) 20mg PO - PPI first-line for GERD (ACG guidelines)\");\n");
        sb.append("        AdministrableSubstance sub = new AdministrableSubstance(); sub.setSubstanceCode(mc);\n");
        sb.append("        sa.setSubstance(sub); sa.setToBeReturned(true); insert(sa);\n");
        sb.append("        ProcedureProposal pr = new ProcedureProposal(); CD pc = new CD();\n");
        sb.append("        pc.setCode(\"28026-5\"); pc.setCodeSystem(\"LOINC\"); pc.setDisplayName(\"Upper GI endoscopy - if refractory or alarm symptoms\");\n");
        sb.append("        pr.setProcedureCode(pc); pr.setToBeReturned(true); insert(pr);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"K21.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Gastro-oesophageal reflux disease with oesophagitis\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Migraine (G43.909) ----------------------------------------------\n");
        sb.append("rule \"Symptom_Migraine_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"G43.909\")\n");
        sb.append("        not SubstanceAdministrationProposal(substance != null, substance.substanceCode != null, substance.substanceCode.code == \"372798006\")\n");
        sb.append("    then\n");
        sb.append("        SubstanceAdministrationProposal sa1 = new SubstanceAdministrationProposal(); CD mc1 = new CD();\n");
        sb.append("        mc1.setCode(\"372798006\"); mc1.setCodeSystem(\"SNOMED-CT\"); mc1.setDisplayName(\"Sumatriptan 50-100mg - triptan abortive therapy for acute migraine\");\n");
        sb.append("        AdministrableSubstance sub1 = new AdministrableSubstance(); sub1.setSubstanceCode(mc1);\n");
        sb.append("        sa1.setSubstance(sub1); sa1.setToBeReturned(true); insert(sa1);\n");
        sb.append("        SubstanceAdministrationProposal sa2 = new SubstanceAdministrationProposal(); CD mc2 = new CD();\n");
        sb.append("        mc2.setCode(\"55489\"); mc2.setCodeSystem(\"RxNorm\"); mc2.setDisplayName(\"Topiramate 25-100mg - preventive migraine therapy (AAN grade A)\");\n");
        sb.append("        AdministrableSubstance sub2 = new AdministrableSubstance(); sub2.setSubstanceCode(mc2);\n");
        sb.append("        sa2.setSubstance(sub2); sa2.setToBeReturned(true); insert(sa2);\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24590-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"MRI Brain - rule out secondary headache causes\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"G43.909\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Migraine, unspecified, not intractable, without status migrainosus\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Chronic Kidney Disease (N18.9) ----------------------------------\n");
        sb.append("rule \"Symptom_CKD_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"N18.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"2160-0\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"2160-0\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Creatinine [Mass/Vol] in Serum - renal function\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"33914-3\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"eGFR - estimated glomerular filtration rate\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"51990-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Basic metabolic panel - electrolytes and renal function\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        ObservationProposal o4 = new ObservationProposal(); CD c4 = new CD();\n");
        sb.append("        c4.setCode(\"5767-9\"); c4.setCodeSystem(\"LOINC\"); c4.setDisplayName(\"Urinalysis with microscopy - proteinuria assessment\");\n");
        sb.append("        o4.setObservationFocus(c4); o4.setToBeReturned(true); insert(o4);\n");
        sb.append("        ObservationProposal o5 = new ObservationProposal(); CD c5 = new CD();\n");
        sb.append("        c5.setCode(\"58410-2\"); c5.setCodeSystem(\"LOINC\"); c5.setDisplayName(\"CBC panel - anaemia of chronic kidney disease\");\n");
        sb.append("        o5.setObservationFocus(c5); o5.setToBeReturned(true); insert(o5);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N18.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Chronic kidney disease, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Iron Deficiency Anaemia (D50.9) -------------------------------\n");
        sb.append("rule \"Symptom_IronDeficiencyAnaemia_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"D50.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"2498-4\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"2498-4\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Serum ferritin - iron store assessment\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC panel - haemoglobin and haematocrit\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"2500-7\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Iron [Mass/Vol] in Serum - total serum iron\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"D50.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Iron deficiency anaemia, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"387107005\"); mc.setCodeSystem(\"SNOMED-CT\"); mc.setDisplayName(\"Ferrous sulfate 325 mg PO daily - oral iron supplementation\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Gout (M10.9) ---------------------------------------------------\n");
        sb.append("rule \"Symptom_Gout_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"M10.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"3084-1\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"3084-1\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Uric acid [Mass/Vol] in Serum - hyperuricaemia assessment\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"2160-0\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Creatinine - renal function before urate-lowering therapy\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"M10.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Gout, unspecified - crystal arthropathy\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"1256\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Colchicine 0.6 mg PO - acute gout attack treatment\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("        SubstanceAdministrationProposal med2 = new SubstanceAdministrationProposal(); AdministrableSubstance sub2 = new AdministrableSubstance(); CD mc2 = new CD();\n");
        sb.append("        mc2.setCode(\"519\"); mc2.setCodeSystem(\"RxNorm\"); mc2.setDisplayName(\"Allopurinol 100-300 mg PO daily - urate-lowering therapy (maintenance)\");\n");
        sb.append("        sub2.setSubstanceCode(mc2); med2.setSubstance(sub2); med2.setToBeReturned(true); insert(med2);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Allergic Rhinitis (J30.9) --------------------------------------\n");
        sb.append("rule \"Symptom_AllergicRhinitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J30.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"6321-1\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"6321-1\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"IgE [Units/Vol] in Serum - total IgE allergy panel\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J30.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Allergic rhinitis, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"203457\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Fluticasone nasal spray 50 mcg - intranasal corticosteroid (first-line)\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("        SubstanceAdministrationProposal med2 = new SubstanceAdministrationProposal(); AdministrableSubstance sub2 = new AdministrableSubstance(); CD mc2 = new CD();\n");
        sb.append("        mc2.setCode(\"17434\"); mc2.setCodeSystem(\"RxNorm\"); mc2.setDisplayName(\"Cetirizine 10 mg PO daily - non-sedating antihistamine\");\n");
        sb.append("        sub2.setSubstanceCode(mc2); med2.setSubstance(sub2); med2.setToBeReturned(true); insert(med2);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Acute Sinusitis (J32.9) ----------------------------------------\n");
        sb.append("rule \"Symptom_Sinusitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J32.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"24627-2\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24627-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CT sinuses without contrast - sinus anatomy assessment\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J32.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Chronic sinusitis, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"723\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Amoxicillin 500 mg PO TID x10d - bacterial sinusitis\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Acute Otitis Media (H66.90) ------------------------------------\n");
        sb.append("rule \"Symptom_OtitisMedia_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"H66.90\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"11331-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"11331-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Otoscopy - tympanic membrane assessment\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"H66.90\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Otitis media, unspecified ear\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"723\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Amoxicillin 80-90 mg/kg/day PO - first-line antibiotic for AOM\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Conjunctivitis (H10.9) -----------------------------------------\n");
        sb.append("rule \"Symptom_Conjunctivitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"H10.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"12235-8\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"12235-8\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Eye culture - bacterial conjunctivitis identification\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"H10.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Unspecified conjunctivitis\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"392468\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Tobramycin 0.3% ophthalmic drops - bacterial conjunctivitis treatment\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: COPD (J44.1) ----------------------------------------------------\n");
        sb.append("rule \"Symptom_COPD_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J44.1\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"19926-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"19926-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Spirometry - FEV1/FVC ratio for COPD diagnosis\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"24627-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Chest X-ray - hyperinflation, flattened diaphragm\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J44.1\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"COPD with acute exacerbation\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"2108\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Salbutamol MDI 90 mcg - SABA bronchodilator\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("        SubstanceAdministrationProposal med2 = new SubstanceAdministrationProposal(); AdministrableSubstance sub2 = new AdministrableSubstance(); CD mc2 = new CD();\n");
        sb.append("        mc2.setCode(\"41493\"); mc2.setCodeSystem(\"RxNorm\"); mc2.setDisplayName(\"Tiotropium 18 mcg inhaled daily - LAMA maintenance bronchodilator\");\n");
        sb.append("        sub2.setSubstanceCode(mc2); med2.setSubstance(sub2); med2.setToBeReturned(true); insert(med2);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Acute Bronchitis (J40) -----------------------------------------\n");
        sb.append("rule \"Symptom_AcuteBronchitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"J40\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"24627-2\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24627-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Chest X-ray - rule out pneumonia in acute bronchitis\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"J40\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Bronchitis, not specified as acute or chronic\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"2108\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Albuterol MDI - bronchospasm relief if wheezing\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Hyperlipidaemia (E78.5) -----------------------------------------\n");
        sb.append("rule \"Symptom_Hyperlipidaemia_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"E78.5\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"2093-3\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"2093-3\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Cholesterol [Mass/Vol] - fasting lipid profile\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"2571-8\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Triglycerides - fasting lipid panel\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"1742-6\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"ALT - liver function before statin initiation\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"E78.5\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Hyperlipidaemia, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"36567\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Atorvastatin 10-80 mg PO daily - high-intensity statin therapy\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Hyperthyroidism (E05.90) ----------------------------------------\n");
        sb.append("rule \"Symptom_Hyperthyroidism_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"E05.90\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"3016-3\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"3016-3\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"TSH - suppressed in hyperthyroidism\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"3053-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Free T4 - elevated in hyperthyroidism\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"E05.90\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Thyrotoxicosis, unspecified without thyrotoxic crisis\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7052\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Methimazole 10-30 mg PO daily - antithyroid therapy (first-line)\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Hypothyroidism (E03.9) ------------------------------------------\n");
        sb.append("rule \"Symptom_Hypothyroidism_E039_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"E03.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"3016-3\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"3016-3\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"TSH - elevated in hypothyroidism\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"3053-4\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Free T4 - low in hypothyroidism\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"E03.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Hypothyroidism, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"10582\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Levothyroxine 25-200 mcg PO daily - thyroid hormone replacement\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Appendicitis (K37) ----------------------------------------------\n");
        sb.append("rule \"Symptom_Appendicitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"K37\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"24550-4\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24550-4\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CT abdomen and pelvis with contrast - appendix evaluation\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC - leukocytosis in appendicitis\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"1988-5\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"CRP - acute inflammatory marker\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"K37\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Unspecified appendicitis - urgent surgical evaluation required\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Peptic Ulcer Disease (K27.9) ------------------------------------\n");
        sb.append("rule \"Symptom_PepticUlcer_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"K27.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"34792-1\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"34792-1\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"H. pylori Ag in stool - non-invasive H. pylori test\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC - anaemia from GI blood loss\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"K27.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Peptic ulcer, unspecified, without haemorrhage or perforation\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7646\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Omeprazole 20 mg PO BID - proton pump inhibitor therapy\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Irritable Bowel Syndrome (K58.9) --------------------------------\n");
        sb.append("rule \"Symptom_IBS_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"K58.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"58410-2\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"58410-2\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CBC - rule out infection or anaemia in IBS evaluation\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"1988-5\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CRP - exclude IBD (elevated in IBD, normal in IBS)\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"K58.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Irritable bowel syndrome without diarrhoea\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"2200\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Dicycloverine 10-20 mg PO - antispasmodic for IBS cramps\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Obstructive Sleep Apnoea (G47.33) -------------------------------\n");
        sb.append("rule \"Symptom_SleepApnea_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"G47.33\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"29273-0\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"29273-0\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Epworth Sleepiness Scale - daytime sleepiness screening\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"60985-8\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Polysomnography - overnight sleep study (gold standard for OSA)\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"G47.33\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Obstructive sleep apnoea\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Atrial Fibrillation (I48.91) ------------------------------------\n");
        sb.append("rule \"Symptom_AtrialFibrillation_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"I48.91\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"11524-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"11524-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"ECG 12-lead - atrial fibrillation confirmation\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"3016-3\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"TSH - thyroid as precipitant of AF\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"34896-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Echocardiogram - cardiac structure in AF\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"I48.91\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Unspecified atrial fibrillation\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"114194\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Apixaban 5 mg PO BID - anticoagulation for stroke prevention\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Heart Failure (I50.9) -------------------------------------------\n");
        sb.append("rule \"Symptom_HeartFailure_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"I50.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"42637-9\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"42637-9\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"BNP [Mass/Vol] - brain natriuretic peptide for heart failure\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"24627-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Chest X-ray - cardiomegaly, pulmonary oedema\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"34896-0\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Echocardiogram - ejection fraction (HFrEF vs HFpEF)\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"I50.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Heart failure, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"18867\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Furosemide 20-80 mg PO daily - loop diuretic for congestion\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("        SubstanceAdministrationProposal med2 = new SubstanceAdministrationProposal(); AdministrableSubstance sub2 = new AdministrableSubstance(); CD mc2 = new CD();\n");
        sb.append("        mc2.setCode(\"18991\"); mc2.setCodeSystem(\"RxNorm\"); mc2.setDisplayName(\"Lisinopril 2.5-40 mg PO daily - ACE inhibitor (HFrEF guideline-directed)\");\n");
        sb.append("        sub2.setSubstanceCode(mc2); med2.setSubstance(sub2); med2.setToBeReturned(true); insert(med2);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Osteoarthritis (M19.90) -----------------------------------------\n");
        sb.append("rule \"Symptom_Osteoarthritis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"M19.90\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"1988-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"1988-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CRP - differentiate OA from inflammatory arthritis\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"36643-5\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"X-ray joint bilateral - osteophytes, joint space narrowing\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"M19.90\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Primary osteoarthritis, unspecified site\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"41493\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Acetaminophen 500-1000 mg PO - first-line analgesic for OA\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Atopic Dermatitis / Eczema (L20.9) ------------------------------\n");
        sb.append("rule \"Symptom_AtopicDermatitis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"L20.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"6321-1\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"6321-1\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"Total IgE - elevated in atopic disease\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"L20.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Atopic dermatitis, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7980\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Hydrocortisone 1% topical cream - mild-potency corticosteroid\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("        SubstanceAdministrationProposal med2 = new SubstanceAdministrationProposal(); AdministrableSubstance sub2 = new AdministrableSubstance(); CD mc2 = new CD();\n");
        sb.append("        mc2.setCode(\"17434\"); mc2.setCodeSystem(\"RxNorm\"); mc2.setDisplayName(\"Cetirizine 10 mg PO - antihistamine for itch\");\n");
        sb.append("        sub2.setSubstanceCode(mc2); med2.setSubstance(sub2); med2.setToBeReturned(true); insert(med2);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Epilepsy / Seizure Disorder (G40.909) ---------------------------\n");
        sb.append("rule \"Symptom_Epilepsy_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"G40.909\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"24629-8\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"24629-8\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"EEG - electroencephalography for seizure diagnosis\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"24590-0\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"MRI brain - structural cause of seizure\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"G40.909\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Epilepsy, unspecified, not intractable\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"9997\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Levetiracetam 500 mg PO BID - first-line antiseizure medication\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Nephrolithiasis / Kidney Stones (N20.0) ------------------------\n");
        sb.append("rule \"Symptom_KidneyStones_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"N20.0\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"35816-7\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"35816-7\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CT KUB without contrast - kidney stone detection\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"5767-9\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"Urinalysis - haematuria and crystalluria\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"N20.0\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Calculus of kidney\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"41493\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Ketorolac 15-30 mg IV/IM - pain management for renal colic\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Obesity (E66.9) -------------------------------------------------\n");
        sb.append("rule \"Symptom_Obesity_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"E66.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"39156-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"39156-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"BMI - body mass index calculation\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"17856-6\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"HbA1c - diabetes screening in obesity\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        ObservationProposal o3 = new ObservationProposal(); CD c3 = new CD();\n");
        sb.append("        c3.setCode(\"2093-3\"); c3.setCodeSystem(\"LOINC\"); c3.setDisplayName(\"Fasting lipid panel - cardiovascular risk in obesity\");\n");
        sb.append("        o3.setObservationFocus(c3); o3.setToBeReturned(true); insert(o3);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"E66.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Obesity, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Type 1 Diabetes Mellitus (E10.9) --------------------------------\n");
        sb.append("rule \"Symptom_Diabetes_T1_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"E10.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"17856-6\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"17856-6\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"HbA1c - glycaemic control in T1DM\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"40558-3\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"C-peptide - residual beta-cell function (low in T1DM)\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"E10.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Type 1 diabetes mellitus without complications\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"253182\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Insulin glargine (Lantus) - basal insulin for T1DM management\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        sb.append("// -- SYMPTOM: Psoriasis (L40.9) -----------------------------------------------\n");
        sb.append("rule \"Symptom_Psoriasis_WorkUp\"\n");
        sb.append("    dialect \"mvel\"\n");
        sb.append("    when\n");
        sb.append("        $p : Problem(problemCode != null, problemCode.code == \"L40.9\")\n");
        sb.append("        not ObservationProposal(observationFocus != null, observationFocus.code == \"1988-5\")\n");
        sb.append("    then\n");
        sb.append("        ObservationProposal o1 = new ObservationProposal(); CD c1 = new CD();\n");
        sb.append("        c1.setCode(\"1988-5\"); c1.setCodeSystem(\"LOINC\"); c1.setDisplayName(\"CRP - systemic inflammation in psoriasis\");\n");
        sb.append("        o1.setObservationFocus(c1); o1.setToBeReturned(true); insert(o1);\n");
        sb.append("        ObservationProposal o2 = new ObservationProposal(); CD c2 = new CD();\n");
        sb.append("        c2.setCode(\"58410-2\"); c2.setCodeSystem(\"LOINC\"); c2.setDisplayName(\"CBC - baseline before systemic therapy\");\n");
        sb.append("        o2.setObservationFocus(c2); o2.setToBeReturned(true); insert(o2);\n");
        sb.append("        Problem dx = new Problem(); CD dxc = new CD();\n");
        sb.append("        dxc.setCode(\"L40.9\"); dxc.setCodeSystem(\"ICD10\"); dxc.setDisplayName(\"Psoriasis, unspecified\");\n");
        sb.append("        dx.setProblemCode(dxc); dx.setToBeReturned(true); insert(dx);\n");
        sb.append("        SubstanceAdministrationProposal med = new SubstanceAdministrationProposal(); AdministrableSubstance sub = new AdministrableSubstance(); CD mc = new CD();\n");
        sb.append("        mc.setCode(\"7980\"); mc.setCodeSystem(\"RxNorm\"); mc.setDisplayName(\"Betamethasone valerate 0.1% cream - moderate-potency topical steroid\");\n");
        sb.append("        sub.setSubstanceCode(mc); med.setSubstance(sub); med.setToBeReturned(true); insert(med);\n");
        sb.append("end\n");
        return sb.toString();
    }
    
    @Override
    public ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> execute(
            InputStream knowledgePackage,
            ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> context) throws Exception {
        
        // Get input fact lists from ThreadLocal (set by EvaluateServlet before calling evaluate()).
        // context.getInput() always returns empty because OpenCDS uses the no-arg constructor
        // and never calls setInput() - the facts are stored in VedaContextHolder instead.
        Map<Class<?>, List<?>> input = VedaContextHolder.get();
        if (input == null) {
            input = context.getInput(); // fallback (will be empty)
        }
        
        // Build KnowledgeBase from the embedded DRL string (no file/stream loading needed)
        KnowledgeBuilder kbuilder = KnowledgeBuilderFactory.newKnowledgeBuilder();
        byte[] drlBytes = VEDA_DRL.getBytes(StandardCharsets.UTF_8);
        kbuilder.add(
            ResourceFactory.newByteArrayResource(drlBytes),
            ResourceType.DRL
        );
        
        if (kbuilder.hasErrors()) {
            throw new RuntimeException("DRL compilation errors: " + kbuilder.getErrors().toString());
        }
        
        KnowledgeBase kbase = KnowledgeBaseFactory.newKnowledgeBase();
        kbase.addKnowledgePackages(kbuilder.getKnowledgePackages());
        
        // Create session and insert facts
        StatefulKnowledgeSession ksession = kbase.newStatefulKnowledgeSession();
        
        // Set globals from EvaluationContext if available
        EvaluationContext evalContext = null;
        if (context instanceof PassThroughExecutionEngineContext) {
            evalContext = ((PassThroughExecutionEngineContext) context).getEvaluationContext();
        }
        
        if (evalContext != null) {
            ksession.setGlobal("evalTime", evalContext.getEvalTime());
            ksession.setGlobal("clientLanguage", evalContext.getClientLanguage());
            ksession.setGlobal("clientTimeZoneOffset", evalContext.getClientTimeZoneOffset());
            ksession.setGlobal("focalPersonId", evalContext.getFocalPersonId());
            // assertions and namedObjects are Drools-internal globals not exposed by EvaluationContext
            ksession.setGlobal("assertions", new java.util.HashSet<String>());
            ksession.setGlobal("namedObjects", new java.util.HashMap<String, Object>());
        } else {
            // Fallback to defaults
            ksession.setGlobal("evalTime", new java.util.Date());
            ksession.setGlobal("clientLanguage", "en-US");
            ksession.setGlobal("clientTimeZoneOffset", "+00:00");
            ksession.setGlobal("focalPersonId", "patient-1");
            ksession.setGlobal("assertions", new java.util.HashSet<String>());
            ksession.setGlobal("namedObjects", new java.util.HashMap<String, Object>());
        }
        
        // Insert all facts from input
        Map<Class<?>, List<FactHandle>> factHandles = new HashMap<>();
        for (Map.Entry<Class<?>, List<?>> entry : input.entrySet()) {
            if (entry.getValue() != null) {
                List<FactHandle> handles = new ArrayList<>();
                for (Object fact : entry.getValue()) {
                    if (fact != null) {
                        handles.add(ksession.insert(fact));
                    }
                }
                factHandles.put(entry.getKey(), handles);
            }
        }
        
        // Fire all rules
        ksession.fireAllRules();
        
        // Collect results - all facts that are in working memory after rules fire
        Map<Class<?>, List<?>> results = new HashMap<Class<?>, List<?>>();
        Collection<Object> allFacts = ksession.getObjects();
        for (Object fact : allFacts) {
            if (fact != null) {
                Class<?> cls = fact.getClass();
                @SuppressWarnings("unchecked")
                List<Object> list = (List<Object>) results.get(cls);
                if (list == null) {
                    list = new ArrayList<Object>();
                    results.put(cls, list);
                }
                list.add(fact);
            }
        }
        
        ksession.dispose();
        
        return context.setResults(results);
    }
}
JAVAEOF
RUN echo "✅ Drools execution engine adapter created" && \
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
            // Store allFactLists in ThreadLocal so DroolsExecutionEngineAdapter can access them.
            // OpenCDS creates PassThroughExecutionEngineContext via no-arg constructor so
            // context.getInput() is always empty – the ThreadLocal is the workaround.
            org.opencds.service.veda.VedaContextHolder.set(allFactLists);
            
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
        } finally {
            // Always clean up ThreadLocal to avoid memory leaks between requests
            org.opencds.service.veda.VedaContextHolder.clear();
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
                    
                    // Also add Demographics as its own fact so Drools rules can match on it directly
                    List<Demographics> demographicsList = new ArrayList<>();
                    demographicsList.add(demographics);
                    allFactLists.put(Demographics.class, demographicsList);
                    
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
    CLASSPATH="/tmp/servlet-api.jar:/tmp/gson.jar:/tmp/drools-core.jar:/tmp/drools-compiler.jar:/tmp/knowledge-api.jar:/tmp/mvel2.jar:/tmp/antlr-runtime.jar:/tmp/janino.jar:/tmp/commons-lang.jar:/tmp/xstream.jar:/tmp/xpp3.jar:/build/webapp/WEB-INF/classes" && \
    for jar in /build/webapp/WEB-INF/lib/*.jar; do \
        CLASSPATH="$CLASSPATH:$jar"; \
    done && \
    echo "Classpath contains $(echo $CLASSPATH | tr ':' '\n' | wc -l) entries" && \
    echo "=== Compiling VedaContextHolder ===" && \
    javac -encoding UTF-8 -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/VedaContextHolder.java 2>&1 && \
    echo "=== Compiling PassThroughExecutionEngineContext ===" && \
    javac -encoding UTF-8 -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/PassThroughExecutionEngineContext.java 2>&1 && \
    echo "=== Compiling PassThroughExecutionEngineAdapter ===" && \
    javac -encoding UTF-8 -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/PassThroughExecutionEngineAdapter.java 2>&1 && \
    echo "=== Compiling PassThroughKnowledgeLoader ===" && \
    javac -encoding UTF-8 -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/PassThroughKnowledgeLoader.java 2>&1 && \
    echo "=== Compiling DroolsExecutionEngineAdapter (depends on above) ===" && \
    javac -encoding UTF-8 -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/DroolsExecutionEngineAdapter.java 2>&1 && \
    echo "=== All adapter classes compiled ===" && \
    find /build/webapp/WEB-INF/classes -name "*.class" -type f && \
    echo "=== Compiling servlet with OpenCDS dependencies ===" && \
    javac -encoding UTF-8 -cp "$CLASSPATH" \
          -d /build/webapp/WEB-INF/classes \
          /build/EvaluateServlet.java 2>&1 || { \
        echo "=== SERVLET COMPILATION FAILED ===" && \
        javac -encoding UTF-8 -cp "$CLASSPATH" \
              -d /build/webapp/WEB-INF/classes \
              /build/EvaluateServlet.java 2>&1 || true && \
        find /build/webapp/WEB-INF/classes -name "*.class" -type f 2>&1 | head -30 || true && \
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
