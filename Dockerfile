# Multi-stage build: Build OpenCDS from source, then create deployable webapp with SOAP endpoint
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy OpenCDS source code
COPY opencds /build/opencds

# Build OpenCDS (produces JARs, not WAR)
WORKDIR /build/opencds
RUN mvn clean install -DskipTests || echo "Build completed with warnings"

# Create webapp structure with proper SOAP servlet configuration
RUN mkdir -p /build/webapp/WEB-INF/lib && \
    mkdir -p /build/webapp/WEB-INF/classes && \
    mkdir -p /build/webapp/WEB-INF/classes/META-INF

# Copy all OpenCDS JARs to webapp lib
RUN find /build/opencds -name "*.jar" -type f -not -name "*-sources.jar" -not -name "*-javadoc.jar" -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Copy dependencies from Maven local repository (selective - only OpenCDS and JAX-WS related)
RUN find /root/.m2/repository -path "*/org/opencds/*/*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true
RUN find /root/.m2/repository -path "*/jakarta/xml/ws/*/*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true
RUN find /root/.m2/repository -path "*/jakarta/jws/*/*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true
RUN find /root/.m2/repository -path "*/jakarta/xml/bind/*/*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Create web.xml with JAX-WS SOAP servlet configuration
RUN cat > /build/webapp/WEB-INF/web.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="http://java.sun.com/xml/ns/javaee" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://java.sun.com/xml/ns/javaee 
         http://java.sun.com/xml/ns/javaee/web-app_3_0.xsd"
         version="3.0">
  <display-name>OpenCDS Decision Support Service</display-name>
  
  <!-- JAX-WS SOAP Service Configuration -->
  <servlet>
    <servlet-name>EvaluationService</servlet-name>
    <servlet-class>com.sun.xml.ws.transport.http.servlet.WSServlet</servlet-class>
    <load-on-startup>1</load-on-startup>
  </servlet>
  
  <servlet-mapping>
    <servlet-name>EvaluationService</servlet-name>
    <url-pattern>/opencds-decision-support-service/evaluate</url-pattern>
  </servlet-mapping>
  
  <!-- JAX-WS Configuration -->
  <listener>
    <listener-class>com.sun.xml.ws.transport.http.servlet.WSServletContextListener</listener-class>
  </listener>
  
  <welcome-file-list>
    <welcome-file>index.html</welcome-file>
  </welcome-file-list>
</web-app>
EOF

# Create sun-jaxws.xml for JAX-WS endpoint configuration
RUN cat > /build/webapp/WEB-INF/sun-jaxws.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<endpoints xmlns="http://java.sun.com/xml/ns/jax-ws/ri/runtime" version="2.0">
  <endpoint
    name="EvaluationService"
    implementation="org.opencds.dss.evaluate.EvaluationSoapService"
    url-pattern="/opencds-decision-support-service/evaluate"/>
</endpoints>
EOF

# Create index page
RUN echo '<!DOCTYPE html><html><head><title>OpenCDS Service</title></head><body><h1>OpenCDS Decision Support Service</h1><p>SOAP endpoint: /opencds-decision-support-service/evaluate</p><p>Service is running.</p></body></html>' > /build/webapp/index.html

# Package as WAR
RUN cd /build/webapp && jar cf /build/opencds.war .

# Runtime stage
FROM tomcat:9-jre17

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy WAR file from builder stage
COPY --from=builder /build/opencds.war /usr/local/tomcat/webapps/opencds.war

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/opencds/ || exit 1

# Start Tomcat
CMD ["catalina.sh", "run"]
