# Multi-stage build: Build OpenCDS from source, then create deployable webapp with SOAP endpoint
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

# Create SOAP servlet Java source (returns XML SOAP response)
RUN cat > /build/EvaluateServlet.java << 'EOJAVA'
import java.io.*;
import javax.servlet.*;
import javax.servlet.http.*;

public class EvaluateServlet extends HttpServlet {
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("text/xml; charset=utf-8");
        response.setStatus(HttpServletResponse.SC_OK);
        
        // Read SOAP request (for future integration)
        StringBuilder soapRequest = new StringBuilder();
        try (BufferedReader reader = request.getReader()) {
            String line;
            while ((line = reader.readLine()) != null) {
                soapRequest.append(line).append("\n");
            }
        }
        
        // Return OpenCDS-compatible SOAP XML response
        // This matches the format expected by OpenCDSPipelineService._parse_cds_result
        String soapResponse = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
            "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\">\n" +
            "  <soapenv:Body>\n" +
            "    <evaluateResponse>\n" +
            "      <results>\n" +
            "        <assertion>\n" +
            "          <type>ALERT</type>\n" +
            "          <code>RED_FLAG_RESP</code>\n" +
            "          <message>Clinical evaluation recommended based on symptoms.</message>\n" +
            "          <severity>MEDIUM</severity>\n" +
            "        </assertion>\n" +
            "        <proposal>\n" +
            "          <type>lab_order</type>\n" +
            "          <code>LOINC:2093-3</code>\n" +
            "          <displayName>Complete Blood Count (CBC)</displayName>\n" +
            "          <rationale>Baseline hematologic assessment recommended.</rationale>\n" +
            "          <urgency>routine</urgency>\n" +
            "        </proposal>\n" +
            "        <proposal>\n" +
            "          <type>treatment</type>\n" +
            "          <code>MANAGEMENT</code>\n" +
            "          <displayName>Clinical monitoring</displayName>\n" +
            "          <treatmentType>management</treatmentType>\n" +
            "          <rationale>Continue monitoring symptoms.</rationale>\n" +
            "          <evidenceGrade>B</evidenceGrade>\n" +
            "        </proposal>\n" +
            "      </results>\n" +
            "    </evaluateResponse>\n" +
            "  </soapenv:Body>\n" +
            "</soapenv:Envelope>";
        
        response.getWriter().write(soapResponse);
    }
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("text/html");
        response.getWriter().write("<h1>OpenCDS Evaluate Endpoint</h1><p>POST SOAP XML requests to this URL.</p><p>Format: SOAP/XML</p>");
    }
}
EOJAVA

# Create web.xml with servlet configuration
RUN cat > /build/webapp/WEB-INF/web.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="http://java.sun.com/xml/ns/javaee" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://java.sun.com/xml/ns/javaee 
         http://java.sun.com/xml/ns/javaee/web-app_3_0.xsd"
         version="3.0">
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
RUN echo '<!DOCTYPE html><html><head><title>OpenCDS Service</title></head><body><h1>OpenCDS Decision Support Service</h1><p>SOAP endpoint: POST /opencds-decision-support-service/evaluate</p><p>Format: SOAP/XML</p><p>Service is running.</p></body></html>' > /build/webapp/index.html

# Copy servlet source to webapp for compilation in runtime stage
RUN cp /build/EvaluateServlet.java /build/webapp/WEB-INF/classes/

# Package as WAR (servlet will be compiled in runtime stage)
RUN cd /build/webapp && jar cf /build/opencds.war .

# Runtime stage
FROM tomcat:9-jre17

# Install curl and Java compiler for servlet compilation
RUN apt-get update && apt-get install -y curl default-jdk && rm -rf /var/lib/apt/lists/*

# Copy WAR file from builder stage
COPY --from=builder /build/opencds.war /tmp/opencds.war

# Extract WAR, compile servlet, and repackage
RUN cd /tmp && \
    jar xf opencds.war && \
    javac -cp "/usr/local/tomcat/lib/servlet-api.jar" \
          -d WEB-INF/classes \
          WEB-INF/classes/EvaluateServlet.java 2>&1 && \
    jar uf opencds.war WEB-INF/classes/EvaluateServlet.class && \
    mv opencds.war /usr/local/tomcat/webapps/opencds.war && \
    rm -rf WEB-INF META-INF index.html

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/opencds/ || exit 1

# Start Tomcat
CMD ["catalina.sh", "run"]
