FROM node:22-bookworm-slim
WORKDIR /app
COPY --chown=node:node infra/private-chain/package.json ./package.json
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force
COPY --chown=node:node contracts ./contracts
COPY --chown=node:node scripts/compile.mjs ./scripts/compile.mjs
COPY --chown=node:node infra/private-chain/server.mjs infra/private-chain/gateway.mjs ./infra/private-chain/
RUN mkdir -p /data && chown node:node /data
USER node
EXPOSE 8080
CMD ["node", "infra/private-chain/server.mjs"]
