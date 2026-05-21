pipeline {

    agent any

    triggers {
        githubPush()
    }

    environment {
        TF_VAR_vsphere_user     = credentials('vsphere-user')
        TF_VAR_vsphere_password = credentials('vsphere-password')
    }

    stages {

        /////////////////////////////////////////////////////////////////////
        // CHECKOUT
        /////////////////////////////////////////////////////////////////////

        stage('Checkout') {

            steps {

                checkout scm

                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
            }
        }

        /////////////////////////////////////////////////////////////////////
        // TERRAFORM
        /////////////////////////////////////////////////////////////////////

        stage('Terraform Init') {

            steps {

                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Validate') {

            steps {

                dir('terraform') {
                    sh 'terraform validate'
                }
            }
        }

        stage('Terraform Plan') {

            steps {

                dir('terraform') {
                    sh 'terraform plan -out=tfplan'
                }
            }
        }

        stage('Terraform Apply') {

            steps {

                dir('terraform') {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // PIPELINE BASE
        /////////////////////////////////////////////////////////////////////

        stage('Pipeline BASE') {

            steps {

                withCredentials([

                    usernamePassword(
                        credentialsId: 'windows-admin-local',
                        usernameVariable: 'WIN_USER',
                        passwordVariable: 'WIN_PASS'
                    ),

                    string(
                        credentialsId: 'ansible-ad-password',
                        variable: 'AD_PASS'
                    )

                ]) {

                    dir('terraform') {

                        script {

                            def dhcpIpsStr = sh(
                                script: 'terraform output -json vms_dhcp_ips | jq -r ".[]"',
                                returnStdout: true
                            ).trim()

                            def staticIpsStr = sh(
                                script: 'terraform output -json vms_calculated_static_ips | jq -r ".[]"',
                                returnStdout: true
                            ).trim()

                            def dhcpIps = dhcpIpsStr.split('\\s+')
                            def staticIps = staticIpsStr.split('\\s+')

                            for (int i = 0; i < dhcpIps.length; i++) {

                                def currentDhcpIp = dhcpIps[i]
                                def currentStaticIp = staticIps[i]

                                echo "--------------------------------------------------"
                                echo "Configurando VM ${i + 1}"
                                echo "DHCP IP: ${currentDhcpIp}"
                                echo "STATIC IP: ${currentStaticIp}"
                                echo "--------------------------------------------------"

                                /////////////////////////////////////////////////////////////////////
                                // AGUARDA WINRM
                                /////////////////////////////////////////////////////////////////////

                                sh """
                                    for t in \$(seq 1 10); do

                                        if nc -z -w5 ${currentDhcpIp} 5986 2>/dev/null; then
                                            echo "WinRM disponível!"
                                            exit 0
                                        fi

                                        echo "Tentativa \$t/10..."
                                        sleep 10

                                    done

                                    echo "Timeout aguardando WinRM"
                                    exit 1
                                """

                                /////////////////////////////////////////////////////////////////////
                                // ANSIBLE BASE
                                /////////////////////////////////////////////////////////////////////

                                dir('../ansible') {

                                    withEnv([
                                        "TARGET_IP=${currentDhcpIp}",
                                        "STATIC_IP=${currentStaticIp}"
                                    ]) {

                                        sh '''
                                            ansible-playbook \
                                              -i inventory/hosts.yml \
                                              playbooks/configure-vm.yml \
                                              --tags base \
                                              -e "target_ip=$TARGET_IP" \
                                              -e "ansible_user=$WIN_USER" \
                                              -e "ansible_password=$WIN_PASS" \
                                              -e "static_ip=$STATIC_IP" \
                                              -e "domain_password=$AD_PASS"
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // APROVAÇÃO DEV
        /////////////////////////////////////////////////////////////////////

        stage('Aprovação DEV') {

            steps {

                script {

                    env.CONTINUAR_DEV = input(
                        message: 'Deseja instalar ferramentas DEV?',
                        ok: 'Continuar',
                        parameters: [
                            booleanParam(
                                defaultValue: true,
                                name: 'INSTALAR_DEV',
                                description: 'Instalar Python, Java e NodeJS?'
                            )
                        ]
                    ).toString()
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // PIPELINE DEV
        /////////////////////////////////////////////////////////////////////

        stage('Pipeline DEV') {

            when {
                expression {
                    return env.CONTINUAR_DEV == "true"
                }
            }

            steps {

                withCredentials([

                    usernamePassword(
                        credentialsId: 'windows-admin-local',
                        usernameVariable: 'WIN_USER',
                        passwordVariable: 'WIN_PASS'
                    )

                ]) {

                    dir('terraform') {

                        script {

                            def staticIpsStr = sh(
                                script: 'terraform output -json vms_calculated_static_ips | jq -r ".[]"',
                                returnStdout: true
                            ).trim()

                            def staticIps = staticIpsStr.split('\\s+')

                            for (int i = 0; i < staticIps.length; i++) {

                                def currentStaticIp = staticIps[i]

                                dir('../ansible') {

                                    withEnv([
                                        "TARGET_IP=${currentStaticIp}"
                                    ]) {

                                        sh '''
                                            ansible-playbook \
                                              -i inventory/hosts.yml \
                                              playbooks/configure-vm.yml \
                                              --tags dev \
                                              -e "target_ip=$TARGET_IP" \
                                              -e "ansible_user=$WIN_USER" \
                                              -e "ansible_password=$WIN_PASS"
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /////////////////////////////////////////////////////////////////////
    // POST
    /////////////////////////////////////////////////////////////////////

    post {

        success {

            script {

                if (env.CONTINUAR_DEV == "false") {

                    currentBuild.description =
                        "Finalizado com sucesso após pipeline BASE"

                } else {

                    currentBuild.description =
                        "Provisionamento completo executado com sucesso"
                }
            }

            echo "Pipeline executado com sucesso!"
        }

        failure {

            echo "Falha detectada. Executando rollback..."

            dir('terraform') {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}