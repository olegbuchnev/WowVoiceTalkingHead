# syntax=docker/dockerfile:1
FROM node:24-bookworm-slim AS admin
WORKDIR /frontend/admin
COPY admin/package*.json ./
RUN npm ci
COPY admin/ ./
RUN npm run build

FROM eclipse-temurin:25-jdk-noble AS build
WORKDIR /build
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN sed -i 's/\r$//' mvnw && chmod +x mvnw
COPY src/ src/
COPY --from=admin /frontend/src/main/resources/static/admin/ src/main/resources/static/admin/
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q verify

FROM eclipse-temurin:25-jre-noble AS runtime
WORKDIR /app
RUN groupadd --gid 10001 vote && useradd --uid 10001 --gid vote --no-create-home vote \
    && mkdir -p /data/exports /catalogue && chown -R vote:vote /data
COPY --from=build --chown=10001:10001 /build/target/voice-vote-server-0.1.0.jar /app/server.jar
ENV SERVER_ADDRESS=0.0.0.0 \
    VOICE_VOTE_PORT=8081 \
    VOICE_VOTE_DB=/data/votes.sqlite \
    VOICE_VOTE_CATALOGUE=/catalogue/catalogue.json \
    VOICE_VOTE_EXPORT_DIR=/data/exports \
    VOICE_VOTE_ADMIN_PASSWORD_FILE=/run/secrets/admin_password
USER 10001:10001
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD ["java", "--enable-native-access=ALL-UNNAMED", "-jar", "/app/server.jar", "healthcheck"]
ENTRYPOINT ["java", "--enable-native-access=ALL-UNNAMED", "-jar", "/app/server.jar"]
