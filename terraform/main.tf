# ═══════════════════════════════════════════════════════════════════
# INFOLINE - INFRASTRUCTURE AS CODE (TERRAFORM) - VERSION CORRIGÉE
# ═══════════════════════════════════════════════════════════════════
# Provisioning :
#   - Cluster Kubernetes (EKS) avec worker nodes
#   - Service Serverless (Lambda + API Gateway)
#   - Réseau (VPC, Subnets publics/privés, Internet Gateway)
#   - Base de données RDS PostgreSQL (optionnel via enable_rds)
# 
# ═══════════════════════════════════════════════════════════════════

# ── CONFIGURATION TERRAFORM ──────────────────────────────────────────
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {  # Génération du mot de passe RDS
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ── PROVIDER AWS ─────────────────────────────────────────────────────
provider "aws" {
  region = var.region
  
  default_tags {
    tags = local.common_tags
  }
}

# ── TAGS COMMUNS ─────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = "InfoLine"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "Team-DevOps"
  }
  
  # Liste des zones de disponibilité pour éviter les références dupliquées
  availability_zones = data.aws_availability_zones.available.names
}

# ── DONNÉES : ZONES DE DISPONIBILITÉ ─────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 1 : RÉSEAU (VPC, SUBNETS, INTERNET GATEWAY)
# ═══════════════════════════════════════════════════════════════════

# ── VPC PRINCIPAL ────────────────────────────────────────────────────
# OBJECTIF : Réseau privé isolé pour toute l'infrastructure InfoLine
# CIDR : 10.0.0.0/16 (65,536 IPs disponibles)
resource "aws_vpc" "infoline_vpc" {
  cidr_block           = var.vpc_cidr  
  enable_dns_hostnames = true  # Requis pour EKS
  enable_dns_support   = true  # Requis pour EKS

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ── SUBNETS PUBLICS ──────────────────────────────────────────────────
# OBJECTIF : Héberger les worker nodes EKS et les LoadBalancers publics
# CIDR : 10.0.1.0/24 (AZ-1) et 10.0.2.0/24 (AZ-2)
# IPs disponibles : ~250 par subnet
resource "aws_subnet" "public" {
  count = var.public_subnet_count  #  Utilisation de variable

  vpc_id                  = aws_vpc.infoline_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = local.availability_zones[count.index]  #  Utilise local
  map_public_ip_on_launch = true  # Nécessaire pour que les instances reçoivent des IPs publiques

  tags = {
    Name                                        = "${var.project_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb"                    = "1"  # Tag requis pour que EKS puisse créer des LoadBalancers
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"  # Tag requis pour EKS
  }
}

# ── INTERNET GATEWAY ─────────────────────────────────────────────────
# OBJECTIF : Permettre l'accès Internet aux ressources dans les subnets publics
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.infoline_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ── TABLE DE ROUTAGE PUBLIQUE ────────────────────────────────────────
# OBJECTIF : Router tout le trafic 0.0.0.0/0 vers l'Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.infoline_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# ── ASSOCIATION SUBNETS <-> TABLE DE ROUTAGE ─────────────────────────
resource "aws_route_table_association" "public" {
  count = var.public_subnet_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 2 : KUBERNETES (EKS)
# ═══════════════════════════════════════════════════════════════════

# ── SECURITY GROUP POUR LE CLUSTER EKS ───────────────────────────────
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group pour le cluster EKS InfoLine"
  vpc_id      = aws_vpc.infoline_vpc.id

  egress {
    description = "Autoriser tout le trafic sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}

# ── RÔLE IAM POUR LE CLUSTER EKS ─────────────────────────────────────
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-eks-cluster-role"
  }
}

# ── POLICIES : PERMISSIONS DU CLUSTER ────────────────────────────────
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# ── CLUSTER EKS ──────────────────────────────────────────────────────
resource "aws_eks_cluster" "infoline" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version  

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = true   # API accessible depuis Internet (dev/test)
    endpoint_private_access = true   # API accessible depuis le VPC
  }

  # S'assurer que les rôles IAM sont créés avant le cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = {
    Name = var.cluster_name
  }
}

# ── RÔLE IAM POUR LES WORKER NODES ───────────────────────────────────
resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"  # IMPORTANT : ec2.amazonaws.com (pas eks.amazonaws.com)
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-eks-node-role"
  }
}

