# See: https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
# Note: you can't refactor this out: its at the top of every script so the scripts can find their includes.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

source include.sh

requires=(
    "uv"
)

check_requirements "${requires[@]}"

# TODO
#index_url="$(pip config --global get global.index-url 2>/dev/null)"
#if [ ! -z "$index_url" ]; then
#    log "Alternate default source found - setting as default for Poetry"
#    if ! poetry source add --priority=default public-pypi "$index_url" ; then
#        fatal 1 "Failed to set alternate default source."
#    fi
#fi

log "Installing project dependencies"
if ! uv sync ; then
    fatal 1 "uv failed to install dependencies"
fi
