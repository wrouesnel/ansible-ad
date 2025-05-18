#!/bin/bash
# /usr/local/sbin/create-local-homedir.sh

function log() {
  echo "$*"
}

# Log all output to syslog.
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

if [ $EUID -ne 0 ]; then
  exit 0
fi

PAM_UID=$(id -u "${PAM_USER}")
PAM_GID=$(id -g "${PAM_USER}")

if (( PAM_UID >= 1000 )); then
  log "Ensure the user has a cache directory"
  install -o "${PAM_UID}" -g "${PAM_GID}" -m 0700 -d "/var/cache/user/${PAM_USER}"

  user_home=$(bash -c "cd ~$(printf %q "$PAM_USER") && pwd")
  log "Ensure the user has a skeleton directory"
  while read -r dir; do
    if [ ! -e "${user_home}/${dir}" ]; then
      mkdir -p "${user_home}/${dir}"
      chown "${PAM_UID}:${PAM_GID}" "${user_home}/${dir}"
      chmod 751 "${user_home}/${dir}"
      restorecon "${user_home}/${fname}"
    fi
  done < <(find /etc/skel -mindepth 1 -type d -printf "%P\n")

  while read -r fname; do
    if [ ! -e "${user_home}/${fname}" ]; then
      cp -f "/etc/skel/${fname}" "${user_home}/${fname}"
      chown "${PAM_UID}:${PAM_GID}" "${user_home}/${fname}"
      chmod 640 "${user_home}/${dir}"
      restorecon "${user_home}/${fname}"
    fi
  done < <(find /etc/skel -mindepth 1 -type f -printf "%P\n")
fi

#if (( PAM_UID >= 1000 )); then
  #install -o "${PAM_UID}" -g "${PAM_GID}" -m 0700 -d "/var/lib/home/${PAM_USER}"
  # Cache should be local
  #install -o "${PAM_UID}" -g "${PAM_GID}" -m 0700 -d "/var/lib/home/${PAM_USER}/.cache"

  # Application Specific Overrides
  # TODO: consider some of these - they reduce overhead, but are they convenient? Python in particular doesn't seem
  # useful.
  # export PYTHONUSERBASE="/usr/local/home/${USER}/.local"  # python
  # export npm_config_cache="/usr/local/home/${USER}/.npm"  # nodejs
  # export CARGO_HOME="/usr/local/home/${USER}/.cargo"      # rust
  # export GOPATH="/usr/local/home/${USER}/go"              # golang

  # Podman
  #install -o "${PAM_UID}" -g "${PAM_GID}" -m 0700 -d "/var/lib/home/${PAM_USER}/.local/share/containers"

  # Flatpak workaround (https://www.sacredheartsc.com/blog/desktop-linux-with-nfs-homedirs/)
  # Note: bind-mounting $HOME/.var to /opt/flatpak/${PAM_USER} will be necessary.
  #install -o "${PAM_USER}" -g "${PAM_USER}" -m 0700 -d "/opt/flatpak/${PAM_USER}"
#fi