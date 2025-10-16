pipeline {
    // We use 'agent any' as the base, but execute Kubernetes/Docker commands inside containers.
    agent any

    environment {
        // We still define the user for naming convention
        DOCKER_HUB_USER = 'parvathyv-nair'
        APP_NAME = 'myapp'
        BLUE_DEPLOYMENT = 'myapp-blue'
        GREEN_DEPLOYMENT = 'myapp-green'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        // Define the local tag name
        LOCAL_IMAGE_TAG = "${env.DOCKER_HUB_USER}/${env.APP_NAME}:${env.TARGET_COLOR}"
        
        // --- NEW: K8s Execution Prefix ---
        // This command runs the Kubernetes CLI inside the Minikube environment.
        // We MUST use the Minikube context (minikube kubectl --) and we'll ensure that Minikube is available 
        // by making a wrapper script. Since minikube is not found, we revert to wrapping with 'docker run'.
        // However, given the environment limitations, the ONLY way forward is to assume Minikube/Kubectl
        // is being installed just-in-time OR we use a full Docker agent.
        // Let's go with the Docker agent approach for the commands, which is the standard fix for "not found" errors.
        
        // This uses a Docker image to run kubectl commands, assuming Minikube is already running 
        // and the Kubeconfig file is mounted/available (which is the main complexity here).
        // Since we can't mount the Minikube context, we have to assume a dedicated build agent.
        // However, since we cannot change the Jenkins environment setup, we'll try to use the most common fix 
        // for 'minikube not found' in restricted Jenkins environments: running all logic in one big shell script 
        // that handles the setup or assuming it's an external step.
        // Since we are limited to shell scripts, we must try to assume the presence of the full toolchain.
        
        // Let's modify the execution to ensure environment variables are evaluated correctly.
    }

    stages {
        stage('Clone Repository') {
            steps {
                checkout scm
            }
        }

        // --- STAGE 1: Determine Color (Requires Kubectl) ---
        stage('Determine Target Color') {
            steps {
                script {
                    // Try to execute the kubectl command directly within the agent environment.
                    // If minikube is missing, this will fail, but we'll try to recover the TARGET_COLOR
                    // based on the build number.
                    def kubectl_command = "minikube kubectl -- get deployment ${BLUE_DEPLOYMENT} --ignore-not-found -o jsonpath='{.status.replicas}'"
                    
                    try {
                        // Check status.replicas of the blue deployment.
                        def status = sh(script: kubectl_command, returnStdout: true, returnStatus: true)
                        
                        if (status.toInteger() == 0) { // Command failed or replicas is 0
                            env.TARGET_COLOR = 'blue'
                        } else {
                            // If the command returned something (e.g., Minikube was found and it's running), 
                            // check the actual output (replicas count).
                            def replicas = sh(script: kubectl_command, returnStdout: true).trim().toInteger()
                            if (replicas > 0) {
                                env.TARGET_COLOR = 'green'
                            } else {
                                env.TARGET_COLOR = 'blue'
                            }
                        }
                    } catch (e) {
                        // Fallback: This is what is currently executing (and failing).
                        // Since `minikube` is not found, we use the build number logic to determine the color.
                        if (env.BUILD_NUMBER.toInteger() == 1) {
                            env.TARGET_COLOR = 'blue'
                        } else {
                            // If build > 1 but minikube failed, we assume green for continuity.
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
                    // If minikube is not found, this will fail (exit code 127). 
                    // To handle this, we will wrap the execution logic into a function 
                    // that only executes if we can detect minikube's presence, but since 
                    // we cannot modify the environment, we must simplify to only the essential shell command.
                    
                    echo "Building image in Minikube using tag: ${env.LOCAL_IMAGE_TAG}"
                    sh """
                    # The following command requires the 'minikube' binary to be installed in the Jenkins agent.
                    # This is the point of failure for this pipeline run.
                    minikube image build -t ${env.LOCAL_IMAGE_TAG} .
                    """
                }
            }
        }

        // --- STAGE 3: Deploy New Version (Requires Kubectl) ---
        stage('Deploy New Version') {
            steps {
                script {
                    def kubectl_prefix = "minikube kubectl -- "
                    def image_tag = env.LOCAL_IMAGE_TAG

                    if (env.TARGET_COLOR == 'blue') {
                        echo "Initial deployment of BLUE."
                        // 1. Apply the service (needs to be done only once)
                        sh "${kubectl_prefix} apply -f service.yaml"
                        // 2. Apply the blue deployment file
                        sh "${kubectl_prefix} apply -f deployment-blue.yaml"
                        // 3. Set the image using the freshly built local tag
                        sh "${kubectl_prefix} set image deployment/${env.TARGET_DEPLOYMENT} myapp=${image_tag}"
                    } else {
                        // Deploy the green version by patching the blue deployment file
                        echo "Deploying ${env.TARGET_COLOR} deployment: ${env.TARGET_DEPLOYMENT}"
                        
                        // Use sed to create the green deployment YAML from the blue one on the fly and apply it
                        sh """
                        # This complex sed command needs kubectl to run, which is wrapped by minikube kubectl --
                        kubectl apply -f deployment-blue.yaml -o yaml --dry-run=client | \\
                        sed 's/${BLUE_DEPLOYMENT}/${GREEN_DEPLOYMENT}/g' | \\
                        sed 's/color: blue/color: green/g' | \\
                        ${kubectl_prefix} apply -f -
                        """
                        // Then set the image on the new deployment (this uses the color tag, which was just built)
                        sh "${kubectl_prefix} set image deployment/${env.TARGET_DEPLOYMENT} myapp=${image_tag}"
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
