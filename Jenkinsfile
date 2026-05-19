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

        stage('Checkout') {
            steps {
                checkout scm

                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
            }
        }

        stage('Limpar state anterior') {
            steps {
                dir('terraform') {
                    sh '''
                        rm -f terraform.tfstate
                        rm -f terraform.tfstate.backup
                        rm -f tfplan
                    '''
                }
            }
        }

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

        stage('Orquestrar Ansible para as VMs') {

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

                                echo "------------------------------------------------------------"
                                echo "Configurando VM ${i + 1}"
                                echo "DHCP IP: ${currentDhcpIp}"
                                echo "STATIC IP: ${currentStaticIp}"
                                echo "------------------------------------------------------------"

                                stage("Aguardar WinRM VM ${i + 1}") {

                                    sh """
                                        for t in \$(seq 1 40); do

                                            if nc -z -w5 ${currentDhcpIp} 5986 2>/dev/null; then
                                                echo "WinRM disponível!"
                                                exit 0
                                            fi

                                            echo "Tentativa \$t/40..."
                                            sleep 10

                                        done

                                        echo "Timeout aguardando WinRM"
                                        exit 1
                                    """
                                }

                                stage("Executar Ansible VM ${i + 1}") {

                                    dir('../ansible') {

                                        withEnv([
                                            "TARGET_IP=${currentDhcpIp}",
                                            "STATIC_IP=${currentStaticIp}"
                                        ]) {

                                            sh '''
                                                ansible-playbook -i inventory/hosts.yml playbooks/configure-vm.yml \
                                                  -e "target_ip=$TARGET_IP" \
                                                  -e "ansible_user=$WIN_USER" \
                                                  -e "ansible_password=$WIN_PASS" \
                                                  -e "static_ip=$STATIC_IP" \
                                                  -e "domain_password=$AD_PASS"
                                            '''
                                        }
                                    }
                                }

                                stage("Validar IP Final VM ${i + 1}") {

                                    sh """
                                        for t in \$(seq 1 15); do

                                            if ping -c 1 -W 2 ${currentStaticIp} >/dev/null; then
                                                echo "VM respondendo no IP ${currentStaticIp}"
                                                exit 0
                                            fi

                                            echo "Aguardando migração DHCP -> IP fixo"
                                            sleep 10

                                        done

                                        echo "VM ainda não respondeu no IP fixo"
                                    """
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    post {

        success {
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