#!/bin/bash

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
  --ldapserver=ldap.glencoesoftware.com \
  --enableldaptls \
  --ldapbasedn='dc=glencoesoftware,dc=com' \
  --enablelocauthorize \
  --enablepamaccess \
  --enablemkhomedir \
  --disablecache \
  --enableldapstarttls \
  --ldaploadcacert=http://sloth.glencoesoftware.com/bootstrap-helpers/ldap-cert.pem \
  --updateall

# setup access.conf
echo '+:glencoe:ALL' >> /etc/security/access.conf
echo '-:ALL EXCEPT root:ALL' >> /etc/security/access.conf
