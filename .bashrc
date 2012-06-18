# .bashrc

# User specific aliases and functions

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# better vim
if (which vim &> /dev/null); then
  alias vi=vim
fi

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi
