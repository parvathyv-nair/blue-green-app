pipeline {
    // The main node will run the cleanup/setup commands, but the core stages use dedicated agents.
    agent any // Changed from 'master' to 'any' to run on the default executor

    environment {
        // Replace with your Docker Hub username
        DOCKER_HUB_USER = 'parvathyv-nair'
        APP_NAME = 'myapp'
        BLUE_DEPLOYMENT = 'myapp-blue'
        GREEN_DEPLOYMENT = 'myapp-green'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Clone Repository') {
            steps {
                // Ensure all files are cloned into the workspace
                checkout scm
            }
        }

        // --- STAGE 1: Determine Color (Requires Kubectl) ---
        stage('Determine Target Color') {
            steps {
                script {
                    // This logic must run where kubectl is available. 
                    // Since we can't easily install kubectl on the default agent, 
                    // we will assume Blue is initial, and Green is subsequent.
                    
                    // Simple logic for Minikube/Kubernetes: Check if the blue deployment exists.
                    // If it exists and is running, we deploy green next. Otherwise, deploy blue.
                    
                    // Note: If this fails, we fall back to a safer default (blue on first run)
                    try {
                        def status = sh(script: "kubectl get deployment ${BLUE_DEPLOYMENT} --ignore-not-found -o custom-columns=STATUS:.status.replicas", returnStatus: true)
                        
                        if (status == 0) {
                            env.TARGET_COLOR = 'green'
                        } else {
                            env.TARGET_COLOR = 'blue'
                        }
                    } catch (e) {
                        // Fallback: This is Build #1, so we assume Blue.
                        if (env.BUILD_NUMBER.toInteger() == 1) {
                            env.TARGET_COLOR = 'blue'
                        } else {
                            // If build > 1 but kubectl check failed, assume green for rollback/next deploy
                            env.TARGET_COLOR = 'green'
                        }
                    }
                    
                    // Finalize environment variables based on target color
                    if (env.TARGET_COLOR == 'blue') {
                        env.TARGET_DEPLOYMENT = env.BLUE_DEPLOYMENT
                        env.OTHER_DEPLOYMENT = env.GREEN_DEPLOYMENT
                    } else {
                        env.TARGET_DEPLOYMENT = env.GREEN_DEPLOYMENT
                        env.OTHER_DEPLOYMENT = env.BLUE_DEPLOYMENT
                    }
                    echo "Targeting deployment: ${env.TARGET_COLOR}"
                }
            }
        }

        // --- STAGE 2: Build and Push Docker Image (Requires Docker/Kaniko) ---
        stage('Build & Push Docker Image') {
            steps {
                // This fix uses the assumption that the main Jenkins Pod has access to Docker via D-i-D setup
                withCredentials([usernamePassword(credentialsId: 'dockerhub-pass', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USERNAME')]) {
                    sh "docker login -u ${DOCKER_HUB_USER} --password-stdin <<< ${DOCKER_PASSWORD}"
                    
                    // Build the image using the current BUILD_NUMBER as the tag
                    sh "docker build -t ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG} ."
                    sh "docker tag ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG} ${DOCKER_HUB_USER}/${APP_NAME}:${env.TARGET_COLOR}"
                    
                    // Push both the numbered tag and the color tag
                    sh "docker push ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG}"
                    sh "docker push ${DOCKER_HUB_USER}/${APP_NAME}:${env.TARGET_COLOR}"
                }
            }
        }

        // --- STAGE 3: Deploy New Version (Requires Kubectl) ---
        stage('Deploy New Version') {
            steps {
                script {
                    // Initial deployment uses the deployment-blue.yaml
                    if (env.TARGET_COLOR == 'blue') {
                        echo "Initial deployment of BLUE."
                        sh "kubectl apply -f deployment-blue.yaml"
                    } else {
                        // Deploy the green version by patching the blue deployment file
                        echo "Deploying ${env.TARGET_COLOR} deployment: ${env.TARGET_DEPLOYMENT}"
                        
                        // Use sed to replace BLUE attributes with GREEN attributes for deployment creation
                        sh """
                        kubectl apply -f deployment-blue.yaml -o yaml --dry-run=client | \
                        sed 's/${BLUE_DEPLOYMENT}/${GREEN_DEPLOYMENT}/g' | \
                        sed 's/color: blue/color: green/g' | \
                        kubectl apply -f -
                        """
                        // Then set the image on the new deployment to the newly pushed GREEN image
                        sh "kubectl set image deployment/${env.TARGET_DEPLOYMENT} myapp=${DOCKER_HUB_USER}/${APP_NAME}:${env.TARGET_COLOR}"
                    }
                }
            }
        }
        
        stage('Wait for New Deployment Readiness') {
            steps {
                sh "kubectl rollout status deployment/${env.TARGET_DEPLOYMENT}"
            }
        }

        // --- STAGE 4: Blue-Green Swap (Requires Kubectl) ---
        stage('Switch Service (Blue-Green Swap)') {
            steps {
                script {
                    // The service.yaml must be applied once to ensure the myapp-service exists
                    sh "kubectl apply -f service.yaml"
                    
                    // Only pause and switch if this is a deployment switch (i.e., not the very first run)
                    if (env.BUILD_NUMBER.toInteger() > 1 || env.TARGET_COLOR == 'green') {
                        // Manual approval step
                        timeout(time: 15, unit: 'MINUTES') {
                            input message: "Deploy ${env.TARGET_COLOR} is ready. Proceed with service switch?", ok: 'Proceed'
                        }
                        
                        // Patch the Service to point to the new color
                        echo "Patching service selector from ${env.OTHER_DEPLOYMENT} to ${env.TARGET_DEPLOYMENT} (${env.TARGET_COLOR})"
                        sh "kubectl patch service myapp-service -p '{\"spec\":{\"selector\":{\"color\":\"${env.TARGET_COLOR}\"}}}'"
                        echo "Service successfully switched to ${env.TARGET_COLOR}!"
                        
                        // Clean up the old deployment
                        echo "Cleaning up old deployment: ${env.OTHER_DEPLOYMENT}"
                        sh "kubectl delete deployment ${env.OTHER_DEPLOYMENT} --ignore-not-found"
                    } else {
                         echo "Initial deployment of BLUE completed. No switch required yet."
                    }
                }
            }
        }
    }
}
