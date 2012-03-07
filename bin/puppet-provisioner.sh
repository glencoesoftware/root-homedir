#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage $0 [none,master,masterless,client]"
  echo "  none: no puppet setup"
  echo "  master: puppet master (set PUPPET_MASTER to ip of external master, leave blank to use self)"
  echo "  masterless: masterless puppetmaster"
  echo "  client: puppet client (set PUPPET_MASTER to ip of master)"
  exit 1
fi

PUPPET_ENV=${1:-none}

(

function set_hostname() {
  case $DISTRO in
    rhel|fedora|centos)
      echo "HOSTNAME=${U_HOSTNAME}" >> /etc/sysconfig/network
      ;;
    debian|ubuntu)
      echo ${U_HOSTNAME} > /etc/hostname
      ;;
    *)
      ;;
  esac
  hostname ${U_HOSTNAME}
}

function puppet_config_repo() {
  # move existing puppet configs away
  # clone our config repo and initialize any submodules
  tar cvfz /tmp/puppet-rpm-configs.tar.gz /etc/puppet && rm -vrf /etc/puppet
  git clone git://github.com/glencoesoftware/puppet-configs /etc/puppet
  ( cd /etc/puppet && git submodule update --init --recursive )
}

function puppet_external_modules() {
  gem install puppet-module --no-ri --no-rdoc
  # install puppetlabs-stdlib puppet module and hiera data backend
  (
    cd $(puppet --configprint modulepath | awk -F: '{ print $2 }') &&
    (
      puppet-module install puppetlabs-stdlib
      puppet-module install hunner-hiera
    )
  )
}

function puppet_set_roles() {
  # set our server_tags in /etc/server_roles
  for role in $PUPPET_ROLES; do
    echo $role >> /etc/server_roles
  done
}

function external_puppet_master() {
  # setup config
  puppet_config_repo
  # set roles
  puppet_set_roles
  # set hosts alias for puppetmaster
  puppet --color=false resource host puppet ip=$PUPPET_MASTER 
  # run puppet once to get cert
  puppet --color=false agent --waitforcert 2 --no-daemonize --verbose --onetime
  # service and start
  chkconfig puppet on && service puppet start
}

function masterless_puppet() {
  # setup config
  puppet_config_repo
  # modules
  puppet_external_modules
  # set roles
  puppet_set_roles
  # run once
  puppet --color=false apply --logdest syslog --verbose /etc/puppet/manifests/site.pp
  # cron run in
  puppet --color=false resource cron puppetrun command='puppet apply --logdest syslog /etc/puppet/manifests/site.pp' minute='*/30'
}

function self_puppet_master() {
  # install basic puppet server
  puppet resource package puppet-server ensure=installed
  # since we are master we talk to ourselves, always
  perl -p -i -e 's/$/ puppet/ if /^127.0.0.1/' /etc/hosts
  # standard config
  puppet_config_repo
  # external modules
  puppet_external_modules
  # set roles
  puppet_set_roles
  # start puppetmaster and run agent against ourselves
  /sbin/service puppetmaster start
  puppet agent --test --color=false |tee /var/log/puppet_agent.log
  chkconfig puppetmaster on
  service puppetmaster start
}

function determine_distro() {
  if [ -f "/etc/centos-release" ]; then
    DISTRO="centos"
  elif [ -f "/etc/fedora-release" ]; then
    DISTRO="fedora"
  elif [ -f "/etc/redhat-release" ]; then
    DISTRO="rhel"
  else
    if [ -e "/etc/lsb-release" ]; then
      dist_try=$(cat /etc/lsb-release |tr A-Z a-z)
      case $dist_try in
        *ubuntu*)
          DISTRO="ubuntu"
          ;;
        *debian*)
          DISTRO="ubuntu"
          ;;
        *gentoo*)
          DISTRO="gentoo"
          ;;
        *)
          DISTRO="unsupported"
          ;;
      esac
    elif [ -e "/etc/system-release" ]; then
      dist_try=$(cat /etc/lsb-release |tr A-Z a-z)
      case $dist_try in
        *)
          echo "/etc/system-release not supported"
          ;;
      esac
    else
      echo "/etc/*-release does not exist"
      exit 1
    fi
  fi

}

function puppet_rpm() {
  if (rpm -q puppetlabs-release &> /dev/null); then
    yum --color=never -y --quiet update puppetlabs-release
  else
    # for fedora assume rhel5-ish
    if [ -f /etc/fedora-release ]; then
      yum --color=never -y --quiet install http://yum.puppetlabs.com/el/5/products/x86_64/puppetlabs-release-5-1.noarch.rpm
    else
      yum --color=never -y --quiet install http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-1.noarch.rpm
    fi
  fi

  yum --color=never -y --quiet install puppet facter rubygems

  # fix broken linode virtualization detection
  release=$( uname -r )
  case $release in
    *-linode*)
      echo 'export FACTER_virtual=virtual' > /etc/profile.d/linode.sh
      echo 'setenv FACTER_virtual virtual' > /etc/profile.d/linode.csh
      ;;
    *)
      ;;
  esac

  case $PUPPET_ENV in
    masterless)
      masterless_puppet
      ;;
    client)
      external_puppet_master
      ;;
    master)
      self_puppet_master
      ;;
    *)
      ;;
  esac

}

function puppet_apt() {
  # add puppetlabs apt repo
  echo "deb http://apt.puppetlabs.com/$DISTRO ${version} main" >> /etc/apt/sources.list
  echo "deb-src http://apt.puppetlabs.com/$DISTRO ${version} main" >> /etc/apt/sources.list
  # import gpgkey
  gpg --recv-keys 4BD6EC30
  gpg -a --export 4BD6EC30 | sudo apt-key add -
  # update repo list
  apt-get update
  if (dpkg -l puppet &> /dev/null); then
    apt-get upgrade puppet facter rubygems
  else
    apt-get install puppet facter rubygems
  fi
}

function bootstrap_rpm() {
  if (rpm -q redhat-release &> /dev/null); then
    release_package='redhat-release'
  elif (rpm -q centos-release &> /dev/null); then
    release_package='centos-release'
  else
    echo "unsupported rpm based distro"
    exit 1
  fi
  os_version=$(rpm -q --queryformat="%{VERSION}" $release_package)
  case $os_version in
    6)
      yum --color=never -y --quiet install --nogpgcheck http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-5.noarch.rpm
    ;;
    5)
      yum --color=never -y --quiet install --nogpgcheck install http://dl.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm
    ;;
    *)
      echo "unsupported distro version $os_version for $DISTRO"
      exit 1
    ;;
  esac

  # install 'extra' packages
  yum --color=never -y --quiet install bash-completion lsof git-core screen
  yum --color=never -y --quiet install yum-plugin-protect-packages yum-plugin-security yum-plugin-verify yum-plugin-versionlock yum-plugin-ps

  # prompt commands for screen
  echo 'echo -ne "\033k${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/~}\033\\";history -a' >> /etc/sysconfig/bash-prompt-screen
  chmod +x /etc/sysconfig/bash-prompt-screen

  # setup puppet
  case $PUPPET_ENV in
    none|'')
      ;;
    *)
      puppet_rpm
      ;;
  esac

}

function bootstrap_apt() {
  echo "not yet implemented"
}

[[ -z "$PUPPET_ENV" ]] && echo "Missing PUPPET_ENV (master, client, masterless, none)" && DIE=$(( $DIE + 1 ))
[[ "$DIE" -gt 0 ]] && exit 1

determine_distro
[[ -n "$U_HOSTNAME" ]] && set_hostname

case $DISTRO in
  centos|rhel)
    bootstrap_rpm
  ;;
  ubuntu|debian)
    bootstrap_apt
  ;;
  gentoo)
  ;;
  *)
    echo "Distro not supported!!"
    exit 1
  ;;
esac


) 2>&1 | tee /tmp/stack-script.log
