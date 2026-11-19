# shellcheck shell=sh
# Helpers for vcs.test: source this, then call newrepo.
# Isolates git and jj from the user's and system's configuration (hooks, signing, auto-track settings),
# and sets an author, so commits work the same everywhere.

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export JJ_USER=test JJ_EMAIL=test@example.com

# newrepo git|jj|none: make and enter a new temporary directory, with a repository of that kind.
# The directory is removed when the shell exits.
newrepo() {
  D=$(mktemp -d "${TMPDIR:-/tmp}/hledger-vcs.XXXXXX")
  JJ_CONFIG=$(mktemp "${TMPDIR:-/tmp}/hledger-vcs-jjconfig.XXXXXX")
  export JJ_CONFIG
  trap 'rm -rf "$D" "$JJ_CONFIG"' EXIT
  cd "$D" || exit 1
  case "$1" in
    git) git init -q ;;
    jj)  jj git init --colocate >/dev/null 2>&1 ;;
  esac
}

# Is jj installed ?
hasjj() { command -v jj >/dev/null 2>&1; }

# Show the commit messages, most recent first.
gitlog() { git log --format=%s; }
jjlog()  { jj log --no-graph -r '::@-' -T 'description.first_line() ++ "\n"' | grep -v '^$'; }
