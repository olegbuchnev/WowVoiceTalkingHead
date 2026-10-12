# syntax=docker/dockerfile:1
FROM node:24-alpine AS build
WORKDIR /app/web/voice-vote
COPY web/voice-vote/package*.json ./
RUN npm ci
COPY web/voice-vote/src/ src/
COPY web/voice-vote/public/ public/
COPY web/voice-vote/index.html ./
COPY web/voice-vote/docker/vite.config.mjs docker/vite.config.mjs
RUN npm run build -- --config docker/vite.config.mjs

FROM node:24-alpine AS runtime
RUN apk add --no-cache nginx
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts && npm cache clean --force
COPY tools/import-forever-audio.js tools/import-forever-audio.js
COPY src/CameraModels.lua src/CameraProfiles.lua src/
COPY web/voice-vote/server.mjs web/voice-vote/portrait-camera.mjs web/voice-vote/viewer-lighting.mjs web/voice-vote/native-camera-samples.json web/voice-vote/portable-data.mjs web/voice-vote/serve.mjs web/voice-vote/
COPY web/voice-vote/docker/nginx.conf web/voice-vote/docker/nginx.conf
COPY --from=build /app/web/voice-vote/dist/ web/voice-vote/dist/
RUN mkdir -p /cache && chown node:node /cache
ENV NODE_ENV=production VOICE_VOTE_MODEL_CACHE=/cache
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
CMD ["node","web/voice-vote/serve.mjs"]
