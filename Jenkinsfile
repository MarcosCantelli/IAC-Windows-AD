pipeline {

    agent any

    triggers {
        githubPush()
    }

    environment {
        // OLVM - mesmas credenciais do DevOps-MVRC-IAC + as duas da VLAN_AD/disco D:
        TF_VAR_ovirt_url                   = credentials('olvm-url')
        TF_VAR_ovirt_username              = credentials('olvm-username')
        TF_VAR_ovirt_password              = credentials('olvm-password')
        TF_VAR_cluster_id                  = credentials('olvm-cluster-id')
        TF_VAR_vnic_profile_id             = credentials('olvm-vnic-profile-id')
        TF_VAR_ad_vnic_profile_id          = credentials('olvm-ad-vnic-profile-id')
        TF_VAR_data_disk_storage_domain_id = credentials('olvm-storage-domain-id')

        // Windows. usernamePassword vira WIN_ADMIN_USR / WIN_ADMIN_PSW.
        // O Ansible lê as três do ambiente (group_vars), nunca da linha de
        // comando - assim a senha não aparece no "ps" do Jenkins.
        WIN_ADMIN                          = credentials('windows-admin-local')
        AD_JOIN_PASSWORD                   = credentials('ansible-ad-password')

        // Inventário gerado a partir do output do Terraform
        INVENTARIO                         = 'inventory/generated.json'
    }

    stages {

        /////////////////////////////////////////////////////////////////////
        // CHECKOUT
        /////////////////////////////////////////////////////////////////////

        stage('Checkout') {
            steps {
                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
            }
        }

        /////////////////////////////////////////////////////////////////////
        // VALIDAR CREDENCIAIS
        // O Jenkins não exporta variável vazia: sem esta checagem, uma
        // credencial em branco vira um erro do Terraform/Ansible que não
        // diz qual credencial é. Nunca imprime valores.
        /////////////////////////////////////////////////////////////////////

        stage('Validar credenciais') {
            steps {
                sh '''
                    falhou=0
                    for par in TF_VAR_ovirt_url:olvm-url \
                               TF_VAR_ovirt_username:olvm-username \
                               TF_VAR_ovirt_password:olvm-password \
                               TF_VAR_cluster_id:olvm-cluster-id \
                               TF_VAR_vnic_profile_id:olvm-vnic-profile-id \
                               TF_VAR_ad_vnic_profile_id:olvm-ad-vnic-profile-id \
                               TF_VAR_data_disk_storage_domain_id:olvm-storage-domain-id \
                               WIN_ADMIN_USR:windows-admin-local \
                               WIN_ADMIN_PSW:windows-admin-local \
                               AD_JOIN_PASSWORD:ansible-ad-password; do
                        var=${par%%:*}; id=${par#*:}
                        if [ -z "$(printenv "$var")" ]; then
                            echo "ERRO: credencial '$id' está VAZIA no Jenkins (preencha de novo)."
                            falhou=1
                        fi
                    done
                    if [ "$TF_VAR_vnic_profile_id" = "$TF_VAR_ad_vnic_profile_id" ]; then
                        echo "ERRO: olvm-vnic-profile-id e olvm-ad-vnic-profile-id são iguais - as duas placas cairiam na mesma rede."
                        falhou=1
                    fi
                    for bin in terraform ansible-playbook ansible-galaxy jq nc; do
                        if ! command -v "$bin" >/dev/null 2>&1; then
                            echo "ERRO: '$bin' não está instalado no Jenkins."
                            falhou=1
                        fi
                    done
                    [ "$falhou" -eq 0 ] && echo "Credenciais e ferramentas OK."
                    exit "$falhou"
                '''
            }
        }

        /////////////////////////////////////////////////////////////////////
        // TERRAFORM
        /////////////////////////////////////////////////////////////////////

        // Mesmo padrão do DevOps-MVRC-IAC: cada execução cria VMs novas.
        // Rodar de novo com as VMs existindo falha por nome repetido, sem
        // tocar nas que já estão no OLVM.
        stage('Limpar state anterior') {
            steps {
                dir('terraform') {
                    sh 'rm -f terraform.tfstate terraform.tfstate.backup tfplan'
                }
                sh 'rm -f ansible/inventory/generated.json'
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init -input=false'
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
                    sh 'terraform plan -input=false -out=tfplan'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    // timeout: sem guest agent no template, o ovirt_wait_for_ip
                    // espera para sempre. Estourando, vira falha e o post destrói.
                    sh 'timeout 30m terraform apply -input=false -auto-approve tfplan'
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // CAPTURAR IPS
        // O guest agent pode reportar a VM antes do DHCP responder (só com
        // 169.254.x.x). Nesse caso o IP vem null e o Terraform relê o guest
        // agent com refresh-only até todas as VMs terem IP.
        /////////////////////////////////////////////////////////////////////

        stage('Capturar IPs das VMs') {
            steps {
                dir('terraform') {
                    sh '''
                        faltando=1
                        for t in $(seq 1 20); do
                            faltando=$(terraform output -json vms_dhcp_ips | jq '[.[] | select(. == null)] | length')
                            [ "$faltando" -eq 0 ] && break
                            echo "$faltando VM(s) ainda sem IP DHCP (tentativa $t/20). Relendo o guest agent em 30s..."
                            sleep 30
                            timeout 5m terraform apply -refresh-only -input=false -auto-approve > /dev/null
                        done
                        if [ "$faltando" -ne 0 ]; then
                            echo "ERRO: VM sem IP na rede de provisionamento. Confira o DHCP da ovirtmgmt e o provisioning_ip_regex."
                            exit 1
                        fi
                        terraform output -json ansible_inventory > ../ansible/inventory/generated.json
                    '''

                    script {
                        env.DHCP_IPS = sh(
                            script: '''terraform output -json vms_dhcp_ips | jq -r 'join(",")' ''',
                            returnStdout: true
                        ).trim()

                        def nomes = sh(
                            script: '''terraform output -json vms_names | jq -r 'join(",")' ''',
                            returnStdout: true
                        ).trim()

                        def fixos = sh(
                            script: '''terraform output -json vms_static_ips | jq -r 'join(",")' ''',
                            returnStdout: true
                        ).trim()

                        env.VMS_RESUMO = "${nomes} | DHCP ${env.DHCP_IPS} | VLAN_AD ${fixos}"
                        echo "VMs: ${env.VMS_RESUMO}"
                    }
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // AGUARDAR WINRM
        /////////////////////////////////////////////////////////////////////

        stage('Aguardar WinRM') {
            steps {
                sh '''
                    for ip in $(echo "$DHCP_IPS" | tr ',' ' '); do
                        ok=0
                        for t in $(seq 1 40); do
                            if nc -z -w5 "$ip" 5986 2>/dev/null; then
                                ok=1
                                break
                            fi
                            echo "WinRM 5986 em $ip: tentativa $t/40..."
                            sleep 15
                        done
                        if [ "$ok" -ne 1 ]; then
                            echo "ERRO: WinRM não respondeu em $ip. Confira o listener HTTPS no template."
                            exit 1
                        fi
                        echo "WinRM disponível em $ip"
                    done
                '''
            }
        }

        /////////////////////////////////////////////////////////////////////
        // PIPELINE BASE: base + rede + ingresso no AD
        /////////////////////////////////////////////////////////////////////

        stage('Pipeline BASE + AD') {
            steps {
                dir('ansible') {
                    sh 'ansible-galaxy collection install -r requirements.yml'

                    sh '''
                        ansible-playbook \
                          -i "$INVENTARIO" \
                          playbooks/configure-vm.yml \
                          --tags base
                    '''
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // APROVAÇÃO DEV
        /////////////////////////////////////////////////////////////////////

        stage('Aprovação DEV') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    script {
                        def resposta = input(
                            message: 'VM no domínio. Deseja continuar para instalação DEV?',
                            ok: 'Continuar',
                            parameters: [
                                booleanParam(
                                    name: 'INSTALAR_DEV',
                                    defaultValue: true,
                                    description: 'Instalar Java, Python, NodeJS e DevTools?'
                                )
                            ]
                        )

                        env.CONTINUAR_DEV = resposta.toString()
                    }
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // PIPELINE DEV
        /////////////////////////////////////////////////////////////////////

        stage('Pipeline DEV') {
            when {
                expression { return env.CONTINUAR_DEV == 'true' }
            }
            steps {
                dir('ansible') {
                    sh '''
                        ansible-playbook \
                          -i "$INVENTARIO" \
                          playbooks/configure-vm.yml \
                          --tags dev
                    '''
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // APROVAÇÃO FINAL
        /////////////////////////////////////////////////////////////////////

        stage('Aprovação Final') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    script {
                        def resposta = input(
                            message: 'Deseja finalizar desativando a placa de provisionamento?',
                            ok: 'Finalizar',
                            parameters: [
                                booleanParam(
                                    name: 'FINALIZAR',
                                    defaultValue: true,
                                    description: 'Deixar a VM só na VLAN_AD? Depois disso o Jenkins não alcança mais a VM.'
                                )
                            ]
                        )

                        env.FINALIZAR_PIPELINE = resposta.toString()
                    }
                }
            }
        }

        /////////////////////////////////////////////////////////////////////
        // PIPELINE FINAL
        /////////////////////////////////////////////////////////////////////

        stage('Pipeline FINAL') {
            when {
                expression { return env.FINALIZAR_PIPELINE == 'true' }
            }
            steps {
                dir('ansible') {
                    sh '''
                        ansible-playbook \
                          -i "$INVENTARIO" \
                          playbooks/configure-vm.yml \
                          --tags finalize
                    '''
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
                if (env.CONTINUAR_DEV != 'true' && env.FINALIZAR_PIPELINE != 'true') {
                    currentBuild.description = 'VM no domínio (sem DEV, placa de provisionamento ativa)'
                } else if (env.FINALIZAR_PIPELINE != 'true') {
                    currentBuild.description = 'VM no domínio + DEV (placa de provisionamento ativa)'
                } else {
                    currentBuild.description = 'Provisionamento completo: VM só na VLAN_AD'
                }
            }
            echo "Pipeline executado com sucesso! ${env.VMS_RESUMO ?: ''}"
        }

        aborted {
            echo "Pipeline abortado (aprovação recusada ou timeout). As VMs foram MANTIDAS no OLVM: ${env.VMS_RESUMO ?: 'nenhuma criada'}"
        }

        failure {
            script {
                // Se a falha for antes de algum stage (ex: credencial que não
                // existe no bloco environment), o post roda sem workspace: não
                // há nada a destruir e o dir() esconderia o erro real.
                try {
                    dir('terraform') {
                        echo 'Falha detectada. Destruindo as VMs criadas nesta execução...'
                        // -refresh=false: o refresh relê o ovirt_wait_for_ip, que
                        // espera para sempre se a VM não tiver IP (ex: não bootou).
                        sh 'timeout 20m terraform destroy -input=false -auto-approve -refresh=false || true'
                    }
                    echo 'Se a falha foi depois do join, remova a conta de computador que ficou no AD.'
                } catch (org.jenkinsci.plugins.workflow.steps.MissingContextVariableException e) {
                    echo 'Pipeline falhou antes de alocar o workspace (ex: credencial ausente) - nada para destruir. Veja o erro no fim do log.'
                }
            }
        }
    }
}
