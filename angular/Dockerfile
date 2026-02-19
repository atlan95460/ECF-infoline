# ÉTAPE 1 : BUILD
FROM node:20-alpine AS build

# Désactiver les analytics pour éviter les prompts interactifs
ENV NG_CLI_ANALYTICS=false

WORKDIR /app

# Copier les fichiers de dépendances
COPY package.json package-lock.json* ./

# Installer toutes les dépendances (y compris le CLI pour le build)
RUN npm ci --quiet --legacy-peer-deps

# Copier le reste du code (le dossier src, angular.json, etc.)
COPY . .

# Lancer le build de production
RUN npm run build

# ÉTAPE 2 : PRODUCTION (Nginx)
FROM nginx:alpine

LABEL maintainer="lotfi.benhamou@gmail.com"

# Nettoyer le dossier par défaut de Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copier les fichiers compilés
# ATTENTION : Vérifie bien le nom du projet 'hello-world' dans ton angular.json
COPY --from=build /app/dist/hello-world/browser /usr/share/nginx/html

# Copier ta config nginx personnalisée
COPY nginx.conf /etc/nginx/nginx.conf

# Activer gzip pour la performance
RUN echo "gzip on; gzip_types text/css application/javascript application/json image/svg+xml;" \
    >> /etc/nginx/conf.d/compression.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
