# Contexto para continuar: VM Windows no OLVM com ingresso no AD

> **Como usar:** abra uma sessão nova do Claude Code na raiz deste repo e mande:
> "Leia o CONTEXTO-OLVM.md e vamos seguir do próximo passo pendente."
>
> Atualizado em 20/11/2026.

---

## Regras fixas

- O Claude **só faz commit local**. Push, force-push, apagar branch e reset ficam com o Marcos. Depois de commitar, o Claude informa em uma linha o hash, a branch e o comando de push.
- Responder em português.
- Senhas de banco: só letras e números.
- O job do Jenkins observa a `main` com `githubPush()`: **push na `main` dispara a pipeline**. Push em outras branches não dispara.

---

## Objetivo

Pipeline Jenkins + Terraform + Ansible que:

1. cria uma VM Windows 11 no **OLVM**, a partir de um template;
2. configura a rede da **VLAN_AD**;
3. ingressa a VM no AD `mvrc.local`.

Antes isso era feito no vSphere (branch `vcenter`), e a VM nunca chegava a entrar no domínio.

---

## Onde estamos

| Item | Estado |
|---|---|
| Branch `olvm` (commit `74166d4`) | Pronta. Já mergeada na `main` pela PR #36 (`6c8320b`) |
| Branch `vcenter` | Código antigo do vSphere, com os bugs. Mergeada antes na `main` pela PR #35 |
| Build #39 (código antigo, vSphere) | Falhou: `ansible_user=-admin-local` (bug do `$windows-admin-local`). A VM foi destruída pelo rollback |
| Primeiro build da `main` com o código OLVM | **Não conferido.** Deve falhar no bloco `environment` por falta das credenciais novas, sem criar nada |
| Testes contra o OLVM/AD real | **Nenhum ainda** |

Validado sem o ambiente: `terraform validate` com o provider `oVirt/ovirt` 2.2.0, a lógica de escolha do IP DHCP, `ansible-playbook --syntax-check`, `--list-tasks` por tag, ansible-lint e os parâmetros do `microsoft.ad.membership` 1.12.

---

## Por que a VM não entrava no AD (já corrigido na `olvm`)

1. **Credenciais no Jenkinsfile antigo.** `-e "ansible_user=$windows-admin-local"`: o shell expande `$windows` como vazia e sobra `-admin-local`. O build #39 provou isso. Agora o `group_vars` lê do ambiente: `WIN_ADMIN_USR`, `WIN_ADMIN_PSW` e `AD_JOIN_PASSWORD`.
2. **A role `network` desativava a NIC DHCP logo após o join.** O Ansible estava conectado por ela, então o host ficava unreachable, a pipeline falhava e o `terraform destroy` rodava. Agora isso só acontece na role `finalize`, em segundo plano, depois de confirmar o domínio.
3. **A role `finalize` não existia.** Foi criada.
4. **`ansible/group_vars` nunca era carregado.** Foi movido para `ansible/inventory/group_vars`.
5. **DNS da NIC DHCP.** Ela continuava com o BIND9 da 192.168.31.x, que também responde por `mvrc.local`, e o Windows não achava o SRV do DC. Agora as duas placas usam o DNS do AD.
6. **Relógio.** Com o template em "Other OS", o OLVM sobe o relógio em UTC (3 horas de diferença) e o Kerberos recusa o join. A role `network` acerta a hora pelo Jenkins.

---

## Ambiente

