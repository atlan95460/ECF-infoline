# ═══════════════════════════════════════════════════════════════════
# VARIABLES DE CONFIGURATION - VERSION CORRIGÉE
# ═══════════════════════════════════════════════════════════════════
# CORRECTIONS APPLIQUÉES :
#   ✅ Variable db_instance_class ajoutée
#   ✅ Version Kubernetes corrigée (1.35 → 1.28)
#   ✅ Validation regex K8s optimisée
#   ✅ Toutes les variables RDS consolidées ici
# ═══════════════════════════════════════════════════════════════════

# ── CONFIGURATION GÉNÉRALE ───────────────────────────────────────────
variable "region" {
  description = "Région AWS pour le déploiement"
  type        = string
  default     = "eu-west-3"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "La région doit être au format valide AWS (ex: eu-west-3)."
  }
}

variable "environment" {
  description = "Environnement de déploiement (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "L'environnement doit être : dev, staging ou prod."
  }
}

variable "project_name" {
  description = "Nom du projet (utilisé dans les tags et noms de ressources)"
  type        = string
  default     = "infoline"
}

# ── RÉSEAU (VPC) ─────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block pour le VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Le CIDR doit être un bloc valide (ex: 10.0.0.0/16)."
  }
}

variable "public_subnet_count" {
  description = "Nombre de subnets publics à créer"
  type        = number
  default     = 2
  
  validation {
    condition     = var.public_subnet_count >= 2 && var.public_subnet_count <= 6
    error_message = "Le nombre de subnets doit être entre 2 et 6 pour la haute disponibilité."
  }
}

# ── KUBERNETES (EKS) ─────────────────────────────────────────────────
variable "cluster_name" {
  description = "Nom du cluster EKS"
  type        = string
  default     = "infoline-cluster"
}

variable "kubernetes_version" {
  description = "Version de Kubernetes pour le cluster EKS"
  type        = string
  default     = "1.28"  # ✅ CORRIGÉ : 1.35 n'existe pas, changé en 1.28
  
  validation {
    # ✅ CORRIGÉ : Regex améliorée pour accepter 1.26 à 1.99
    condition     = can(regex("^1\\.[2-9][0-9]$", var.kubernetes_version))
    error_message = "La version Kubernetes doit être au format 1.XX (ex: 1.28)."
  }
}

variable "node_desired_size" {
  description = "Nombre de worker nodes souhaité"
  type        = number
  default     = 1  # Mettre 2 pour la haute disponibilité
  
  validation {
    condition     = var.node_desired_size >= 1
    error_message = "Le nombre souhaité doit être au moins 1."
  }
}

variable "node_min_size" {
  description = "Nombre minimum de worker nodes"
  type        = number
  default     = 1
  
  validation {
    condition     = var.node_min_size >= 1
    error_message = "Le minimum doit être au moins 1 node."
  }
}

variable "node_max_size" {
  description = "Nombre maximum de worker nodes (pour l'autoscaling)"
  type        = number
  default     = 4
  
  validation {
    condition     = var.node_max_size >= var.node_min_size
    error_message = "Le maximum doit être >= au minimum."
  }
}

variable "node_instance_type" {
  description = "Type d'instance EC2 pour les worker nodes"
  type        = string
  default     = "t3.small"
  
  # Types recommandés :
  # - Dev/Test : t3.small (2 vCPU, 2 Go), t3.medium (2 vCPU, 4 Go)
  # - Prod : t3.large (2 vCPU, 8 Go), t3.xlarge (4 vCPU, 16 Go), m5.large
}

variable "node_disk_size" {
  description = "Taille du disque (Go) pour chaque worker node"
  type        = number
  default     = 20
  
  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 100
    error_message = "La taille du disque doit être entre 20 et 100 Go."
  }
}

# ── LAMBDA ───────────────────────────────────────────────────────────
variable "lambda_function_name" {
  description = "Nom de la fonction Lambda d'authentification"
  type        = string
  default     = "infoline-auth-service"
}

variable "lambda_runtime" {
  description = "Runtime de la Lambda (nodejs18.x ou java21)"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition     = contains(["nodejs18.x", "nodejs20.x", "java21", "java17"], var.lambda_runtime)
    error_message = "Runtime doit être : nodejs18.x, nodejs20.x, java21 ou java17."
  }
}

variable "lambda_handler" {
  description = "Handler de la Lambda"
  type        = string
  default     = "index.handler"
  
  # Pour Java : "com.infoline.auth.LoginHandler::handleRequest"
}

variable "lambda_memory_size" {
  description = "Mémoire allouée à la Lambda (Mo)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "La mémoire doit être entre 128 et 3008 Mo."
  }
}

variable "lambda_timeout" {
  description = "Timeout de la Lambda (secondes)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Le timeout doit être entre 3 et 900 secondes."
  }
}

# ── LOGS & MONITORING ────────────────────────────────────────────────
variable "log_retention_days" {
  description = "Durée de rétention des logs CloudWatch (jours)"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "La rétention doit être une valeur standard CloudWatch."
  }
}

# ── TAGS PERSONNALISÉS ───────────────────────────────────────────────
variable "additional_tags" {
  description = "Tags supplémentaires à appliquer à toutes les ressources"
  type        = map(string)
  default     = {}
  
  # Exemple d'utilisation :
  # additional_tags = {
  #   CostCenter = "Engineering"
  #   Owner      = "John Doe"
  # }
}

# ── BASE DE DONNÉES (RDS) ────────────────────────────────────────────
variable "enable_rds" {
  description = "Créer une base de données RDS PostgreSQL"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Nom de la base de données"
  type        = string
  default     = "infoline"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Le nom de la DB doit commencer par une lettre et contenir uniquement des lettres, chiffres et underscores."
  }
}

variable "db_username" {
  description = "Nom d'utilisateur de la base de données"
  type        = string
  default     = "admin_infoline"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_username))
    error_message = "Le username doit commencer par une lettre."
  }
}

# ✅ AJOUTÉ : Variable manquante pour l'instance class RDS
variable "db_instance_class" {
  description = "Classe d'instance pour RDS"
  type        = string
  default     = "db.t3.micro"
  
  # Classes recommandées :
  # - Dev/Test : db.t3.micro (1 vCPU, 1 Go), db.t3.small (1 vCPU, 2 Go)
  # - Prod : db.t3.medium (2 vCPU, 4 Go), db.t3.large (2 vCPU, 8 Go)
  # - Haute perf : db.r6g.large (2 vCPU, 16 Go RAM optimisée)
}

variable "db_allocated_storage" {
  description = "Taille du stockage alloué (Go)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Le stockage doit être entre 20 Go et 65536 Go."
  }
}

variable "enable_kms_encryption" {
  description = "Utiliser une clé KMS personnalisée pour le chiffrement (coût supplémentaire ~1 USD/mois)"
  type        = bool
  default     = false
  
  # Note : RDS est chiffré par défaut avec storage_encrypted = true
  # Cette option ajoute une clé KMS personnalisée pour plus de contrôle
}
