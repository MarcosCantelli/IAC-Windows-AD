# IAC-Windows-AD

> Pipeline de Infraestrutura como Código que cria VMs Windows 11 no OLVM (Oracle Linux Virtualization Manager), configura a rede da VLAN_AD e ingressa as VMs no Active Directory `mvrc.local`, usando Jenkins, Terraform e Ansible.

> Esta é a branch `olvm`. A versão original para vSphere fica na branch `vcenter`. A estrutura segue o [DevOps-MVRC-IAC](https://github.com/MarcosCantelli/DevOps-MVRC-IAC) (provider `oVirt/ovirt`, credenciais `olvm-*`, state limpo a cada execução).

---

## Fluxo

```
Jenkins
  │
  ├── Terraform  → clona o template Windows no OLVM
  │                nic1 = ovirtmgmt (DHCP, provisionamento)
  │                nic2 = VLAN_AD
  │                disco D: (Programas)
  │                liga a VM e lê o IP DHCP pelo guest agent
  │
  ├── Ansible BASE + AD (WinRM HTTPS 5986 pelo IP DHCP)
  │     base     → disco D:, Chocolatey, timezone, long paths...
  │     network  → hostname, IP fixo na VLAN_AD, DNS do AD, relógio
  │     ad_join  → testa o DC, ingressa no domínio, reinicia, valida
  │
  ├── [aprovação] Ansible DEV  → Python, Java, NodeJS, DevTools
  │
  ├── [aprovação] Ansible FINAL → desativa a nic1: a VM fica só na VLAN_AD
  │
  └── Post → falha: terraform destroy | abortado: mantém as VMs
```

| Item | Valor padrão |
|---|---|
| VM no OLVM | `Win11_AD-01`, `-02`... (`vm_name`, `vm_count`) |
| Hostname | `VDI-W11-50` (prefixo + último octeto do IP fixo) |
| IP fixo VLAN_AD | `172.16.0.50` em diante (`ad_network_cidr`, `static_ip_start`) |
| Gateway / DNS / DC | `172.16.0.254` |
| Domínio | `mvrc.local`, conta `ansible@mvrc.local` |

---

## Por que a VM não entrava no AD (branch vcenter)

O código antigo tinha cinco problemas, todos corrigidos aqui:

| Problema | Efeito | Correção |
|---|---|---|
| `-e "ansible_user=$windows-admin-local"` e `domain_password=$ansible-ad-password` no Jenkinsfile | O shell expande `$windows` e `$ansible` (vazias): o Ansible recebia `-admin-local` e `-ad-password` | Credenciais lidas do ambiente no `group_vars` (`WIN_ADMIN_USR`, `WIN_ADMIN_PSW`, `AD_JOIN_PASSWORD`) |
| A role `network` desativava a NIC DHCP logo após o join | O Ansible estava conectado justamente por ela: host unreachable, falha e `terraform destroy` | A NIC só é desativada na role `finalize`, em segundo plano, depois de confirmar o domínio |
| Role `finalize` não existia | O stage FINAL sempre falhava (e destruía a VM) | Role criada |
| `ansible/group_vars` fora do lugar | Não fica ao lado do inventário nem do playbook: nada ali era carregado | Movido para `ansible/inventory/group_vars` |
| DNS da NIC DHCP continuava sendo o da rede 192.168.31.x | O BIND9 também responde por `mvrc.local`; o Windows perguntava a ele pelo `_ldap._tcp.dc._msdcs.mvrc.local` e não achava o DC | As duas placas usam o DNS do AD durante o provisionamento |

Também saiu o `join-ad.yml`, que usava o módulo `win_domain_membership` (removido) com parâmetros trocados, e entrou o `requirements.yml` com a coleção `microsoft.ad`.

---

## Estrutura

```
├── Jenkinsfile
├── terraform/
│   ├── main.tf            # template, VM, nic1/nic2, disco D:, start, guest agent
│   ├── variables.tf
│   ├── outputs.tf         # IPs e o inventário pronto para o Ansible
│   ├── versions.tf        # provider oVirt/ovirt ~> 2.2
│   └── terraform.tfvars   # só valores não sensíveis
└── ansible/
    ├── requirements.yml   # ansible.windows, community.windows, microsoft.ad, chocolatey
    ├── inventory/
    │   ├── hosts.yml      # para rodar da sua máquina
    │   ├── generated.json # gerado pelo Jenkins (fora do Git)
    │   └── group_vars/    # all.yml (AD) e windows.yml (WinRM, programas)
    ├── playbooks/configure-vm.yml   # tags: base, ad, dev, finalize
    └── roles/
        ├── base/          # disco D:, Chocolatey, políticas
        ├── network/       # hostname, IPs, DNS, firewall WinRM, relógio
        ├── ad_join/       # pré-checagens, join, validação
        ├── finalize/      # isola a VM na VLAN_AD
        └── python/ java/ nodejs/ devtools/
```

---

## Pré-requisitos no OLVM

### 1. VLAN_AD

A rede `VLAN_AD` precisa existir no OLVM e estar no host (`Setup Host Networks`), com VLAN tag se dividir a placa física com a `ovirtmgmt`. O controlador de domínio (`WinServer22_AD`) precisa de uma placa nela respondendo em `172.16.0.254`.

### 2. Template Windows

O provider não tem catálogo de imagens: o template precisa existir antes. Partindo de uma VM Windows 11 no OLVM:

1. **virtio-win**: instale o `virtio-win-guest-tools` (ISO do virtio-win). Ele traz os drivers NetKVM (rede) e vioscsi (disco) e o **QEMU Guest Agent**.
   - O provider 2.2.0 não deixa escolher o modelo da placa: as NICs criadas pelo Terraform são sempre **VirtIO**. Sem o NetKVM, o Windows não vê as placas.
   - Sem o guest agent, o Terraform espera o IP para sempre no `ovirt_wait_for_ip`.
2. **WinRM HTTPS na 5986**, com certificado (self-signed serve) e regra de firewall. O Ansible conecta por NTLM com um usuário **administrador local**. Se não for o `Administrator` embutido, deixe `LocalAccountTokenFilterPolicy = 1` já no template.
3. **Tipo de SO** `Windows 11` na VM (aba Geral). Com `Other OS`, o OLVM sobe o relógio em UTC e o Windows lê como hora local (3 horas de diferença, e o Kerberos recusa o join). A role `network` acerta o relógio de qualquer forma, mas o certo é o tipo correto. Também dá para forçar pelo `os_type` no `terraform.tfvars`.
4. **Remova as placas de rede** do template: o Terraform cria as duas.
5. Recomendado: generalize com `sysprep /generalize /oobe /shutdown` usando um `unattend.xml` que pule o OOBE e reabilite o WinRM. Sem sysprep o join funciona, mas todos os clones nascem com o mesmo SID de máquina.
6. **O disco do template não pode ficar no `hosted_storage`**: ali só SuperUser cria disco, e o clone feito pelo usuário do Jenkins falha com `Internal Engine Error` (`NON_ADMIN_USER_NOT_AUTHORIZED_TO_PERFORM_ACTION_ON_HE` no `engine.log`). Use um domínio de dados comum. O mesmo vale para o disco D: (`olvm-storage-domain-id`).
7. **Make Template** e coloque o nome exato em `template_name` no `terraform.tfvars` (padrão `W11_25H2_ANSIBLE`).

### 3. Conta no AD

A conta `ansible@mvrc.local` precisa ter permissão para ingressar computadores no domínio (ou na OU de `ad_ou_path`).

---

## Credenciais do Jenkins

| Credential ID | Tipo | Conteúdo |
|---|---|---|
| `olvm-url` | Secret text | URL da API do Engine (`https://<engine>/ovirt-engine/api`) |
| `olvm-username` | Secret text | Usuário do OLVM (ex: `jenkins@mvrc.local@internalsso`) |
| `olvm-password` | Secret text | Senha do usuário do OLVM |
| `olvm-cluster-id` | Secret text | UUID do cluster |
| `olvm-vnic-profile-id` | Secret text | UUID do vNIC profile da `ovirtmgmt` (nic1, DHCP) |
| `olvm-ad-vnic-profile-id` | Secret text | UUID do vNIC profile da `VLAN_AD` (nic2) **- nova** |
| `olvm-storage-domain-id` | Secret text | UUID do storage domain do disco D: (não o `hosted_storage`) **- nova** |
| `windows-admin-local` | Username with password | Admin local do template (WinRM) |
| `ansible-ad-password` | Secret text | Senha da conta `ansible@mvrc.local` |

As cinco primeiras são as mesmas do DevOps-MVRC-IAC. Os IDs saem do banco do engine (o portal não mostra o ID do vNIC profile):

```bash
sudo -u postgres psql -d engine -c "select p.id, p.name as perfil, n.name as rede from vnic_profiles p join network n on n.id = p.network_id;"
sudo -u postgres psql -d engine -c "select id, storage_name from storage_domain_static;"
```

O stage **Validar credenciais** aponta qual credencial está vazia, sem imprimir valores, e confere se `terraform`, `ansible-playbook`, `ansible-galaxy`, `jq` e `nc` existem no Jenkins. O Ansible do Jenkins também precisa do `pywinrm` (`pip install pywinrm`).

Job do Jenkins: *Pipeline script from SCM*, branch `*/olvm`, Script Path `Jenkinsfile`.

---

## Stages

| Stage | O que faz |
|---|---|
| Validar credenciais | Credenciais não vazias, vNIC profiles diferentes, ferramentas instaladas |
| Limpar state anterior | Apaga o tfstate: cada execução cria VMs novas |
| Terraform Init / Validate / Plan / Apply | Clona o template, cria nic1, nic2 e o disco D:, liga a VM |
| Capturar IPs das VMs | Lê o IP DHCP pelo guest agent; se ainda não veio, relê com `refresh-only` (até 10 min); grava `ansible/inventory/generated.json` |
| Aguardar WinRM | Porta 5986 em cada IP (até 10 min) |
| Pipeline BASE + AD | `--tags base`: roles base, network e ad_join |
| Aprovação DEV → Pipeline DEV | `--tags dev` |
| Aprovação Final → Pipeline FINAL | `--tags finalize`: confere o domínio e desativa a nic1 |

Na **falha**, o post roda `terraform destroy`. Se a falha foi depois do join, a conta de computador fica no AD e precisa ser apagada à mão. Se a pipeline for **abortada** (aprovação recusada ou timeout), as VMs ficam no OLVM.

> **Limitação:** como o state é apagado a cada execução (igual ao DevOps-MVRC-IAC), rodar de novo com as VMs existindo falha no Terraform por nome repetido, sem tocar nelas. Para recriar, apague as VMs no OLVM (e as contas no AD) antes.

---

## Ingresso no AD em detalhe

1. **Hostname** `VDI-W11-<octeto>`, com reboot.
2. **Placas**: a de provisionamento é a que tem o IP usado pelo WinRM; a da VLAN_AD é a outra placa física (precisa estar com link).
3. **VLAN_AD**: IP fixo, gateway `172.16.0.254`, DNS do AD, sufixo `mvrc.local`, registro no DNS ligado. Métrica 50, para a internet (Chocolatey) continuar saindo pela 192.168.31.x enquanto ela existir.
4. **Placa de provisionamento**: DNS do AD, métrica 10, sem registro no DNS do AD.
5. **Relógio**: se diferir mais de 60 s do Jenkins, é acertado (o Kerberos aceita no máximo 5 min).
6. **Pré-checagens**: portas 53/88/389/445 no DC e o SRV `_ldap._tcp.dc._msdcs.mvrc.local`. Cada uma falha com a causa provável.
7. **Join** com `microsoft.ad.membership` e reboot pelo próprio módulo, que reconecta pelo mesmo IP.
8. **Pós-join**: relógio passa a sincronizar com o domínio, `ipconfig /registerdns`, validação de `PartOfDomain` e do canal seguro.

---

## Rodar o Ansible da sua máquina

Útil para refazer só o join numa VM que já existe:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
pip install pywinrm

export WIN_ADMIN_USR='admin-local'
export WIN_ADMIN_PSW='...'
export AD_JOIN_PASSWORD='...'

# preencha ansible_host (IP DHCP) e static_ip em inventory/hosts.yml
ansible-playbook -i inventory/hosts.yml playbooks/configure-vm.yml --tags ad
```

---

## Estado de validação

Validado sem acesso ao ambiente:

- `terraform validate` e `terraform fmt` com o provider `oVirt/ovirt` 2.2.0
- a escolha do IP DHCP no output do guest agent (ignora `127.x` e `169.254.x`, devolve `null` sem DHCP)
- `ansible-playbook --syntax-check`, `--list-tasks` por tag e resolução das variáveis do inventário gerado
- parâmetros do `microsoft.ad.membership` na versão 1.12 da coleção

**Ainda não rodou contra o OLVM nem contra o AD.** O Jenkinsfile também não passou pelo Declarative Linter (exige um controlador Jenkins).

---

## Author

**Marcos Cantelli** - DevOps & Infrastructure Engineer

[GitHub](https://github.com/MarcosCantelli)