| Item | Valor |
|---|---|
| Hypervisor | OLVM (oVirt), self-hosted engine, login via Keycloak (`...@internalsso`) |
| Rede de provisionamento | `ovirtmgmt`, DHCP 192.168.31.x. O Jenkins fala WinRM por ela |
| VLAN_AD | 172.16.0.0/24, **sem DHCP** (o log do vSphere mostrou 169.254.x na 2ª placa). Precisa de VLAN tag no host |
| DC / DNS / gateway | 172.16.0.254 (WinServer22_AD, com RRAS) |
| Domínio | `mvrc.local`, conta de ingresso `ansible@mvrc.local` |
| VM / hostname | `Win11_AD-01` / `VDI-W11-50` (IP fixo 172.16.0.50) |
| Template | `W11_25H2_ANSIBLE` no `terraform.tfvars`. **Confirmar se existe no OLVM.** O `Win11_Template` migrado do vCenter provavelmente não tem WinRM |
| Storage | `hosted_storage` **não serve** para template nem para o disco D:. Usar um domínio de dados comum (ex: `data_vms_hd`) |
| Projeto de referência | `../DevOps-MVRC-IAC-1` (mesmo padrão: credenciais `olvm-*`, state limpo a cada execução) |

Limitações do provider 2.2.0 que guiaram o código:

- Não há data source por nome para cluster, vNIC profile ou storage domain: só UUID, que vem por credencial.
- As NICs criadas pelo Terraform são sempre **VirtIO**. O template precisa do driver NetKVM.
- O `ovirt_wait_for_ip` depende do QEMU Guest Agent. Sem ele, espera para sempre (o Jenkins tem `timeout 30m`).

---

## Passo a passo pendente

### Passo 0: conferir o build da `main` com o código OLVM
- [ ] No Jenkins, veja o build disparado pelo merge da PR #36. O esperado é falhar no início, sem criar VM, por "credential not found" (`olvm-ad-vnic-profile-id`).
- [ ] Se ele criou alguma VM no vSphere ou no OLVM, apague-a.

### Passo 1: rede VLAN_AD no OLVM
- [ ] Em *Network → Networks*, confirme que a `VLAN_AD` existe (com VLAN tag) e está no host (*Hosts → Setup Host Networks*).
- [ ] O DC (WinServer22_AD) precisa estar no OLVM, com uma placa na VLAN_AD respondendo em 172.16.0.254.
- [ ] Teste: de outra VM na VLAN_AD, `ping 172.16.0.254` e `nslookup mvrc.local 172.16.0.254`.

### Passo 2: template Windows 11 no OLVM
Parta de uma VM Win11 no OLVM (nova ou a `Win11_Template` migrada) e siga, em ordem:

- [ ] **Tipo de SO:** *Edit VM → General → Operating System: Windows 11*.
- [ ] **virtio-win:** anexe a ISO do virtio-win como CD e rode `virtio-win-guest-tools.exe`. Ele instala os drivers NetKVM e vioscsi e o QEMU Guest Agent. Depois confira, no `services.msc`, se o *QEMU Guest Agent* está **Automático e em execução**.
  - Se o disco de boot estiver em SATA (migrado do VMware), pode continuar em SATA. Só a rede precisa ser VirtIO.
- [ ] **WinRM HTTPS 5986** (PowerShell como admin):
  ```powershell
  Enable-PSRemoting -Force -SkipNetworkProfileCheck
  $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
  New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force
  New-NetFirewallRule -DisplayName "WinRM HTTPS 5986" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any
  winrm enumerate winrm/config/listener   # deve listar HTTPS na 5986
  ```
- [ ] **Usuário admin local** igual ao da credencial `windows-admin-local`. Se não for o `Administrator` embutido:
  ```powershell
  Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord
  ```
- [ ] **Teste do WinRM antes de virar template:** do Jenkins, `nc -zv <ip> 5986`. Depois um `ansible -m ansible.windows.win_ping` com o `inventory/hosts.yml` e as variáveis `WIN_ADMIN_*` exportadas.
- [ ] (Opcional, recomendado) `sysprep /generalize /oobe /shutdown` com um `unattend.xml` que pule o OOBE. **Depois do sysprep, confira se o listener HTTPS continua.** Sem sysprep o join funciona, mas os clones nascem com o mesmo SID.
- [ ] Desligue a VM e **remova as placas de rede** (*Network Interfaces → Remove*). O Terraform cria as duas.
- [ ] Confirme que o disco **não** está no `hosted_storage`. Se estiver, use *Templates → Disks → Copy* para outro domínio e remova a cópia antiga.
- [ ] *Make Template*. Se o nome for diferente de `W11_25H2_ANSIBLE`, me peça para ajustar o `terraform/terraform.tfvars`.

