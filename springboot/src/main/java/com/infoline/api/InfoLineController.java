package com.infoline.api;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

/**
 * Contrôleur principal de l'API InfoLine
 * Fournit les endpoints de base pour la vérification et les informations système
 * 
 * @author Équipe DevOps InfoLine
 * @version 1.0
 */
@RestController
@RequestMapping("/api/v1")  // Versioning de l'API (bonne pratique)
public class InfoLineController {

    // ── INJECTION DES VARIABLES D'ENVIRONNEMENT ─────────────────────
    // Ces variables sont définies dans application.properties
    // et peuvent être surchargées par des variables d'environnement K8s
    
    @Value("${spring.application.name:infoline-api}")
    private String applicationName;
    
    @Value("${app.version:1.0.0}")
    private String appVersion;
    
    @Value("${app.environment:dev}")
    private String environment;

    // ═══════════════════════════════════════════════════════════════
    // ENDPOINTS PUBLICS
    // ═══════════════════════════════════════════════════════════════

    /**
     * Endpoint racine - Message de bienvenue
     * URL : GET /api/v1/
     * 
     * @return Message de bienvenue avec timestamp
     */
    @GetMapping("/")
    public ResponseEntity<Map<String, Object>> home() {
        Map<String, Object> response = new HashMap<>();
        response.put("message", "🏆 Bienvenue sur InfoLine API");
        response.put("description", "API REST pour l'actualité des technologies sportives");
        response.put("version", appVersion);
        response.put("environment", environment);
        response.put("timestamp", getCurrentTimestamp());
        response.put("endpoints", Map.of(
            "health", "/api/v1/health",
            "info", "/api/v1/info",
            "status", "/api/v1/status"
        ));
        
        return ResponseEntity.ok(response);
    }

    /**
     * Endpoint de santé - Pour les probes Kubernetes
     * URL : GET /api/v1/health
     * 
     * Utilisé par :
     * - Kubernetes liveness probe (vérifie que l'app tourne)
     * - Kubernetes readiness probe (vérifie que l'app est prête)
     * - Monitoring externe
     * 
     * @return Status de santé de l'application
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("application", applicationName);
        health.put("timestamp", getCurrentTimestamp());
        
        // Vérifications additionnelles (à développer)
        Map<String, String> checks = new HashMap<>();
        checks.put("api", "UP");
        // TODO : Ajouter check database quand RDS sera connectée
        // checks.put("database", checkDatabase() ? "UP" : "DOWN");
        // TODO : Ajouter check cache si Redis est utilisé
        // checks.put("cache", checkCache() ? "UP" : "DOWN");
        
        health.put("checks", checks);
        
        return ResponseEntity.ok(health);
    }

    /**
     * Endpoint d'informations système
     * URL : GET /api/v1/info
     * 
     * Fournit des informations détaillées sur l'application
     * 
     * @return Informations système et runtime
     */
    @GetMapping("/info")
    public ResponseEntity<Map<String, Object>> info() {
        Map<String, Object> info = new HashMap<>();
        
        // Informations application
        info.put("application", Map.of(
            "name", applicationName,
            "version", appVersion,
            "environment", environment,
            "description", "API REST pour InfoLine - Actualités sportives & tech"
        ));
        
        // Informations runtime Java
        Runtime runtime = Runtime.getRuntime();
        info.put("runtime", Map.of(
            "javaVersion", System.getProperty("java.version"),
            "javaVendor", System.getProperty("java.vendor"),
            "processors", runtime.availableProcessors(),
            "memoryTotal", formatBytes(runtime.totalMemory()),
            "memoryFree", formatBytes(runtime.freeMemory()),
            "memoryUsed", formatBytes(runtime.totalMemory() - runtime.freeMemory())
        ));
        
        // Informations système
        info.put("system", Map.of(
            "os", System.getProperty("os.name"),
            "osVersion", System.getProperty("os.version"),
            "osArch", System.getProperty("os.arch")
        ));
        
        info.put("timestamp", getCurrentTimestamp());
        
        return ResponseEntity.ok(info);
    }

    /**
     * Endpoint de status détaillé
     * URL : GET /api/v1/status
     * 
     * Combine health + info pour un aperçu complet
     * 
     * @return Status complet de l'application
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> status() {
        Map<String, Object> status = new HashMap<>();
        
        status.put("status", "RUNNING");
        status.put("uptime", getUptime());
        status.put("application", applicationName);
        status.put("version", appVersion);
        status.put("environment", environment);
        status.put("timestamp", getCurrentTimestamp());
        
        // Statistiques (pour démonstration)
        status.put("stats", Map.of(
            "totalRequests", 0,  // TODO : Implémenter compteur
            "activeConnections", 0,  // TODO : Implémenter compteur
            "lastDeployment", getCurrentTimestamp()
        ));
        
        return ResponseEntity.ok(status);
    }

    // ═══════════════════════════════════════════════════════════════
    // ENDPOINT DE TEST (à retirer en production)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Endpoint de test - Simule une erreur pour tester le monitoring
     * URL : GET /api/v1/test/error
     * 
     * ⚠️ À SUPPRIMER EN PRODUCTION
     * 
     * @return Erreur 500 pour tester le monitoring
     */
    @GetMapping("/test/error")
    public ResponseEntity<Map<String, String>> testError() {
        Map<String, String> error = new HashMap<>();
        error.put("error", "Test error endpoint");
        error.put("message", "Ceci est une erreur de test pour vérifier le monitoring");
        error.put("timestamp", getCurrentTimestamp());
        
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(error);
    }

    /**
     * Endpoint de test - Simule une latence
     * URL : GET /api/v1/test/slow?delay=2000
     * 
     * @param delay Délai en millisecondes (default: 2000ms)
     * @return Message après délai
     */
    @GetMapping("/test/slow")
    public ResponseEntity<Map<String, Object>> testSlow(
            @RequestParam(defaultValue = "2000") int delay) {
        
        try {
            Thread.sleep(delay);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Réponse après délai de " + delay + "ms");
        response.put("delay", delay + "ms");
        response.put("timestamp", getCurrentTimestamp());
        
        return ResponseEntity.ok(response);
    }

    // ═══════════════════════════════════════════════════════════════
    // MÉTHODES UTILITAIRES PRIVÉES
    // ═══════════════════════════════════════════════════════════════

    /**
     * Obtient le timestamp actuel formaté
     * 
     * @return Timestamp au format ISO 8601
     */
    private String getCurrentTimestamp() {
        return LocalDateTime.now()
            .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }

    /**
     * Formate les bytes en format lisible (Ko, Mo, Go)
     * 
     * @param bytes Nombre de bytes
     * @return Chaîne formatée (ex: "256 MB")
     */
    private String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        String pre = "KMGTPE".charAt(exp - 1) + "";
        return String.format("%.1f %sB", bytes / Math.pow(1024, exp), pre);
    }

    /**
     * Calcule l'uptime approximatif de la JVM
     * 
     * @return Uptime formaté
     */
    private String getUptime() {
        long uptimeMillis = java.lang.management.ManagementFactory.getRuntimeMXBean().getUptime();
        long seconds = uptimeMillis / 1000;
        long minutes = seconds / 60;
        long hours = minutes / 60;
        long days = hours / 24;
        
        if (days > 0) {
            return String.format("%d days, %d hours", days, hours % 24);
        } else if (hours > 0) {
            return String.format("%d hours, %d minutes", hours, minutes % 60);
        } else if (minutes > 0) {
            return String.format("%d minutes, %d seconds", minutes, seconds % 60);
        } else {
            return String.format("%d seconds", seconds);
        }
    }
}
