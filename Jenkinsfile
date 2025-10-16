pipeline {
    // We use 'agent any' to run on the built-in executor, which has the 'minikube' CLI available.
    agent any

    environment {
        // We still define the user for naming convention, but the push step is removed for now.
        DOCKER_HUB_USER = 'parvathyv-nair'
        APP_NAME = 'myapp'
        BLUE_DEPLOYMENT = 'myapp-blue'
        GREEN_DEPLOYMENT = 'myapp-green'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        // Define the local Minikube tag name to use for deployment
        LOCAL_IMAGE_TAG = "${env.DOCKER_HUB_USER}/${env.APP_NAME}:${env.TARGET_COLOR}"
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
                    
                    // Update the image tag environment variable
                    env.LOCAL_IMAGE_TAG = "${env.DOCKER_HUB_USER}/${env.APP_NAME}:${env.TARGET_COLOR}"
                    
                    echo "Targeting deployment: ${env.TARGET_COLOR}"
                    echo "Using image tag: ${env.LOCAL_IMAGE_TAG}"
                }
            }
        }

        // --- STAGE 2: Build Image (Direct to Minikube Docker Daemon) ---
        stage('Build Image in Minikube') {
            steps {
                script {
                    // This command handles both building the image and ensuring it is available in Minikube's internal registry.
                    echo "Building image in Minikube using tag: ${env.LOCAL_IMAGE_TAG}"
                    sh "minikube image build -t ${env.LOCAL_IMAGE_TAG} ."
                    
                    // NOTE: Docker Hub push steps are removed for simplicity and to bypass Minikube execution issues.
                    // The image is now ready for deployment in the Minikube cluster.
                }
            }
        }

        // --- STAGE 3: Deploy New Version (Requires Kubectl) ---
        stage('Deploy New Version') {
            steps {
                script {
                    def kubectl_prefix = "minikube kubectl -- "

                    if (env.TARGET_COLOR == 'blue') {
                        echo "Initial deployment of BLUE."
                        // 1. Apply the service (needs to be done only once)
                        sh "${kubectl_prefix} apply -f service.yaml"
                        // 2. Apply the blue deployment file
                        sh "${kubectl_prefix} apply -f deployment-blue.yaml"
                        // 3. Set the image using the freshly built local tag
                        sh "${kubectl_prefix} set image deployment/${env.TARGET_DEPLOYMENT} myapp=${env.LOCAL_IMAGE_TAG}"
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
                        // Then set the image on the new deployment (this uses the color tag, which was just built)
                        sh "${kubectl_prefix} set image deployment/${env.TARGET_DEPLOYMENT} myapp=${env.LOCAL_IMAGE_TAG}"
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
                    
                    // The service.yaml is applied in the Deploy New Version stage now.
                    
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