### Passo 3: credenciais do Jenkins
- [ ] Pegue os IDs no engine:
  ```bash
  sudo -u postgres psql -d engine -c "select p.id, p.name as perfil, n.name as rede from vnic_profiles p join network n on n.id = p.network_id;"
  sudo -u postgres psql -d engine -c "select id, storage_name from storage_domain_static;"
  ```
- [ ] Crie `olvm-ad-vnic-profile-id` (Secret text) com o UUID do profile da **VLAN_AD**.
- [ ] Crie `olvm-storage-domain-id` (Secret text) com o UUID do domínio do disco D: (não o `hosted_storage`).
- [ ] Confira se já existem: `olvm-url`, `olvm-username`, `olvm-password`, `olvm-cluster-id`, `olvm-vnic-profile-id` (ovirtmgmt), `windows-admin-local` e `ansible-ad-password`.
- [ ] O usuário `jenkins@...@internalsso` precisa de `DataCenterAdmin`. Já é assim no DevOps-MVRC-IAC.

### Passo 4: ferramentas no servidor Jenkins
- [ ] `jq`, `nc`, `terraform` e `ansible` (o stage *Validar credenciais* acusa o que faltar).
- [ ] `pywinrm` no Python do Ansible. Como usuário `jenkins`: `python3 -m pip install --user pywinrm`, ou o pacote da distro.

### Passo 5: AD
- [ ] A conta `ansible@mvrc.local` precisa poder ingressar computadores (em *Computers* ou na OU de `ad_ou_path`).
- [ ] Se sobrou do build #39 a conta de computador `VDI-W11-50` no AD, apague-a.

### Passo 6: primeira execução
- [ ] Rode o job manualmente (*Build Now*) e acompanhe stage a stage.
- [ ] Pontos de maior risco, em ordem:
  1. clone do template (permissão / `hosted_storage`);
  2. IP pelo guest agent;
  3. WinRM;
  4. disco D: (driver vioscsi);
  5. portas e DNS do DC;
  6. o join em si.
- [ ] Na falha, a VM é destruída (`terraform destroy -refresh=false`). Copie o log do stage que falhou e mande para o Claude.
- [ ] Na **Aprovação DEV** e na **Aprovação Final** dá para parar sem destruir a VM: abortar mantém as VMs.

### Alternativa enquanto o template do OLVM não fica pronto
Aplicar as mesmas correções na branch `vcenter` para validar o join no vSphere, que está funcionando (o build #39 criou a VM e o WinRM respondeu). **Ainda não foi feito: decidir.**

---

## Arquivos principais

| Arquivo | Papel |
|---|---|
| `Jenkinsfile` | Credenciais `olvm-*`, validação, Terraform, captura de IP (com `refresh-only`), WinRM, BASE+AD, DEV, FINAL |
| `terraform/main.tf` | Template, VM, nic1 (ovirtmgmt), nic2 (VLAN_AD), disco D:, start e `ovirt_wait_for_ip` |
| `terraform/outputs.tf` | `ansible_inventory`, que o Jenkins grava em `ansible/inventory/generated.json` |
| `ansible/inventory/group_vars/all.yml` | Domínio, DC, gateway, hostname, conta de ingresso |
| `ansible/inventory/group_vars/windows.yml` | WinRM (5986, NTLM), credenciais via ambiente, versões dos programas |
| `ansible/roles/network` | Hostname, IP fixo, DNS do AD nas duas placas, firewall WinRM, relógio |
| `ansible/roles/ad_join` | Testa portas e SRV do DC, `microsoft.ad.membership`, validação |
| `ansible/roles/finalize` | Confere o domínio e desativa a nic1 em segundo plano |
| `README.md` | Documentação completa |
