#!/bin/bash
LDAP_SERVER=${1:-ldap.glencoesoftware.com}
LDAP_CERT_PATH=${2:-http://sloth.glencoesoftware.com/bootstrap-helpers/ldap-cert.pem}

# install 'extra' packages
yum --color=never -y --quiet install bash-completion lsof git-core screen
yum --color=never -y --quiet install yum-plugin-protect-packages yum-plugin-security yum-plugin-verify yum-plugin-versionlock yum-plugin-ps
yum --color=never -y --quiet install pam_ldap authconfig nss-pam-ldapd

# prompt commands for screen
# echo 'echo -ne "\033k${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/~}\033\\";history -a' >> /etc/sysconfig/bash-prompt-screen
# chmod +x /etc/sysconfig/bash-prompt-screen

# setup authentication
authconfig \
  --enableldapauth \
  --enableshadow \
  --enablemd5 \
  --enableldap \
  --ldapserver=${LDAP_SERVER} \
  --enableldaptls \
  --ldapbasedn='dc=glencoesoftware,dc=com' \
  --enablelocauthorize \
  --enablepamaccess \
  --enablemkhomedir \
  --disablecache \
  --enableldapstarttls \
  --ldaploadcacert=${LDAP_CERT_PATH} \
  --updateall

# setup access.conf
echo '+:glencoe:ALL' >> /etc/security/access.conf
echo '-:ALL EXCEPT root:ALL' >> /etc/security/access.conf
