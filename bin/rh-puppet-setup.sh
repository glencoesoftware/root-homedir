#!/bin/bash
#
# $Id$

dist=${1:-el6}
puppet_confdir=${2:-"/etc/puppet"}
repo=${3:-"git://github.com/glencoesoftware"}

function check_for_puppet_repo() {
  if [ -e "/etc/yum.repos.d/puppetlabs.repo" ]; then
    yum_install_puppet
  else
    yum -y install http://yum.puppetlabs.com/el/${release}/products/${arch}/puppetlabs-release-6-6.noarch.rpm
    yum_install_puppet
  fi
}

function yum_install_puppet() {
  yum --enablerepo=puppetlabs* -y install puppetlabs-release puppet
}

function yum_install_git() {
  yum -y install git
}

function clone_config_repo() {
  if [ -d "${puppet_confdir}" ]; then
    if [ -d "${puppet_confdir}/.git" ]; then
      true
    else
      tar cvfz /tmp/puppet-configs.tar.gz $puppet_confdir && rm -rf $puppet_confdir
    fi
  fi
  yum_install_git
  if [ ! -d "${puppet_confdir}/.git" ]; then
    git clone ${repo}/puppet-configs.git $puppet_confdir
  fi
  cd $puppet_confdir && git submodule update --init --recursive
}

function install_puppet_cronjob() {
  puppet resource cron puppet-run-standalone ensure=present user=root minute='*/30' command="${puppet_confdir}/run-standalone"
}

arch=$(arch)
case $dist in
  el6)
    release=6
  ;;
  el5)
    release=5
  ;;
esac

clone_config_repo
check_for_puppet_repo
install_puppet_cronjob
