// ═══════════════════════════════════════════════════════════════════
// JENKINSFILE - CI/CD PIPELINE INFOLINE API (Java 17 + Spring Boot)
// ═══════════════════════════════════════════════════════════════════
// Ce pipeline automatise :
//   1. Build Maven (compilation + tests)
//   2. Analyse de code (SonarQube optionnel)
//   3. Build image Docker
//   4. Push vers Docker Hub
//   5. Déploiement sur Kubernetes (EKS)
//   6. Tests de santé post-déploiement
// ═══════════════════════════════════════════════════════════════════

pipeline {
    // ── AGENT ────────────────────────────────────────────────────────
    // Exécute le pipeline sur n'importe quel agent Jenkins disponible
    agent any

    // ── VARIABLES D'ENVIRONNEMENT ────────────────────────────────────
    environment {
        // Configuration de l'application
        APP_NAME = 'infoline-api'
        APP_VERSION = '1.0.0'
        
        // Java & Maven
        JAVA_HOME = '/usr/lib/jvm/java-17-openjdk-amd64'
        MAVEN_HOME = '/opt/maven'
        MAVEN_OPTS = '-Xmx1024m '
        
        // Docker
        DOCKER_IMAGE = "${APP_NAME}"
        DOCKER_REGISTRY = 'docker.io'  // Docker Hub
        DOCKER_REGISTRY_CREDENTIALS = 'dockerhub-credentials'  // ID dans Jenkins Credentials
        DOCKER_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(8)}"
        
        // Kubernetes
        K8S_NAMESPACE = 'infoline'
        K8S_DEPLOYMENT = "${APP_NAME}"
        KUBECONFIG_CREDENTIALS = 'kubeconfig-eks'  // ID dans Jenkins Credentials
        
        // AWS (si vous utilisez ECR au lieu de Docker Hub)
        AWS_REGION = 'eu-west-3'
        AWS_ACCOUNT_ID = credentials('aws-account-id')  // Optionnel
        
        // SonarQube (optionnel)
        SONAR_HOST_URL = 'http://sonarqube:9000'
        SONAR_PROJECT_KEY = 'infoline-api'
    }

    // ── OPTIONS DU PIPELINE ──────────────────────────────────────────
    options {
        // Conservation des builds : garde les 10 derniers
        buildDiscarder(logRotator(numToKeepStr: '10'))
        
        // Timeout global : annule le pipeline après 30 minutes
        timeout(time: 30, unit: 'MINUTES')
        
        // Empêche les builds concurrents du même job
        disableConcurrentBuilds()
        
        // Ajoute un timestamp à chaque ligne de log
        timestamps()
        
        // Active les couleurs ANSI dans les logs
        ansiColor('xterm')
    }

    // ── DÉCLENCHEURS (TRIGGERS) ──────────────────────────────────────
    triggers {
        // Poll SCM : vérifie Git toutes les 5 minutes
        // Déclenche un build si des changements sont détectés
        pollSCM('H/5 * * * *')
        
        // Ou utiliser webhook GitHub/GitLab (recommandé en prod)
        // githubPush()
    }

    // ══════════════════════════════════════════════════════════════════
    // STAGES DU PIPELINE
    // ══════════════════════════════════════════════════════════════════
    
    stages {
        
        // ──────────────────────────────────────────────────────────────
        // STAGE 1 : PRÉPARATION & CHECKOUT
        // ──────────────────────────────────────────────────────────────
        stage('🔄 Checkout Code') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "📦 Récupération du code depuis Git"
                    echo "═══════════════════════════════════════════"
                    
                    // Récupère le code depuis le repository Git configuré dans le job
                    checkout scm
                    
                    // Affiche les informations du commit
                    sh '''
                        echo "✅ Branch : ${GIT_BRANCH}"
                        echo "✅ Commit : ${GIT_COMMIT}"
                        git log -1 --pretty=format:"%h - %an : %s"
                    '''
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 2 : VÉRIFICATION DE L'ENVIRONNEMENT
        // ──────────────────────────────────────────────────────────────
        stage('🔍 Vérification Environnement') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🔍 Vérification des outils installés"
                    echo "═══════════════════════════════════════════"
                    
                    sh '''
                        echo "🔧 Vérification Java..."
                        java -version
                        echo ""
                        
                        echo "🔧 Vérification Maven..."
                        mvn -version
                        echo ""
                        
                        echo "🔧 Vérification Docker..."
                        docker --version
                        echo ""
                        
                        echo "🔧 Vérification kubectl..."
                        kubectl version --client
                        echo ""
                        
                        echo "📊 Espace disque disponible..."
                        df -h | grep -E '/$|/var'
                    '''
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 3 : BUILD MAVEN & TESTS UNITAIRES
        // ──────────────────────────────────────────────────────────────
        stage('🏗️  Maven Build & Test') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🏗️  Compilation et tests Maven"
                    echo "═══════════════════════════════════════════"
                    echo "🏗️ Déplacement dans le dossier du code et compilation..."
                    // On entre dans le dossier spécifique AVANT de lancer Maven
                    dir('springboot') {
                    // Nettoie les builds précédents et compile
                    sh 'mvn clean compile'}
                    
                    echo ""
                    echo "🧪 Exécution des tests unitaires..."
                    
                    // Exécute les tests avec rapport de couverture
                    sh '''
                        mvn test \
                            -Dmaven.test.failure.ignore=false \
                            -DfailIfNoTests=false
                    '''
                    
                    echo ""
                    echo "📦 Création du JAR exécutable..."
                    
                    // Package : crée le JAR sans re-exécuter les tests
                    sh 'mvn package -DskipTests'
                    
                    // Vérifie que le JAR a bien été créé
                    sh '''
                        echo "✅ Fichier JAR créé :"
                        ls -lh target/*.jar
                    '''
                }
            }
            
            // Publication des résultats de tests
            post {
                always {
                    // Publie les résultats des tests JUnit
                    junit testResults: '**/target/surefire-reports/*.xml', 
                          allowEmptyResults: true
                    
                    // Archive le JAR créé
                    archiveArtifacts artifacts: 'target/*.jar',
                                     fingerprint: true,
                                     allowEmptyArchive: false
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 4 : ANALYSE DE CODE (SONARQUBE - OPTIONNEL)
        // ──────────────────────────────────────────────────────────────
        stage('🔍 Analyse SonarQube') {
            when {
                // Exécute uniquement si SonarQube est configuré
                expression { return env.SONAR_HOST_URL != null }
            }
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🔍 Analyse de code avec SonarQube"
                    echo "═══════════════════════════════════════════"
                    
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                            mvn sonar:sonar \
                                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                                -Dsonar.host.url=${SONAR_HOST_URL}
                        '''
                    }
                    
                    // Attend le résultat du Quality Gate
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 5 : BUILD IMAGE DOCKER
        // ──────────────────────────────────────────────────────────────
        stage('🐳 Docker Build') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🐳 Construction de l'image Docker"
                    echo "═══════════════════════════════════════════"
                    
                    // Build de l'image avec tags multiple
                    sh """
                        docker build \
                            --build-arg VERSION=${APP_VERSION} \
                            --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                            --build-arg VCS_REF=${GIT_COMMIT} \
                            -t ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${DOCKER_TAG} \
                            -t ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:latest \
                            .
                    """
                    
                    echo ""
                    echo "✅ Image Docker créée :"
                    sh "docker images | grep ${DOCKER_IMAGE}"
                    
                    echo ""
                    echo "🔍 Inspection de l'image..."
                    sh """
                        docker inspect ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:latest | \
                        jq -r '.[0] | {
                            "Size": (.Size / 1024 / 1024 | tostring + " MB"),
                            "Created": .Created,
                            "Architecture": .Architecture,
                            "Os": .Os
                        }'
                    """
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 6 : SCAN DE SÉCURITÉ (TRIVY - OPTIONNEL)
        // ──────────────────────────────────────────────────────────────
        stage('🔒 Security Scan') {
            when {
                // Exécute uniquement en production ou si activé
                expression { return env.BRANCH_NAME == 'main' }
            }
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🔒 Scan de sécurité de l'image Docker"
                    echo "═══════════════════════════════════════════"
                    
                    // Scan avec Trivy (scanner de vulnérabilités)
                    sh """
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --exit-code 0 \
                            --no-progress \
                            ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${DOCKER_TAG}
                    """
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 7 : PUSH VERS DOCKER REGISTRY
        // ──────────────────────────────────────────────────────────────
        stage('📤 Docker Push') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "📤 Publication de l'image vers Docker Hub"
                    echo "═══════════════════════════════════════════"
                    
                    // Login Docker Hub avec credentials Jenkins
                    withCredentials([usernamePassword(
                        credentialsId: "${DOCKER_REGISTRY_CREDENTIALS}",
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh '''
                            echo "🔐 Login Docker Hub..."
                            echo $DOCKER_PASS | docker login ${DOCKER_REGISTRY} \
                                --username $DOCKER_USER \
                                --password-stdin
                        '''
                    }
                    
                    // Push des images avec les deux tags
                    sh """
                        echo ""
                        echo "⬆️  Push de l'image avec tag ${DOCKER_TAG}..."
                        docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${DOCKER_TAG}
                        
                        echo ""
                        echo "⬆️  Push de l'image avec tag latest..."
                        docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:latest
                    """
                    
                    echo ""
                    echo "✅ Images publiées :"
                    echo "   - ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${DOCKER_TAG}"
                    echo "   - ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:latest"
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 8 : DÉPLOIEMENT SUR KUBERNETES
        // ──────────────────────────────────────────────────────────────
        stage('☸️  Deploy to Kubernetes') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "☸️  Déploiement sur Kubernetes (EKS)"
                    echo "═══════════════════════════════════════════"
                    
                    // Configure kubectl avec kubeconfig depuis Jenkins Credentials
                    withCredentials([file(
                        credentialsId: "${KUBECONFIG_CREDENTIALS}",
                        variable: 'KUBECONFIG_FILE'
                    )]) {
                        sh '''
                            # Créer le répertoire .kube si inexistant
                            mkdir -p ~/.kube
                            
                            # Copier le kubeconfig
                            cp $KUBECONFIG_FILE ~/.kube/config
                            chmod 600 ~/.kube/config
                            
                            echo "✅ kubectl configuré"
                            kubectl version --short
                        '''
                    }
                    
                    // Créer le namespace s'il n'existe pas
                    sh """
                        echo ""
                        echo "📦 Vérification du namespace ${K8S_NAMESPACE}..."
                        kubectl get namespace ${K8S_NAMESPACE} || \
                        kubectl create namespace ${K8S_NAMESPACE}
                    """
                    
                    // Remplacer le tag de l'image dans le deployment
                    sh """
                        echo ""
                        echo "🔄 Mise à jour du deployment..."
                        
                        # Remplace IMAGE_TAG dans deployment.yaml
                        sed -i 's|IMAGE_TAG|${DOCKER_TAG}|g' k8s/deployment.yaml
                        
                        # Remplace REGISTRY dans deployment.yaml
                        sed -i 's|REGISTRY|${DOCKER_REGISTRY}|g' k8s/deployment.yaml
                    """
                    
                    // Appliquer les manifestes Kubernetes
                    sh """
                        echo ""
                        echo "⚙️  Application des manifestes K8s..."
                        kubectl apply -f k8s/ -n ${K8S_NAMESPACE}
                    """
                    
                    // Attendre que le rollout soit terminé
                    sh """
                        echo ""
                        echo "⏳ Attente du rollout (timeout 3 minutes)..."
                        kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                            -n ${K8S_NAMESPACE} \
                            --timeout=180s
                    """
                    
                    // Afficher l'état du déploiement
                    sh """
                        echo ""
                        echo "📊 État du déploiement :"
                        kubectl get deployment ${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE}
                        
                        echo ""
                        echo "📊 Pods en cours d'exécution :"
                        kubectl get pods -l app=${APP_NAME} -n ${K8S_NAMESPACE}
                        
                        echo ""
                        echo "📊 Services exposés :"
                        kubectl get svc ${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE}
                    """
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 9 : TESTS DE SANTÉ POST-DÉPLOIEMENT
        // ──────────────────────────────────────────────────────────────
        stage('🏥 Health Check') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🏥 Tests de santé de l'application"
                    echo "═══════════════════════════════════════════"
                    
                    // Récupérer l'URL du LoadBalancer
                    def serviceUrl = sh(
                        script: """
                            kubectl get svc ${K8S_DEPLOYMENT} \
                                -n ${K8S_NAMESPACE} \
                                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || \
                            kubectl get svc ${K8S_DEPLOYMENT} \
                                -n ${K8S_NAMESPACE} \
                                -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
                        """,
                        returnStdout: true
                    ).trim()
                    
                    if (serviceUrl) {
                        echo "🌐 URL du service : http://${serviceUrl}"
                        
                        // Attendre que le LoadBalancer soit prêt
                        echo "⏳ Attente du LoadBalancer (30 secondes)..."
                        sleep(30)
                        
                        // Test du endpoint /health
                        retry(5) {
                            sh """
                                echo ""
                                echo "🔍 Test du endpoint /api/v1/health..."
                                curl -f -s -o /dev/null -w "%{http_code}" \
                                    http://${serviceUrl}/api/v1/health || exit 1
                                
                                echo ""
                                echo "✅ Application accessible et en bonne santé !"
                            """
                        }
                    } else {
                        echo "⚠️  LoadBalancer non disponible immédiatement"
                        echo "   Utilisez: kubectl get svc -n ${K8S_NAMESPACE}"
                    }
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 10 : NETTOYAGE
        // ──────────────────────────────────────────────────────────────
        stage('🧹 Cleanup') {
            steps {
                script {
                    echo "═══════════════════════════════════════════"
                    echo "🧹 Nettoyage des ressources temporaires"
                    echo "═══════════════════════════════════════════"
                    
                    sh '''
                        # Supprimer les images Docker locales (garde latest)
                        docker image prune -f
                        
                        # Supprimer les conteneurs arrêtés
                        docker container prune -f
                        
                        echo "✅ Nettoyage terminé"
                    '''
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // POST-ACTIONS (après tous les stages)
    // ══════════════════════════════════════════════════════════════════
    
    post {
        // Toujours exécuté (succès ou échec)
        always {
            echo "═══════════════════════════════════════════"
            echo "📊 FIN DU PIPELINE"
            echo "═══════════════════════════════════════════"
            
            // Nettoie le workspace Jenkins
            cleanWs()
        }
        
        // Exécuté uniquement en cas de succès
        success {
            echo "✅ PIPELINE RÉUSSI !"
            echo "🚀 Application déployée avec succès"
            echo "📦 Image : ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${DOCKER_TAG}"
            
            // Notification Slack (optionnel)
            // slackSend(
            //     color: 'good',
            //     message: "✅ Déploiement réussi : ${env.JOB_NAME} #${env.BUILD_NUMBER}"
            // )
        }
        
        // Exécuté uniquement en cas d'échec
        failure {
            echo "❌ PIPELINE ÉCHOUÉ !"
            echo "Consultez les logs pour plus de détails"
            
            // Notification Slack (optionnel)
            // slackSend(
            //     color: 'danger',
            //     message: "❌ Déploiement échoué : ${env.JOB_NAME} #${env.BUILD_NUMBER}"
            // )
        }
        
        // Exécuté si le pipeline est instable
        unstable {
            echo "⚠️  PIPELINE INSTABLE"
            echo "Certains tests ont échoué mais le build continue"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// NOTES & RECOMMANDATIONS
// ═══════════════════════════════════════════════════════════════════
//
// 📋 PRÉREQUIS :
//   - Jenkins installé avec plugins : Docker, Kubernetes CLI, Git
//   - Credentials configurés dans Jenkins :
//     * dockerhub-credentials (username/password)
//     * kubeconfig-eks (fichier kubeconfig)
//   - Java 17, Maven, Docker, kubectl installés sur l'agent Jenkins
//
// 🔐 SECRETS À CONFIGURER DANS JENKINS :
//   1. dockerhub-credentials : Username/Password Docker Hub
//   2. kubeconfig-eks : Fichier kubeconfig pour EKS
//   3. aws-account-id : (optionnel) Si vous utilisez ECR
//
// 🚀 OPTIMISATIONS POSSIBLES :
//   - Utiliser des agents Docker pour chaque stage
//   - Mettre en cache les dépendances Maven
//   - Paralléliser les tests
//   - Ajouter des tests d'intégration
//   - Mettre en place un rollback automatique en cas d'échec
//
// 📊 MONITORING :
//   - Logs Jenkins : Console Output
//   - Kubernetes : kubectl logs -f deployment/${K8S_DEPLOYMENT}
//   - Métriques : Prometheus + Grafana (optionnel)
//
// ═══════════════════════════════════════════════════════════════════