# ── POLICIES : PERMISSIONS DES WORKER NODES ──────────────────────────
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# ── NODE GROUP (WORKER NODES) ────────────────────────────────────────
resource "aws_eks_node_group" "infoline_nodes" {
  cluster_name    = aws_eks_cluster.infoline.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id

  # Configuration de scalabilité automatique
  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Type et taille des instances EC2
  instance_types = [var.node_instance_type]
  disk_size      = var.node_disk_size

  # Stratégie de mise à jour (rolling update)
  update_config {
    max_unavailable = 1  # Maximum 1 node indisponible pendant une mise à jour
  }

  # S'assurer que les permissions sont en place avant de créer les nodes
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]

  tags = {
    Name = "${var.project_name}-worker-nodes"
  }
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 3 : SERVERLESS (LAMBDA + API GATEWAY)
# ═══════════════════════════════════════════════════════════════════

# ── RÔLE IAM POUR LA LAMBDA ──────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# ── POLICY : PERMISSIONS CLOUDWATCH LOGS ─────────────────────────────
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# ── CODE LAMBDA TEMPORAIRE (Hello World) ─────────────────────────────
# NOTE : Remplacez par votre code Java/TypeScript de production
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_payload.zip"

  source {
    content = <<-EOT
      exports.handler = async (event) => {
        console.log('Event:', JSON.stringify(event));
        
        // Exemple de réponse pour un service d'authentification
        return {
          statusCode: 200,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'  // CORS pour le frontend
          },
          body: JSON.stringify({
            message: 'InfoLine Auth Service - Hello World!',
            timestamp: new Date().toISOString(),
            environment: '${var.environment}'
          })
        };
      };
    EOT
    filename = "index.js"
  }
}

# ── FONCTION LAMBDA ──────────────────────────────────────────────────
resource "aws_lambda_function" "infoline_auth" {
  function_name = var.lambda_function_name
  description   = "Service d'authentification pour InfoLine (users/admin)"
  role          = aws_iam_role.lambda_role.arn

  # Code source
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Runtime
  runtime = var.lambda_runtime
  handler = var.lambda_handler

  # Configuration
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Variables d'environnement
  environment {
    variables = {
      ENVIRONMENT = var.environment
      # Décommentez et complétez quand RDS est activé :
      # DB_HOST     = var.enable_rds ? aws_db_instance.infoline_db[0].address : ""
      # DB_PORT     = "5432"
      # DB_NAME     = var.db_name
    }
  }

  tags = {
    Name = "${var.project_name}-auth-lambda"
  }
}

# ── CLOUDWATCH LOG GROUP POUR LA LAMBDA ──────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.infoline_auth.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-lambda-logs"
  }
}

