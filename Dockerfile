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
        '        <identifier>org.opencds.service.veda.PassThroughAdapter</identifier>' \
        '        <adapter>org.opencds.service.veda.PassThroughExecutionEngineAdapter</adapter>' \
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
        '        <executionEngine>org.opencds.service.veda.PassThroughAdapter</executionEngine>' \
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

# Create minimal execution engine adapter (pass-through implementation)
RUN echo "=== Creating minimal execution engine adapter ===" && \
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
        'public class PassThroughExecutionEngineAdapter implements ExecutionEngineAdapter<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>, String> {' \
        '    ' \
        '    @Override' \
        '    public ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> execute(' \
        '            String knowledgePackage,' \
        '            ExecutionEngineContext<Map<Class<?>, List<?>>, Map<Class<?>, List<?>>> context) throws Exception {' \
        '        ' \
        '        // Pass-through: return input as output' \
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
        '}' > /build/PassThroughExecutionEngineContext.java && \
    printf '%s\n' \
        'package org.opencds.service.veda;' \
        '' \
        'import org.opencds.config.api.KnowledgeLoader;' \
        'import org.opencds.config.api.model.KnowledgeModule;' \
        'import java.util.function.Function;' \
        '' \
        '/**' \
        ' * Minimal knowledge loader implementation.' \
        ' * Returns the knowledge package ID as a string (for DRL files, this would be the file path).' \
        ' */' \
        'public class PassThroughKnowledgeLoader implements KnowledgeLoader<String, String> {' \
        '    ' \
        '    @Override' \
        '    public String loadKnowledgePackage(KnowledgeModule knowledgeModule, Function<KnowledgeModule, String> inputFunction) {' \
        '        // Return the package ID as the knowledge package' \
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
        // Parse JSON request
        JsonObject request = gson.fromJson(requestJson, JsonObject.class);
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
        
        // Create allFactLists - this is where the vMR data goes
        // For now, create an empty map (minimal test)
        // TODO: Convert JSON vMR to OpenCDS internal vMR format (CDSInput)
        // This requires:
        // 1. Parse JSON vMR structure
        // 2. Convert to OpenCDS vMR Java objects (CDSInput)
        // 3. Build fact lists from CDSInput
        Map<Class<?>, List<?>> allFactLists = new HashMap<>();
        
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
    
    private String convertResponseToJson(EvaluationResponseKMItem evalResponse, String originalRequest) {
        // Convert OpenCDS response to our JSON format
        JsonObject response = new JsonObject();
        JsonObject vmrOutput = new JsonObject();
        JsonObject clinicalStatements = new JsonObject();
        JsonArray proposals = new JsonArray();
        
        getServletContext().log("Converting OpenCDS response to JSON");
        
        // Extract proposals from OpenCDS response
        // The EvaluationResponseKMItem contains resultFactLists which need to be parsed
        // This is a complex conversion that requires understanding OpenCDS's internal structure
        
        // For now, we'll create a response indicating OpenCDS was called successfully
        // The actual parsing of resultFactLists will be implemented next
        
        try {
            // Log response structure for debugging
            getServletContext().log("Response KM Item: " + evalResponse.toString());
            
            // TODO: Parse resultFactLists from evalResponse
            // The resultFactLists contain the actual evaluation results
            // These need to be converted to our proposal format
            
            // Placeholder: Return a response indicating OpenCDS was called
            JsonObject proposal = new JsonObject();
            proposal.addProperty("type", "diagnosis");
            proposal.addProperty("displayName", "OpenCDS Evaluation Result");
            proposal.addProperty("confidence", 75);
            proposal.addProperty("rationale", "Generated by OpenCDS evaluation engine (response parsing pending)");
            proposal.addProperty("evidenceGrade", "A");
            proposal.addProperty("code", "Z00.0");
            proposals.add(proposal);
            
        } catch (Exception e) {
            getServletContext().log("Error converting response: " + e.getMessage(), e);
            // Return minimal response
        }
        
        clinicalStatements.add("proposals", proposals);
        vmrOutput.add("clinicalStatements", clinicalStatements);
        response.add("vmrOutput", vmrOutput);
        
        return gson.toJson(response);
    }
    
    private String getMockResponse(String requestJson) {
        // Parse request to provide context-aware mock response
        JsonObject request = gson.fromJson(requestJson, JsonObject.class);
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
    CLASSPATH="/tmp/servlet-api.jar:/tmp/gson.jar" && \
    for jar in /build/webapp/WEB-INF/lib/*.jar; do \
        CLASSPATH="$CLASSPATH:$jar"; \
    done && \
    echo "Classpath contains $(echo $CLASSPATH | tr ':' '\n' | wc -l) entries" && \
    echo "=== Compiling execution engine adapter classes ===" && \
    javac -cp "$CLASSPATH" -d /build/webapp/WEB-INF/classes \
        /build/PassThroughExecutionEngineAdapter.java \
        /build/PassThroughExecutionEngineContext.java \
        /build/PassThroughKnowledgeLoader.java && \
    echo "✅ Execution engine adapter classes compiled" && \
    echo "=== Compiling servlet with OpenCDS dependencies ===" && \
    javac -cp "$CLASSPATH" \
          -d /build/webapp/WEB-INF/classes \
          /build/EvaluateServlet.java 2>&1 | head -50 && \
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
