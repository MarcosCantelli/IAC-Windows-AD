pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        // Injeta as credenciais do vSphere criadas no Jenkins como variáveis de ambiente para o Terraform
        TF_VAR_vsphere_user     = credentials('vsphere-user')
        TF_VAR_vsphere_password = credentials('vsphere-password')
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
            }
        }

        stage('Limpar state anterior') {
            steps {
                dir('terraform') {
                    // Limpeza padrão para evitar travas de execuções locais anteriores
                    sh 'rm -f terraform.tfstate terraform.tfstate.backup tfplan'
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
                // Puxamos com segurança os acessos locais e do AD cadastrados no Jenkins Credentials
                withCredentials([
                    usernamePassword(credentialsId: 'windows-admin-local', usernameVariable: 'WIN_USER', passwordVariable: 'WIN_PASS'),
                    string(credentialsId: 'ansible-ad-password', variable: 'AD_PASS')
                ]) {
                    dir('terraform') {
                        script {
                            // Captura os outputs do Terraform convertendo-os em strings limpas separadas por espaço
                            def dhcpIpsStr = sh(script: 'terraform output -json vms_dhcp_ips | jq -r ".[]"', returnStdout: true).trim()
                            def staticIpsStr = sh(script: 'terraform output -json vms_calculated_static_ips | jq -r ".[]"', returnStdout: true).trim()

                            // Transforma as strings em listas do Groovy
                            def dhcpIps = dhcpIpsStr.split('\\s+')
                            def staticIps = staticIpsStr.split('\\s+')

                            // Varre a lista de máquinas criadas rodando a esteira para cada uma delas
                            for (int i = 0; i < dhcpIps.length; i++) {
                                def currentDhcpIp = dhcpIps[i]
                                def currentStaticIp = staticIps[i]

                                echo "------------------------------------------------------------"
                                echo "Iniciando configuração da VM ${i + 1}:"
                                echo "IP Temporário (DHCP): ${currentDhcpIp}"
                                echo "IP Final Alocado (Estático): ${currentStaticIp}"
                                echo "------------------------------------------------------------"

                                // 1. CORREÇÃO AQUI: Aguarda a porta do WinRM HTTPS (5986) usando 'nc' universal
                                echo "Aguardando WinRM (Porta 5986) em ${currentDhcpIp}..."
                                sh """
                                    for t in \$(seq 1 40); do
                                        if nc -z -w5 ${currentDhcpIp} 5986 2>/dev/null; then
                                            echo "WinRM disponível após \$((t*10)) segundos!"
                                            exit 0
                                        fi
                                        echo "Tentativa \$t/40 — aguardando inicialização do Windows..."
                                        sleep 10
                                    done
                                    echo "Timeout: WinRM não respondeu na porta 5986"
                                    exit 1
                                """

                                // 2. Dispara o Ansible passando dinamicamente as credenciais e as variáveis específicas da VM atual
                                dir('../ansible') {
                                    sh """
                                        ansible-playbook -i inventory/hosts.yml playbooks/configure-vm.yml \
                                          -e "target_ip=${currentDhcpIp}" \
                                          -e "ansible_user=${WIN_USER}" \
                                          -e "ansible_password=${WIN_PASS}" \
                                          -e "static_ip=${currentStaticIp}" \
                                          -e "domain_password=${AD_PASS}"
                                    """
                                }

                                // 3. Valida se após o fim do playbook a VM responde com sucesso no seu IP Estático definitivo
                                echo "Validando se a VM já está operando no IP fixo ${currentStaticIp}..."
                                sh """
                                    for t in \$(seq 1 15); do
                                        if ping -c 1 -W 2 ${currentStaticIp} >/dev/null; then
                                            echo "Sucesso! VM ativa e respondendo no IP Fixo: ${currentStaticIp}"
                                            exit 0
                                        fi
                                        echo "Aguardando migração de rede... tentativa \$t/15"
                                        sleep 10
                                    done
                                    echo "Aviso: A VM não respondeu ao ping no IP Estático ainda."
                                """
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline executado com sucesso absoluto! Todas as VMs Windows foram provisionadas, adicionadas ao AD e configuradas."
        }
        failure {
            echo "Houve uma falha no processo. Acionando rollback para evitar sujeira no vCenter..."
            dir('terraform') {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}