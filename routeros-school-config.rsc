###############################################
# MIKROTIK - REDE ESCOLAR COMPLETA
#
# Cenário:
# Infraestrutura de rede para ambiente escolar
# com separação entre:
#
# - Rede Administrativa
# - Rede de Alunos
#
# Funcionalidades:
# - Dual WAN
# - Failover
# - Load Balance (PCC)
# - DHCP
# - Firewall
# - NAT
# - Acesso remoto seguro
#
# Observação:
# Neste cenário foram utilizados DHCP Servers
# separados em interfaces distintas porque
# parte da infraestrutura utilizava switches
# não gerenciáveis, impossibilitando o uso
# adequado de VLANs.
#
# ATENÇÃO:
# NÃO importar diretamente em produção
# sem revisar interfaces, IPs e portas.
###############################################


###############################################
# 1. RENOMEAR INTERFACES
###############################################

/interface ethernet

set ether1 name=WAN1
set ether2 name=WAN2
set ether3 name=LAN-ALUNOS
set ether4 name=LAN-ADM


###############################################
# 2. CRIAR BRIDGES
###############################################
# Estrutura recomendada para expansão futura

/interface bridge

add name=bridge-alunos
add name=bridge-adm


###############################################
# 3. ADICIONAR PORTAS NAS BRIDGES
###############################################

/interface bridge port

add bridge=bridge-alunos interface=LAN-ALUNOS

add bridge=bridge-adm interface=LAN-ADM


###############################################
# 4. CONFIGURAÇÃO DOS LINKS PPPoE
###############################################
# Substituir usuário e senha

/interface pppoe-client

add name=pppoe-wan1 \
interface=WAN1 \
user=USUARIO_WAN1 \
password=SENHA_WAN1 \
disabled=no \
add-default-route=no

add name=pppoe-wan2 \
interface=WAN2 \
user=USUARIO_WAN2 \
password=SENHA_WAN2 \
disabled=no \
add-default-route=no


###############################################
# 5. CONFIGURAÇÃO DE IP DAS REDES
###############################################

/ip address

add address=10.7.0.1/22 \
interface=bridge-alunos \
comment="Gateway alunos"

add address=10.8.0.1/22 \
interface=bridge-adm \
comment="Gateway administrativo"


###############################################
# 6. DHCP POOLS
###############################################

/ip pool

add name=pool-alunos \
ranges=10.7.0.20-10.7.3.254

add name=pool-adm \
ranges=10.8.0.20-10.8.3.254


###############################################
# 7. DHCP SERVER
###############################################
# Cada rede possui DHCP próprio devido
# à ausência de VLANs na infraestrutura

/ip dhcp-server

add name=dhcp-alunos \
interface=bridge-alunos \
address-pool=pool-alunos \
disabled=no

add name=dhcp-adm \
interface=bridge-adm \
address-pool=pool-adm \
disabled=no


###############################################
# 8. REDES DHCP
###############################################

/ip dhcp-server network

add address=10.7.0.0/22 \
gateway=10.7.0.1 \
dns-server=1.1.1.1,8.8.8.8 \
comment="Rede alunos"

add address=10.8.0.0/22 \
gateway=10.8.0.1 \
dns-server=1.1.1.1,8.8.8.8 \
comment="Rede administrativa"


###############################################
# 9. ADDRESS LISTS
###############################################

/ip firewall address-list

add list=ADM-LAN \
address=10.8.0.0/22 \
comment="Rede administrativa"

add list=CLIENT-LAN \
address=10.7.0.0/22 \
comment="Rede alunos"

add list=GESTAO-REMOTA \
address=x.x.x.x/yy \
comment="IP autorizado acesso remoto"


###############################################
# 10. FIREWALL INPUT
###############################################
# Proteção do roteador

/ip firewall filter

# Permitir conexões estabelecidas
add chain=input \
action=accept \
connection-state=established,related \
comment="INPUT estabelecido"

# Permitir acesso administrativo
add chain=input \
action=accept \
src-address-list=ADM-LAN \
comment="INPUT administrativo"

# Permitir ICMP limitado
add chain=input \
action=accept \
protocol=icmp \
limit=50,5 \
comment="INPUT ICMP"

# Permitir acesso remoto
add chain=input \
action=accept \
protocol=tcp \
dst-port=<PORTA_CUSTOMIZADA> \
src-address-list=GESTAO-REMOTA \
comment="INPUT remoto"

# Bloquear restante
add chain=input \
action=drop \
comment="INPUT DROP"


