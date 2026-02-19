# ÉTAPE 1 : BUILD
FROM node:20-alpine AS build

# Désactiver les analytics pour éviter les prompts interactifs
ENV NG_CLI_ANALYTICS=false

WORKDIR /app

# Copier les fichiers de dépendances
COPY package.json package-lock.json* ./

# Utilisation de 'install' au lieu de 'ci' pour synchroniser le lockfile automatiquement
RUN npm install --quiet --legacy-peer-deps

# Copier le reste du code (NETTOYÉ : suppression du texte )
COPY . .

# Lancer le build de production
RUN npm run build

# ÉTAPE 2 : PRODUCTION (Nginx)
FROM nginx:alpine

LABEL maintainer="lotfi.benhamou@gmail.com"

# Nettoyer le dossier par défaut de Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copier les fichiers compilés (Vérifié pour Angular v17+)
COPY --from=build /app/dist/angular-hello-world/browser /usr/share/nginx/html

# Copier ta config nginx personnalisée
COPY nginx.conf /etc/nginx/nginx.conf

# Activer gzip pour la performance (NETTOYÉ : suppression du texte )
RUN echo "gzip on; gzip_types text/css application/javascript application/json image/svg+xml;" \
    >> /etc/nginx/conf.d/compression.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
