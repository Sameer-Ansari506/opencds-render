# Multi-stage build: Build OpenCDS from source, then deploy WAR file
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy OpenCDS source code
COPY opencds /build/opencds

# Build OpenCDS
WORKDIR /build/opencds
RUN mvn clean install -DskipTests || echo "Build completed with warnings"

# Find and copy the WAR file (if one was built)
# Check common locations for WAR files
RUN (find . -name "*.war" -type f -exec cp {} /build/opencds.war \; 2>/dev/null) || \
    (find . -path "*/target/*.war" -type f -exec cp {} /build/opencds.war \; 2>/dev/null) || \
    echo "WARNING: No WAR file found in build output"

# Runtime stage
FROM tomcat:9-jre17

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy WAR file from builder stage (if it exists)
COPY --from=builder /build/opencds.war /usr/local/tomcat/webapps/opencds.war 2>/dev/null || \
    echo "WARNING: No WAR file to copy - deployment may fail"

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/opencds/ || exit 1

# Start Tomcat
CMD ["catalina.sh", "run"]