###############################################
# 11. FIREWALL FORWARD
###############################################
# Controle entre redes internas

# Permitir conexões estabelecidas
add chain=forward \
action=accept \
connection-state=established,related \
comment="FORWARD estabelecido"

# ADM acessa ALUNOS
add chain=forward \
action=accept \
src-address-list=ADM-LAN \
dst-address-list=CLIENT-LAN \
comment="ADM -> ALUNOS"

# ALUNOS bloqueados da ADM
add chain=forward \
action=drop \
src-address-list=CLIENT-LAN \
dst-address-list=ADM-LAN \
comment="ALUNOS -> ADM BLOQUEADO"


###############################################
# 12. NAT
###############################################

/ip firewall nat

add chain=srcnat \
action=masquerade \
out-interface=pppoe-wan1 \
comment="NAT WAN1"

add chain=srcnat \
action=masquerade \
out-interface=pppoe-wan2 \
comment="NAT WAN2"


###############################################
# 13. FAILOVER
###############################################
# WAN1 principal
# WAN2 backup

/ip route

add dst-address=0.0.0.0/0 \
gateway=pppoe-wan1 \
distance=1 \
comment="WAN1"

add dst-address=0.0.0.0/0 \
gateway=pppoe-wan2 \
distance=2 \
comment="WAN2"


###############################################
# 14. MANGLE - PRIORIDADE ADM
###############################################

/ip firewall mangle

add chain=prerouting \
src-address-list=ADM-LAN \
connection-mark=no-mark \
action=mark-connection \
new-connection-mark=ADM-CONN \
passthrough=yes \
comment="ADM-CONN"

add chain=prerouting \
connection-mark=ADM-CONN \
action=mark-routing \
new-routing-mark=to-WAN1 \
passthrough=no \
comment="ADM-WAN1"


###############################################
# 15. PCC - LOAD BALANCE ALUNOS
###############################################

# WAN1
add chain=prerouting \
src-address-list=CLIENT-LAN \
connection-mark=no-mark \
per-connection-classifier=both-addresses:2/0 \
action=mark-connection \
new-connection-mark=WAN1-CONN \
passthrough=yes \
comment="PCC WAN1"

# WAN2
add chain=prerouting \
src-address-list=CLIENT-LAN \
connection-mark=no-mark \
per-connection-classifier=both-addresses:2/1 \
action=mark-connection \
new-connection-mark=WAN2-CONN \
passthrough=yes \
comment="PCC WAN2"

# Rotear WAN1
add chain=prerouting \
connection-mark=WAN1-CONN \
action=mark-routing \
new-routing-mark=to-WAN1 \
passthrough=no \
comment="ROTA WAN1"

# Rotear WAN2
add chain=prerouting \
connection-mark=WAN2-CONN \
action=mark-routing \
new-routing-mark=to-WAN2 \
passthrough=no \
comment="ROTA WAN2"


###############################################
# 16. ROTAS PCC
###############################################

/ip route

add dst-address=0.0.0.0/0 \
gateway=pppoe-wan1 \
routing-mark=to-WAN1 \
distance=1 \
comment="PCC WAN1"

add dst-address=0.0.0.0/0 \
gateway=pppoe-wan2 \
routing-mark=to-WAN2 \
distance=1 \
comment="PCC WAN2"


###############################################
# 17. SEGURANÇA DOS SERVIÇOS
###############################################

/ip service

set winbox port=<PORTA_CUSTOMIZADA>

set winbox address=<FAIXA_PERMITIDA>

set www-ssl address=<FAIXA_PERMITIDA>


###############################################
# 18. DNS
###############################################
# Recomendação:
# Sempre utilizar preferencialmente
# o DNS fornecido pelo seu provedor,
# evitando problemas de latência,
# cache e roteamento regional.

/ip dns

set servers=1.1.1.1,8.8.8.8 \
allow-remote-requests=yes


###############################################
# 19. BACKUP AUTOMÁTICO
###############################################
# Opcional

/system scheduler

add interval=1d \
name=backup-diario \
on-event="/system backup save name=backup-auto" \
start-time=03:00:00


###############################################
# 20. ROLLBACK
###############################################
# Usar apenas se necessário

# /ip firewall mangle disable [find]
# /ip firewall nat disable [find]
# /ip firewall filter disable [find]
# /ip route remove [find]
# /interface pppoe-client disable [find]


###############################################
# FIM DO SCRIPT
###############################################
