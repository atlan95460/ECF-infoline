# ═══════════════════════════════════════════════════════════════════
# DOCKERFILE - InfoLine API (Spring Boot + Java 17)
# ═══════════════════════════════════════════════════════════════════
# Build multi-stage optimisé pour :
#   - Réduire la taille de l'image finale (~140 Mo au lieu de 700 Mo)
#   - Accélérer les builds grâce au cache des layers Docker
#   - Améliorer la sécurité (utilisateur non-root, image slim)
#   - Optimiser les performances runtime (JVM flags Java 17)
# ═══════════════════════════════════════════════════════════════════

# ── ÉTAPE 1 : BUILD (Image Maven temporaire) ─────────────────────────
# Cette étape sera jetée après la compilation
FROM maven:3.9-eclipse-temurin-17-alpine AS builder

# Métadonnées de l'image
LABEL maintainer="Team DevOps InfoLine"
LABEL description="Builder stage for InfoLine API"
LABEL java.version="17"

# Définir le répertoire de travail
WORKDIR /build

# 1 : Copier pom.xml AVANT le code source
# → Permet de cacher les dépendances si seul le code change
COPY pom.xml .

# Télécharger les dépendances (cette layer sera cachée)
RUN mvn dependency:go-offline -B

# Copier le code source
COPY src ./src

# 2 : Build avec flags optimisés
# -DskipTests : Skip les tests (déjà exécutés en CI/CD)
# -B : Mode batch (pas d'output interactif)
# --no-transfer-progress : Moins de logs (build plus rapide)
RUN mvn clean package -DskipTests -B --no-transfer-progress

# Vérifier que le JAR a bien été créé
RUN ls -lh target/*.jar

# ── ÉTAPE 2 : RUNTIME (Image finale légère) ──────────────────────────
FROM eclipse-temurin:17-jre-alpine

# Métadonnées de l'image finale
LABEL maintainer="Team DevOps InfoLine"
LABEL version="1.0.0"
LABEL description="InfoLine API - Spring Boot REST API"
LABEL java.version="17"
LABEL spring.boot.version="3.x"

# 3 : Créer un utilisateur non-root (sécurité)
# Évite d'exécuter l'application en tant que root
RUN addgroup -g 1001 -S lotfi && \
    adduser -u 1001 -S lotfi -G lotfi

# Définir le répertoire de travail
WORKDIR /app

# 4 : Copier le JAR avec un nom fixe
# Facilite les références dans ENTRYPOINT
COPY --from=builder /build/target/*.jar app.jar

# 5 : Changer le propriétaire des fichiers
RUN chown -R lotfi:lotfi /app

# Passer à l'utilisateur non-root
USER lotfi:lotfi

# Exposer le port de l'application
EXPOSE 8080

# 6 : Variables d'environnement pour la JVM
# Ces valeurs peuvent être surchargées au runtime
ENV JAVA_OPTS="-Xms256m -Xmx512m" \
    SPRING_PROFILES_ACTIVE="prod"

# 7 : Health check Docker natif
# Docker vérifie automatiquement que l'app est en vie
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/v1/health || exit 1

# 8 : Point d'entrée avec flags JVM optimisés pour Java 17
# exec : Permet d'arrêter proprement le conteneur (SIGTERM)
# -XX:+UseContainerSupport : Détecte automatiquement les limites de mémoire du conteneur
# -XX:MaxRAMPercentage=75.0 : Utilise max 75% de la RAM du conteneur
# -XX:+UseG1GC : Garbage Collector G1 (optimal pour Java 17 en conteneur)
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS \
    -XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -Djava.security.egd=file:/dev/./urandom \
    -jar app.jar"]

# ═══════════════════════════════════════════════════════════════════
# INSTRUCTIONS DE BUILD
# ═══════════════════════════════════════════════════════════════════
#
# Build de l'image :
#   docker build -t infoline-api:1.0.0 .
#   docker build -t infoline-api:latest .
#
# Run du conteneur :
#   docker run -d \
#     -p 8080:8080 \
#     -e SPRING_PROFILES_ACTIVE=dev \
#     -e JAVA_OPTS="-Xms128m -Xmx256m" \
#     --name infoline-api \
#     infoline-api:latest
#
# Build avec BuildKit (plus rapide) :
#   DOCKER_BUILDKIT=1 docker build -t infoline-api:latest .
#
# ═══════════════════════════════════════════════════════════════════
