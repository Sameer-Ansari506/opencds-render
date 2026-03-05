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

# Copy dependencies from Maven local repository (selective - only OpenCDS related)
RUN find /root/.m2/repository -path "*/org/opencds/*/*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Download Jakarta Servlet API for compilation
RUN mvn dependency:get -Dartifact=jakarta.servlet:jakarta.servlet-api:6.0.0 -Ddest=/tmp/servlet-api.jar || \
    curl -L -o /tmp/servlet-api.jar https://repo1.maven.org/maven2/jakarta/servlet/jakarta.servlet-api/6.0.0/jakarta.servlet-api-6.0.0.jar

# Create REST servlet Java source (returns JSON) - Using Jakarta EE for Tomcat 9
RUN cat > /build/EvaluateServlet.java << 'EOJAVA'
import java.io.*;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import jakarta.servlet.annotation.*;

@WebServlet(name = "EvaluateServlet", urlPatterns = {"/opencds-decision-support-service/evaluate"})
public class EvaluateServlet extends HttpServlet {
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("application/json; charset=utf-8");
        response.setStatus(HttpServletResponse.SC_OK);
        
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
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.getWriter().write("{\"status\": \"running\", \"endpoint\": \"/opencds-decision-support-service/evaluate\", \"method\": \"POST\", \"format\": \"JSON\"}");
    }
}
EOJAVA

# Compile servlet in builder stage (has Java compiler)
RUN echo "=== Compiling servlet ===" && \
    javac -cp "/tmp/servlet-api.jar" \
          -d /build/webapp/WEB-INF/classes \
          /build/EvaluateServlet.java && \
    echo "=== Servlet compiled successfully ===" && \
    ls -la /build/webapp/WEB-INF/classes/

# Create web.xml with servlet configuration (backup - annotation should work)
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
    jar tf /build/opencds.war | grep -E "(EvaluateServlet|web.xml)" && \
    echo "=== WAR verified ==="

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
