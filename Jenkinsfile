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

                            /////////////////////////////////////////////////////////////////////
                            // SALVA LISTA PARA PIPELINES FUTUROS
                            /////////////////////////////////////////////////////////////////////

                            env.DHCP_IPS   = dhcpIps.join(',')
                            env.STATIC_IPS = staticIps.join(',')

                            for (int i = 0; i < dhcpIps.length; i++) {

                                def currentDhcpIp = dhcpIps[i]
                                def currentStaticIp = staticIps[i]

                                echo "--------------------------------------------------"
                                echo "Configurando VM ${i + 1}"
                                echo "DHCP IP: ${currentDhcpIp}"
                                echo "STATIC IP: ${currentStaticIp}"
                                echo "--------------------------------------------------"

                                /////////////////////////////////////////////////////////////////////
                                // AGUARDA WINRM VIA DHCP
                                /////////////////////////////////////////////////////////////////////

                                sh """
                                    for t in \$(seq 1 20); do

                                        if nc -z -w5 ${currentDhcpIp} 5986 2>/dev/null; then
                                            echo "WinRM disponível no IP DHCP!"
                                            exit 0
                                        fi

                                        echo "Tentativa \$t/20..."
                                        sleep 15

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

                                /////////////////////////////////////////////////////////////////////
                                // VALIDAR QUE A VM CONTINUA RESPONDENDO
                                // NO DHCP APÓS O DOMAIN JOIN
                                /////////////////////////////////////////////////////////////////////

                                sh """
                                    for t in \$(seq 1 20); do

                                        if nc -z -w5 ${currentDhcpIp} 5986 2>/dev/null; then
                                            echo "VM voltou após reboot/domain join!"
                                            exit 0
                                        fi

                                        echo "Aguardando retorno WinRM pós-domain..."
                                        sleep 20

                                    done

                                    echo "VM não retornou após domain join"
                                    exit 1
                                """
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

                timeout(time: 30, unit: 'MINUTES') {

                    script {

                        def resposta = input(
                            message: 'Deseja continuar para instalação DEV?',
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

                    script {

                        /////////////////////////////////////////////////////////////////////
                        // IMPORTANTE:
                        // CONTINUAMOS USANDO O IP DHCP (192.168.x.x)
                        // ENQUANTO EXISTIR A PLACA VM NETWORK
                        /////////////////////////////////////////////////////////////////////

                        def dhcpIps = env.DHCP_IPS.split(',')

                        for (int i = 0; i < dhcpIps.length; i++) {

                            def currentDhcpIp = dhcpIps[i]

                            echo "--------------------------------------------------"
                            echo "Instalando DEV VM ${i + 1}"
                            echo "IP DHCP: ${currentDhcpIp}"
                            echo "--------------------------------------------------"

                            /////////////////////////////////////////////////////////////////////
                            // GARANTE WINRM
                            /////////////////////////////////////////////////////////////////////

                            sh """
                                for t in \$(seq 1 20); do

                                    if nc -z -w5 ${currentDhcpIp} 5986 2>/dev/null; then
                                        echo "WinRM disponível!"
                                        exit 0
                                    fi

                                    echo "Tentativa \$t/20..."
                                    sleep 15

                                done

                                echo "Timeout aguardando WinRM DEV"
                                exit 1
                            """

                            /////////////////////////////////////////////////////////////////////
                            // EXECUTA PLAYBOOK DEV
                            /////////////////////////////////////////////////////////////////////

                            dir('ansible') {

                                withEnv([
                                    "TARGET_IP=${currentDhcpIp}"
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

        /////////////////////////////////////////////////////////////////////
        // APROVAÇÃO FINAL
        /////////////////////////////////////////////////////////////////////

        stage('Aprovação Final') {

            when {
                expression {
                    return env.CONTINUAR_DEV == "true"
                }
            }

            steps {

                timeout(time: 30, unit: 'MINUTES') {

                    script {

                        def resposta = input(
                            message: 'Deseja finalizar removendo NIC DHCP?',
                            ok: 'Finalizar',
                            parameters: [
                                booleanParam(
                                    name: 'FINALIZAR',
                                    defaultValue: true,
                                    description: 'Remover VM Network e deixar apenas VLAN_AD?'
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
                expression {
                    return env.FINALIZAR_PIPELINE == "true"
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

                    script {

                        def dhcpIps = env.DHCP_IPS.split(',')

                        for (int i = 0; i < dhcpIps.length; i++) {

                            def currentDhcpIp = dhcpIps[i]

                            echo "Finalizando VM ${i + 1}"

                            dir('ansible') {

                                withEnv([
                                    "TARGET_IP=${currentDhcpIp}"
                                ]) {

                                    sh '''
                                        ansible-playbook \
                                          -i inventory/hosts.yml \
                                          playbooks/configure-vm.yml \
                                          --tags finalize \
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

    /////////////////////////////////////////////////////////////////////
    // POST
    /////////////////////////////////////////////////////////////////////

    post {

        success {

            script {

                if (env.CONTINUAR_DEV != "true") {

                    currentBuild.description =
                        "Finalizado com sucesso após Pipeline BASE"

                } else if (env.FINALIZAR_PIPELINE != "true") {

                    currentBuild.description =
                        "Finalizado com sucesso após Pipeline DEV"

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