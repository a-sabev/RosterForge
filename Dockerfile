# syntax=docker/dockerfile:1

FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
# Tests use Testcontainers and need a container runtime, so they run outside the image build.
RUN --mount=type=cache,target=/root/.m2 mvn -B -q -DskipTests package

FROM docker.io/library/eclipse-temurin:21-jre
RUN useradd --system --uid 10001 rosterforge
USER rosterforge
WORKDIR /app
COPY --from=build /workspace/target/*.jar app.jar
EXPOSE 8080
# Overall actuator health: UP only once the app has started and its datasource is reachable.
# start-period covers Flyway and context startup, so a slow start isn't counted as a failure.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
