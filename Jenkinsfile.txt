pipeline {
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
                git branch: 'master', url: 'https://github.com/parvathyv-nair/blue-green-app.git'
            }
        }

        stage('Determine Target Color') {
            steps {
                script {
                    // Check if blue deployment exists. If it exists, deploy green. If not, deploy blue first.
                    def status = sh(script: "kubectl get deployment ${BLUE_DEPLOYMENT} --ignore-not-found -o custom-columns=STATUS:.status.replicas", returnStatus: true)
                    
                    if (status == 0) {
                        // Blue is active, so we target Green for the new deployment
                        env.TARGET_COLOR = 'green'
                        env.TARGET_DEPLOYMENT = env.GREEN_DEPLOYMENT
                        env.OTHER_DEPLOYMENT = env.BLUE_DEPLOYMENT
                    } else {
                        // Neither exists or Blue doesn't exist, start with Blue
                        env.TARGET_COLOR = 'blue'
                        env.TARGET_DEPLOYMENT = env.BLUE_DEPLOYMENT
                        env.OTHER_DEPLOYMENT = env.GREEN_DEPLOYMENT
                    }
                    echo "Targeting deployment: ${env.TARGET_COLOR}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Build the image using the current BUILD_NUMBER as the tag
                    sh "docker build -t ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG} ."
                    sh "docker tag ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG} ${DOCKER_HUB_USER}/${APP_NAME}:${env.TARGET_COLOR}"
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                // Use the Docker Hub credential ID 'dockerhub-pass' configured in Jenkins
                withCredentials([usernamePassword(credentialsId: 'dockerhub-pass', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USERNAME')]) {
                    sh "echo \$DOCKER_PASSWORD | docker login -u \$DOCKER_USERNAME --password-stdin"
                    // Push both the numbered tag and the color tag
                    sh "docker push ${DOCKER_HUB_USER}/${APP_NAME}:${IMAGE_TAG}"
                    sh "docker push ${DOCKER_HUB_USER}/${APP_NAME}:${env.TARGET_COLOR}"
                }
            }
        }

        stage('Deploy New Version') {
            steps {
                script {
                    // Use the deployment-blue.yaml as the base for the first run (Blue)
                    // On subsequent runs (Green), we patch the image and color label
                    
                    if (env.TARGET_COLOR == 'blue') {
                        // Initial deployment, apply the file as-is
                        sh "kubectl apply -f deployment-blue.yaml"
                    } else {
                        // Update the existing green deployment (or create it if it's the first green run)
                        sh """
                        kubectl apply -f deployment-blue.yaml -o yaml --dry-run=client | \
                        sed 's/${BLUE_DEPLOYMENT}/${GREEN_DEPLOYMENT}/g' | \
                        sed 's/color: blue/color: green/g' | \
                        kubectl apply -f -
                        """
                        // Then update the new deployment's image
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

        stage('Switch Service (Blue-Green Swap)') {
            steps {
                // Only pause and switch if this is not the first blue deployment
                script {
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
                         // Initial blue deployment, just apply service.yaml to ensure it exists
                         echo "Initial deployment of BLUE. Applying service.yaml."
                         sh "kubectl apply -f service.yaml"
                    }
                }
            }
        }
    }
}
