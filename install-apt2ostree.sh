#!/usr/bin/env bash
set -e

APT2OSTREE_DIR=/opt/apt2ostree
GOPATH_DIR=/opt/go
APTLY_DIR=$GOPATH_DIR/src/github.com/aptly-dev/aptly

if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

apt update
apt install -y \
  git \
  python3 \
  golang-go \
  make \
  ninja-build \
  ostree \
  bubblewrap \
  ca-certificates

mkdir -p /opt /usr/local/bin "$GOPATH_DIR/src/github.com/aptly-dev"

if [ -L "$APTLY_DIR" ]; then
  rm -f "$APTLY_DIR"
fi

if [ ! -d "$APTLY_DIR/.git" ]; then
  git clone https://github.com/stb-tester/aptly.git "$APTLY_DIR"
fi

cd "$APTLY_DIR"
git fetch
git checkout lockfile
git pull --ff-only origin lockfile

export GOPATH="$GOPATH_DIR"
export GO111MODULE=off
make install

ln -sf "$GOPATH_DIR/bin/aptly" /usr/local/bin/aptly

if [ ! -d "$APT2OSTREE_DIR/.git" ]; then
  git clone https://github.com/stb-tester/apt2ostree.git "$APT2OSTREE_DIR"
fi

cd "$APT2OSTREE_DIR"
git fetch
git checkout master
git pull --ff-only origin master

for f in apt2ostree/apt.py apt2ostree/ninja.py; do
  if grep -q '^import pipes$' "$f"; then
    sed -i 's/^import pipes$/try:\n    import pipes\nexcept ModuleNotFoundError:\n    import shlex as pipes/' "$f"
  fi
done

python3 - "$APT2OSTREE_DIR/apt2ostree/ostree.py" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

old = """    tmpdir=$$(mktemp -dt ostree_adddir.XXXXXX);
    cp $in_file $$tmpdir;
    ostree --repo=$ostree_repo commit --devino-canonical -b $out_branch
           --no-bindings --orphan --timestamp=0
           --tree=ref=$in_branch
           --tree=prefix=$prefix --tree=dir=$$tmpdir
           --owner-uid=0 --owner-gid=0;
    rm -rf $$tmpdir;
"""

new = """    tmpdir=$$(mktemp -dt ostree_adddir.XXXXXX);
    rootdir=$$tmpdir/root;
    ostree --repo=$ostree_repo checkout -UH $in_branch $$rootdir;
    mkdir -p $$rootdir/$prefix;
    cp $in_file $$rootdir/$prefix/;
    ostree --repo=$ostree_repo commit --devino-canonical -b $out_branch
           --no-bindings --orphan --timestamp=0
           --tree=dir=$$rootdir
           --owner-uid=0 --owner-gid=0;
    rm -rf $$tmpdir;
"""

if old in text:
    text = text.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
PY

cat > /etc/profile.d/apt2ostree.sh <<EOF
export PYTHONPATH="$APT2OSTREE_DIR:\${PYTHONPATH:-}"
export PATH="/usr/local/bin:$GOPATH_DIR/bin:\$PATH"
EOF

export PYTHONPATH="$APT2OSTREE_DIR:${PYTHONPATH:-}"
export PATH="/usr/local/bin:$GOPATH_DIR/bin:$PATH"

python3 -c "import apt2ostree; print('apt2ostree ok')"
aptly version
ninja --version
ostree --version

echo "apt2ostree installed in $APT2OSTREE_DIR"
