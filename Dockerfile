FROM node:22-alpine

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev --ignore-scripts

COPY --chown=node:node . .

USER node

EXPOSE 3000

CMD ["node", "src/index.js"]

HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/status').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"