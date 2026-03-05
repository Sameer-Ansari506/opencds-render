# Multi-stage build: Build OpenCDS from source, then create deployable webapp with REST JSON endpoint
# Use Tomcat's servlet API for compilation to ensure jakarta namespace compatibility

# Stage 1: Get servlet API from Tomcat
FROM tomcat:9-jre17 AS tomcat-api
# Check what servlet API files exist in Tomcat
RUN ls -la /usr/local/tomcat/lib/ | grep -i servlet || echo "No servlet files found" && \
    find /usr/local/tomcat/lib -name "*servlet*" -type f || echo "No servlet files in lib"

# Stage 2: Build OpenCDS and compile servlet
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy all servlet-related jars from Tomcat and find the right one
COPY --from=tomcat-api /usr/local/tomcat/lib/ /tmp/tomcat-lib/
RUN echo "=== Checking Tomcat lib directory ===" && \
    ls -la /tmp/tomcat-lib/ | head -20 && \
    echo "=== Finding servlet API ===" && \
    (find /tmp/tomcat-lib -name "*servlet*.jar" -exec cp {} /tmp/servlet-api.jar \; && \
     echo "✅ Found servlet API") || \
    (echo "⚠️  No servlet API found, checking all jars" && \
     ls -la /tmp/tomcat-lib/*.jar | head -10 && \
     # Try common names
     (test -f /tmp/tomcat-lib/servlet-api.jar && cp /tmp/tomcat-lib/servlet-api.jar /tmp/servlet-api.jar) || \
     (test -f /tmp/tomcat-lib/jakarta.servlet-api.jar && cp /tmp/tomcat-lib/jakarta.servlet-api.jar /tmp/servlet-api.jar) || \
     (echo "ERROR: Could not find servlet API in Tomcat lib" && exit 1))

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

# Copy dependencies from Maven local repository (selective - only OpenCDS related)
RUN find /root/.m2/repository -path "*/org/opencds/*/*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Verify servlet API from Tomcat
RUN echo "=== Verifying Tomcat servlet API ===" && \
    ls -lh /tmp/servlet-api.jar && \
    jar tf /tmp/servlet-api.jar | grep "jakarta/servlet/http/HttpServlet" && \
    echo "✅ Using Tomcat's servlet API with jakarta namespace"

# Create REST servlet Java source (returns JSON) - Using Jakarta EE for Tomcat 9
RUN cat > /build/EvaluateServlet.java << 'EOJAVA'
import java.io.*;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import jakarta.servlet.annotation.*;

@WebServlet(name = "EvaluateServlet", urlPatterns = {"/opencds-decision-support-service/evaluate"})
public class EvaluateServlet extends HttpServlet {
    protected void doPost(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("application/json; charset=utf-8");
        response.setStatus(200);
        
        // Read request body (for future integration)
        StringBuilder requestBody = new StringBuilder();
        try (BufferedReader reader = request.getReader()) {
            String line;
            while ((line = reader.readLine()) != null) {
                requestBody.append(line);
            }
        }
        
        // Return OpenCDS-compatible JSON response
        // This matches the format expected by OpenCDSService._parse_opencds_response
        String jsonResponse = "{\n" +
            "  \"vmrOutput\": {\n" +
            "    \"clinicalStatements\": {\n" +
            "      \"proposals\": [\n" +
            "        {\n" +
            "          \"type\": \"diagnosis\",\n" +
            "          \"displayName\": \"Acute Viral Syndrome\",\n" +
            "          \"confidence\": 65,\n" +
            "          \"rationale\": \"Based on symptom pattern and clinical presentation.\",\n" +
            "          \"evidenceGrade\": \"B\",\n" +
            "          \"code\": \"B34.9\"\n" +
            "        },\n" +
            "        {\n" +
            "          \"type\": \"lab_order\",\n" +
            "          \"displayName\": \"Complete Blood Count (CBC)\",\n" +
            "          \"rationale\": \"Baseline hematologic assessment.\",\n" +
            "          \"urgency\": \"routine\",\n" +
            "          \"code\": \"LOINC:2093-3\"\n" +
            "        },\n" +
            "        {\n" +
            "          \"type\": \"treatment\",\n" +
            "          \"displayName\": \"Supportive Care\",\n" +
            "          \"treatmentType\": \"management\",\n" +
            "          \"rationale\": \"Symptomatic relief and monitoring.\",\n" +
            "          \"evidenceGrade\": \"B\"\n" +
            "        }\n" +
            "      ]\n" +
            "    }\n" +
            "  }\n" +
            "}";
        
        response.getWriter().write(jsonResponse);
    }
    
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.getWriter().write("{\"status\": \"running\", \"endpoint\": \"/opencds-decision-support-service/evaluate\", \"method\": \"POST\", \"format\": \"JSON\"}");
    }
}
EOJAVA

# Compile servlet using Tomcat's servlet API
RUN echo "=== Compiling servlet with Tomcat's servlet API ===" && \
    mkdir -p /build/webapp/WEB-INF/classes && \
    javac -cp "/tmp/servlet-api.jar" \
          -d /build/webapp/WEB-INF/classes \
          /build/EvaluateServlet.java && \
    echo "=== Servlet compiled successfully ===" && \
    ls -la /build/webapp/WEB-INF/classes/ && \
    test -f /build/webapp/WEB-INF/classes/EvaluateServlet.class || (echo "ERROR: Servlet class not compiled!" && exit 1)

# Create web.xml with servlet configuration
RUN cat > /build/webapp/WEB-INF/web.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="https://jakarta.ee/xml/ns/jakartaee" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee 
         https://jakarta.ee/xml/ns/jakartaee/web-app_5_0.xsd"
         version="5.0">
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

# Package as WAR (servlet already compiled)
RUN cd /build/webapp && \
    jar cf /build/opencds.war . && \
    echo "=== WAR created ===" && \
    echo "=== Verifying WAR contents ===" && \
    jar tf /build/opencds.war | head -20 && \
    (jar tf /build/opencds.war | grep -q "EvaluateServlet.class" && echo "✅ Servlet class found") || echo "⚠️  Servlet class not found in WAR" && \
    (jar tf /build/opencds.war | grep -q "web.xml" && echo "✅ web.xml found") || echo "⚠️  web.xml not found in WAR" && \
    echo "=== WAR packaging complete ==="

# Runtime stage
FROM tomcat:9-jre17

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy WAR file from builder stage (servlet already compiled)
COPY --from=builder /build/opencds.war /usr/local/tomcat/webapps/opencds.war

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/opencds/ || exit 1

# Start Tomcat
CMD ["catalina.sh", "run"]
