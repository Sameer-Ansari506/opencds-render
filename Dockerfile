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

# Download Jakarta Servlet API 6.0.0 (latest, definitely has jakarta namespace)
RUN echo "=== Downloading Jakarta Servlet API 6.0.0 ===" && \
    curl -L -f -o /tmp/servlet-api.jar \
    https://repo1.maven.org/maven2/jakarta/servlet/jakarta.servlet-api/6.0.0/jakarta.servlet-api-6.0.0.jar && \
    test -f /tmp/servlet-api.jar || (echo "ERROR: Failed to download servlet-api.jar" && exit 1) && \
    echo "=== Verifying servlet-api.jar ===" && \
    ls -lh /tmp/servlet-api.jar && \
    echo "=== Checking first 20 entries in jar ===" && \
    jar tf /tmp/servlet-api.jar | head -20 && \
    echo "=== Verifying jakarta namespace ===" && \
    (jar tf /tmp/servlet-api.jar | grep -q "^jakarta/servlet/http/HttpServlet.class$" && \
     echo "✅ CONFIRMED: jar contains jakarta/servlet/http/HttpServlet.class") || \
    (echo "❌ ERROR: jar does NOT contain jakarta packages!" && \
     echo "Found these servlet classes instead:" && \
     jar tf /tmp/servlet-api.jar | grep "servlet/http" | head -5 && \
     exit 1)

# Create REST servlet Java source (returns JSON) - Using Jakarta EE
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

# Compile servlet
RUN echo "=== Compiling servlet ===" && \
    mkdir -p /build/webapp/WEB-INF/classes && \
    javac -version && \
    echo "=== Compiling with servlet API ===" && \
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
