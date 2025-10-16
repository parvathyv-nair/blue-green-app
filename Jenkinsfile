pipeline {
    // We use 'agent any' to run on the built-in executor, which has the 'minikube' CLI available.
    agent any

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
                    // Check if the blue deployment exists and has replicas. If so, deploy green next.
                    // We run kubectl commands directly using 'minikube kubectl --' to ensure it runs inside the Minikube environment.
                    def kubectl_prefix = "minikube kubectl -- "
                    
                    try {
                        // Check status.replicas of the blue deployment (only works if kubectl is available)
                        def status = sh(script: "${kubectl_prefix} get deployment ${BLUE_DEPLOYMENT} --ignore-not-found -o jsonpath='{.status.replicas}'", returnStdout: true).trim()
                        
                        if (status.toInteger() > 0) {
                            env.TARGET_COLOR = 'green'
                        } else {
                            env.TARGET_COLOR = 'blue'
                        }
                    } catch (e) {
                        // Fallback: This is Build #1, so we assume Blue.
                        if (env.BUILD_NUMBER.toInteger() == 1) {
                            env.TARGET_COLOR = 'blue'
                        } else {
                            // If build > 1 but kubectl check failed, assume green
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

        // --- STAGE 2: Build and Push Docker Image (Direct to Minikube Docker Daemon) ---
        stage('Build and Push Docker Image') {
            steps {
                script {
                    def full_image_tag = "${env.DOCKER_HUB_USER}/${env.APP_NAME}:${env.IMAGE_TAG}"
                    def color_image_tag = "${env.DOCKER_HUB_USER}/${env.APP_NAME}:${env.TARGET_COLOR}"
                    
                    // 1. Build the image directly inside the Minikube Docker daemon
                    // This command handles both build and ensuring the image is available in Minikube's internal registry.
                    echo "Building image in Minikube: ${full_image_tag}"
                    sh "minikube image build -t ${full_image_tag} ."
                    
                    // 2. Tag the image with the color
                    // Note: We run the following Docker commands locally after setting the environment
                    sh "eval \$(minikube docker-env)"
                    sh "docker tag ${full_image_tag} ${color_image_tag}"
                }
                
                // 3. Log in and push to Docker Hub (Required for public access/other environments, even if Minikube doesn't need it)
                withCredentials([usernamePassword(credentialsId: 'dockerhub-pass', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USERNAME')]) {
                    echo "Pushing images to Docker Hub..."
                    
                    // Fixes the shell redirection error by using sh/EOF block
                    sh """
                    docker login -u ${DOCKER_USERNAME} --password-stdin <<< ${DOCKER_PASSWORD}
                    docker push ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG}
                    docker push ${DOCKER_HUB_USER}/${APP_NAME}:${TARGET_COLOR}
                    """
                }
            }
        }

        // --- STAGE 3: Deploy New Version (Requires Kubectl) ---
        stage('Deploy New Version') {
            steps {
                script {
                    def kubectl_prefix = "minikube kubectl -- "
                    def current_deployment_file = "deployment-${env.TARGET_COLOR}.yaml" // Use the appropriate YAML file

                    if (env.TARGET_COLOR == 'blue') {
                        echo "Initial deployment of BLUE."
                        // Apply the blue deployment file
                        sh "${kubectl_prefix} apply -f deployment-blue.yaml"
                    } else {
                        // Deploy the green version by patching the blue deployment file
                        echo "Deploying ${env.TARGET_COLOR} deployment: ${env.TARGET_DEPLOYMENT}"
                        
                        // Use sed to create the green deployment YAML from the blue one on the fly and apply it
                        sh """
                        kubectl apply -f deployment-blue.yaml -o yaml --dry-run=client | \\
                        sed 's/${BLUE_DEPLOYMENT}/${GREEN_DEPLOYMENT}/g' | \\
                        sed 's/color: blue/color: green/g' | \\
                        ${kubectl_prefix} apply -f -
                        """
                        // Then set the image on the new deployment (this uses the color tag, which was just built/pushed)
                        sh "${kubectl_prefix} set image deployment/${env.TARGET_DEPLOYMENT} myapp=${DOCKER_HUB_USER}/${APP_NAME}:${env.TARGET_COLOR}"
                    }
                }
            }
        }
        
        stage('Wait for New Deployment Readiness') {
            steps {
                sh "minikube kubectl -- rollout status deployment/${env.TARGET_DEPLOYMENT}"
            }
        }

        // --- STAGE 4: Blue-Green Swap (Requires Kubectl) ---
        stage('Switch Service (Blue-Green Swap)') {
            steps {
                script {
                    def kubectl_prefix = "minikube kubectl -- "

                    // The service.yaml must be applied once to ensure the myapp-service exists
                    sh "${kubectl_prefix} apply -f service.yaml"
                    
                    // Only pause and switch if this is a deployment switch (i.e., not the very first run)
                    if (env.BUILD_NUMBER.toInteger() > 1 || env.TARGET_COLOR == 'green') {
                        // Manual approval step
                        timeout(time: 15, unit: 'MINUTES') {
                            input message: "Deploy ${env.TARGET_COLOR} is ready. Proceed with service switch?", ok: 'Proceed'
                        }
                        
                        // Patch the Service to point to the new color
                        echo "Patching service selector from ${env.OTHER_DEPLOYMENT} to ${env.TARGET_DEPLOYMENT} (${env.TARGET_COLOR})"
                        sh "${kubectl_prefix} patch service myapp-service -p '{\"spec\":{\"selector\":{\"color\":\"${env.TARGET_COLOR}\"}}}'"
                        echo "Service successfully switched to ${env.TARGET_COLOR}!"
                        
                        // Clean up the old deployment
                        echo "Cleaning up old deployment: ${env.OTHER_DEPLOYMENT}"
                        sh "${kubectl_prefix} delete deployment ${env.OTHER_DEPLOYMENT} --ignore-not-found"
                    } else {
                         echo "Initial deployment of BLUE completed. No switch required yet."
                    }
                }
            }
        }
    }
}
