#!/bin/bash
# See: https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
# Note: you can't refactor this out: its at the top of every script so the scripts can find their includes.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

source "${SCRIPT_DIR}/include.sh"
source "${SCRIPT_DIR}/activate"

pushd "${SCRIPT_DIR}" 1> /dev/null || exit 1

# These need to be here so Kerberos authentication to synthetic windows clusters will work.
export KRB5_CONFIG="${SCRIPT_DIR}/krb5.conf"
export KRB5_KDC_PROFILE=/dev/null

ansible-playbook "$@"
result=$?

exit $result