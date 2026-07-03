FROM node:22-bookworm-slim AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.24.0 --activate

COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY frontend/ ./

ARG VITE_API_MODE=http
ARG VITE_API_BASE_URL=/api
ARG VITE_MOCK_DELAY_MS=400
ARG VITE_TIMELINE_POLL_INTERVAL_MS=5000

ENV VITE_API_MODE=${VITE_API_MODE}
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}
ENV VITE_MOCK_DELAY_MS=${VITE_MOCK_DELAY_MS}
ENV VITE_TIMELINE_POLL_INTERVAL_MS=${VITE_TIMELINE_POLL_INTERVAL_MS}

RUN pnpm exec vite build

FROM nginx:1.27-alpine

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80