# ── API GATEWAY (HTTP API v2) ────────────────────────────────────────
resource "aws_apigatewayv2_api" "infoline_api" {
  name          = "${var.project_name}-auth-api"
  protocol_type = "HTTP"
  description   = "API Gateway pour le service d'authentification InfoLine"

  cors_configuration {
    allow_origins = ["*"]  #  En production, restreindre aux domaines autorisés
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = {
    Name = "${var.project_name}-auth-api"
  }
}

# ── INTÉGRATION : API GATEWAY → LAMBDA ───────────────────────────────
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id = aws_apigatewayv2_api.infoline_api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.infoline_auth.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# ── ROUTE : POST /login ──────────────────────────────────────────────
resource "aws_apigatewayv2_route" "login_route" {
  api_id    = aws_apigatewayv2_api.infoline_api.id
  route_key = "POST /login"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# ── ROUTE : GET / (health check) ─────────────────────────────────────
resource "aws_apigatewayv2_route" "root_route" {
  api_id    = aws_apigatewayv2_api.infoline_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# ── STAGE DE DÉPLOIEMENT ─────────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.infoline_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

# ── LOG GROUP POUR API GATEWAY ───────────────────────────────────────
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.infoline_api.name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

# ── PERMISSION : API GATEWAY PEUT INVOQUER LA LAMBDA ─────────────────
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.infoline_auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.infoline_api.execution_arn}/*/*"
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 4 : BASE DE DONNÉES RDS POSTGRESQL 
# ═══════════════════════════════════════════════════════════════════
# NOTE : Activé/désactivé via var.enable_rds dans terraform.tfvars

# ── SUBNETS PRIVÉS POUR RDS ──────────────────────────────────────────
# BONNE PRATIQUE : Les bases de données doivent TOUJOURS être en privé
# CIDR : 10.0.10.0/24 (AZ-1) et 10.0.11.0/24 (AZ-2)
resource "aws_subnet" "private" {
  count = var.enable_rds ? 2 : 0

  vpc_id                  = aws_vpc.infoline_vpc.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = local.availability_zones[count.index]  
  map_public_ip_on_launch = false  # IMPORTANT : jamais d'IP publique

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Tier = "Database"
  }
}

# ── DB SUBNET GROUP ──────────────────────────────────────────────────
resource "aws_db_subnet_group" "infoline_db" {
  count = var.enable_rds ? 1 : 0

  name        = "${var.project_name}-db-subnet-group"
  description = "Subnet group pour RDS PostgreSQL InfoLine"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnets"
  }
}

# ── SECURITY GROUP POUR RDS ──────────────────────────────────────────
resource "aws_security_group" "rds_sg" {
  count = var.enable_rds ? 1 : 0

  name        = "${var.project_name}-rds-sg"
  description = "Security group pour RDS PostgreSQL - acces depuis le VPC uniquement"
  vpc_id      = aws_vpc.infoline_vpc.id

  # Ingress : PostgreSQL depuis le VPC
  ingress {
    description = "PostgreSQL depuis le VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # Utilise la variable
  }

  # Ingress : PostgreSQL depuis les pods Kubernetes
  ingress {
    description     = "PostgreSQL depuis les pods K8s"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Egress : Tout le trafic sortant
  egress {
    description = "Tout le trafic sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# ── RANDOM PASSWORD SÉCURISÉ ─────────────────────────────────────────
# Génère un mot de passe aléatoire de 16 caractères
resource "random_password" "db_password" {
  count = var.enable_rds ? 1 : 0

  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── STOCKAGE SÉCURISÉ DU MOT DE PASSE (AWS SECRETS MANAGER) ─────────
resource "aws_secretsmanager_secret" "db_password" {
  count = var.enable_rds ? 1 : 0

  name        = "${var.project_name}/database/password"
  description = "Mot de passe de la base de données PostgreSQL InfoLine"

  tags = {
    Name = "${var.project_name}-db-password"
  }
}

#  Version initiale sans l'host (évite la dépendance circulaire)
resource "aws_secretsmanager_secret_version" "db_password_initial" {
  count = var.enable_rds ? 1 : 0

  secret_id = aws_secretsmanager_secret.db_password[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password[0].result
    engine   = "postgres"
    port     = 5432
    dbname   = var.db_name
  })

  lifecycle {
    ignore_changes = [secret_string]  # Sera mis à jour après création de la DB
  }
}

# ── INSTANCE RDS POSTGRESQL ──────────────────────────────────────────
resource "aws_db_instance" "infoline_db" {
  count = var.enable_rds ? 1 : 0

  # Identification
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "15.8"

  # Ressources
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"  # gp3 plus performant et moins cher que gp2
  iops              = 3000

  # Configuration de la base
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password[0].result

  # Réseau
  db_subnet_group_name   = aws_db_subnet_group.infoline_db[0].name
  vpc_security_group_ids = [aws_security_group.rds_sg[0].id]
  publicly_accessible    = false

  # Haute disponibilité
  multi_az = var.environment == "prod" ? true : false

  # Backups
  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Chiffrement
  storage_encrypted = true
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.rds[0].arn : null

  # Snapshots
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-db-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = var.environment == "prod" ? 60 : 0
  monitoring_role_arn             = var.environment == "prod" ? aws_iam_role.rds_monitoring[0].arn : null

  # Performance Insights
  performance_insights_enabled          = var.environment == "prod" ? true : false
  performance_insights_retention_period = var.environment == "prod" ? 7 : null

  # Mises à jour
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  # Protection
  deletion_protection = var.environment == "prod" ? true : false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.infoline_postgres[0].name

  tags = {
    Name        = "${var.project_name}-postgresql"
    Environment = var.environment
  }

  depends_on = [random_password.db_password]
}

# Version complète avec l'host (après création de la DB)
resource "aws_secretsmanager_secret_version" "db_password_complete" {
  count = var.enable_rds ? 1 : 0

  secret_id = aws_secretsmanager_secret.db_password[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password[0].result
    engine   = "postgres"
    host     = aws_db_instance.infoline_db[0].address
    port     = 5432
    dbname   = var.db_name
  })

  depends_on = [
    aws_db_instance.infoline_db,
    aws_secretsmanager_secret_version.db_password_initial
  ]
}

# ── PARAMETER GROUP POSTGRESQL ───────────────────────────────────────
resource "aws_db_parameter_group" "infoline_postgres" {
  count = var.enable_rds ? 1 : 0

  name        = "${var.project_name}-postgres15-params"
  family      = "postgres15"
  description = "Paramètres optimisés pour PostgreSQL 15 - InfoLine"

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/10240}"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "max_connections"
    value = "100"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "work_mem"
    value = "4096"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-postgres-params"
  }
}

# ── KMS KEY  ──────────────────────────────────────────────
resource "aws_kms_key" "rds" {
  count = var.enable_rds && var.enable_kms_encryption ? 1 : 0

  description             = "Clé KMS pour le chiffrement RDS InfoLine"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-rds-kms-key"
  }
}

resource "aws_kms_alias" "rds" {
  count = var.enable_rds && var.enable_kms_encryption ? 1 : 0

  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

# ── IAM ROLE POUR ENHANCED MONITORING (PROD) ─────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  count = var.enable_rds && var.environment == "prod" ? 1 : 0

  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.enable_rds && var.environment == "prod" ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ═══════════════════════════════════════════════════════════════════
# OUTPUTS
# ═══════════════════════════════════════════════════════════════════

# ── GÉNÉRAL ──────────────────────────────────────────────────────────
output "region" {
  description = "Région AWS utilisée"
  value       = var.region
}

output "vpc_id" {
  description = "ID du VPC créé"
  value       = aws_vpc.infoline_vpc.id
}

# ── KUBERNETES ───────────────────────────────────────────────────────
output "cluster_name" {
  description = "Nom du cluster EKS"
  value       = aws_eks_cluster.infoline.name
}

output "cluster_endpoint" {
  description = "Endpoint de l'API Kubernetes"
  value       = aws_eks_cluster.infoline.endpoint
}

output "cluster_security_group_id" {
  description = "Security group du cluster EKS"
  value       = aws_security_group.eks_cluster.id
}

output "configure_kubectl" {
  description = "Commande pour configurer kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.infoline.name}"
}

# ── LAMBDA & API GATEWAY ─────────────────────────────────────────────
output "lambda_function_name" {
  description = "Nom de la fonction Lambda"
  value       = aws_lambda_function.infoline_auth.function_name
}

output "lambda_function_arn" {
  description = "ARN de la fonction Lambda"
  value       = aws_lambda_function.infoline_auth.arn
}

output "api_gateway_url" {
  description = "URL de l'API Gateway (service d'authentification)"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_gateway_endpoints" {
  description = "Endpoints disponibles"
  value = {
    health_check = "${aws_apigatewayv2_stage.default.invoke_url}/"
    login        = "${aws_apigatewayv2_stage.default.invoke_url}/login"
  }
}

# ── RDS ──────────────────────────────────────────────────────────────
output "database_endpoint" {
  description = "Endpoint de connexion à la base de données"
  value       = var.enable_rds ? aws_db_instance.infoline_db[0].endpoint : null
}

output "database_name" {
  description = "Nom de la base de données"
  value       = var.enable_rds ? aws_db_instance.infoline_db[0].db_name : null
}

output "database_username" {
  description = "Nom d'utilisateur de la base"
  value       = var.enable_rds ? var.db_username : null
  sensitive   = true
}

output "database_password_secret_arn" {
  description = "ARN du secret contenant le mot de passe (AWS Secrets Manager)"
  value       = var.enable_rds ? aws_secretsmanager_secret.db_password[0].arn : null
}

output "database_connection_string" {
  description = "Commande pour se connecter à la base (psql)"
  value       = var.enable_rds ? "psql -h ${aws_db_instance.infoline_db[0].address} -U ${var.db_username} -d ${var.db_name}" : null
  sensitive   = true
}

# ── INSTRUCTIONS POST-DÉPLOIEMENT ────────────────────────────────────
output "next_steps" {
  description = "Prochaines étapes après le déploiement"
  value = <<-EOT
    
    ✅ Infrastructure provisionnée avec succès !
    
    📋 PROCHAINES ÉTAPES :
    
    1️⃣  CONFIGURER KUBECTL :
       ${format("aws eks update-kubeconfig --region %s --name %s", var.region, aws_eks_cluster.infoline.name)}
    
    2️⃣  VÉRIFIER LE CLUSTER :
       kubectl get nodes
       kubectl get pods --all-namespaces
    
    3️⃣  TESTER L'API GATEWAY :
       curl ${aws_apigatewayv2_stage.default.invoke_url}/
       curl -X POST ${aws_apigatewayv2_stage.default.invoke_url}/login
    
    4️⃣  DÉPLOYER VOTRE APPLICATION :
       kubectl apply -f k8s/deployment.yaml
    
    📊 MONITORING :
       - Lambda logs : CloudWatch → /aws/lambda/${aws_lambda_function.infoline_auth.function_name}
       - API Gateway logs : CloudWatch → /aws/apigateway/${aws_apigatewayv2_api.infoline_api.name}
       ${var.enable_rds ? "- RDS logs : CloudWatch → /aws/rds/instance/${var.project_name}-db/postgresql" : ""}
    
    ${var.enable_rds ? "🗄️  BASE DE DONNÉES :\n       - Endpoint : ${aws_db_instance.infoline_db[0].address}\n       - Récupérer le mot de passe : aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db_password[0].arn}" : ""}
    
  EOT
}
