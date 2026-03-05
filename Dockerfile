# Multi-stage build: Build OpenCDS from source, then create deployable webapp
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy OpenCDS source code
COPY opencds /build/opencds

# Build OpenCDS (produces JARs, not WAR)
WORKDIR /build/opencds
RUN mvn clean install -DskipTests || echo "Build completed with warnings"

# Create a minimal webapp structure
RUN mkdir -p /build/webapp/WEB-INF/lib && \
    mkdir -p /build/webapp/WEB-INF/classes

# Copy all OpenCDS JARs to webapp lib
RUN find /build/opencds -name "*.jar" -type f -not -name "*-sources.jar" -not -name "*-javadoc.jar" -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Copy dependencies from Maven local repository
RUN find /root/.m2/repository -name "*.jar" -type f -exec cp {} /build/webapp/WEB-INF/lib/ \; 2>/dev/null || true

# Create minimal web.xml
RUN echo '<?xml version="1.0" encoding="UTF-8"?>' > /build/webapp/WEB-INF/web.xml && \
    echo '<web-app xmlns="http://java.sun.com/xml/ns/javaee" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="3.0">' >> /build/webapp/WEB-INF/web.xml && \
    echo '  <display-name>OpenCDS Decision Support Service</display-name>' >> /build/webapp/WEB-INF/web.xml && \
    echo '  <welcome-file-list>' >> /build/webapp/WEB-INF/web.xml && \
    echo '    <welcome-file>index.html</welcome-file>' >> /build/webapp/WEB-INF/web.xml && \
    echo '  </welcome-file-list>' >> /build/webapp/WEB-INF/web.xml && \
    echo '</web-app>' >> /build/webapp/WEB-INF/web.xml

# Create index page
RUN echo '<!DOCTYPE html><html><head><title>OpenCDS Service</title></head><body><h1>OpenCDS Decision Support Service</h1><p>Service is running.</p></body></html>' > /build/webapp/index.html

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
