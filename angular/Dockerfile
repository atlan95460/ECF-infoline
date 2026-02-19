# ═══════════════════════════════════════════════════════════════════
# DOCKERFILE ANGULAR ULTRA-OPTIMISÉ pour t3.small
# ═══════════════════════════════════════════════════════════════════
# Taille finale : ~15-20MB (vs 200MB+ pour une image standard)
# Optimisations :
#   - Multi-stage build
#   - Node Alpine (plus léger)
#   - nginx Alpine
#   - Compression gzip
#   - Cache busting optimisé
#   - Production build avec optimisations AOT
# ═══════════════════════════════════════════════════════════════════

# ────────────────────────────────────────────────────────────────────
# ÉTAPE 1 : BUILD (Node Alpine - ~150MB)
# ────────────────────────────────────────────────────────────────────
FROM node:18-alpine AS build

# Variables d'environnement pour optimiser le build
ENV NODE_ENV=production
ENV NG_CLI_ANALYTICS=false

WORKDIR /app

# ── Copier uniquement package.json en premier (cache Docker) ────────
# Si package.json ne change pas, cette étape est mise en cache
COPY package.json package-lock.json* ./

# ── Installer les dépendances ───────────────────────────────────────
# --production=false car on a besoin de @angular/cli pour builder
RUN npm ci --quiet

# ── Copier le code source ───────────────────────────────────────────
COPY . .

# ── Build de production avec optimisations maximales ────────────────
# --configuration=production active :
#   - AOT (Ahead Of Time compilation)
#   - Minification
#   - Tree shaking
#   - Optimisation des bundles
RUN npm run build

# ────────────────────────────────────────────────────────────────────
# ÉTAPE 2 : PRODUCTION (Nginx Alpine - ~15MB)
# ────────────────────────────────────────────────────────────────────
FROM nginx:alpine

# ── Métadonnées ─────────────────────────────────────────────────────
LABEL maintainer="your-email@example.com"
LABEL description="Angular Hello World - Ultra optimisé pour t3.small"

# ── Supprimer la config nginx par défaut ───────────────────────────
RUN rm -rf /usr/share/nginx/html/*

# ── Copier l'application buildée ────────────────────────────────────
# Le chemin peut varier selon votre version d'Angular
# Angular 15+ : dist/hello-world/browser
# Angular <15 : dist/hello-world
COPY --from=build /app/dist/hello-world /usr/share/nginx/html

# ── Configuration nginx optimisée ───────────────────────────────────
COPY nginx.conf /etc/nginx/nginx.conf

# ── Activer la compression gzip ─────────────────────────────────────
RUN echo "gzip on; gzip_types text/css application/javascript application/json image/svg+xml;" \
    >> /etc/nginx/conf.d/compression.conf

# ── Healthcheck ─────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

# ── User non-root pour la sécurité ──────────────────────────────────
# RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80

# ── Démarrer nginx ──────────────────────────────────────────────────
CMD ["nginx", "-g", "daemon off;"]
