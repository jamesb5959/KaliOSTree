#!/usr/bin/env bash
set -e

APT2OSTREE_DIR=/opt/apt2ostree
GOPATH_DIR=/opt/go
RESULTS=/mnt/hostshare/apt2ostree-test-results
WORK=/tmp/apt2ostree-nginx-example

export PYTHONPATH="$APT2OSTREE_DIR:${PYTHONPATH:-}"
export PATH="/usr/local/bin:$GOPATH_DIR/bin:$PATH"

mkdir -p "$RESULTS"

run_test() {
  name="$1"
  shift

  echo "[*] $name"
  if "$@" > "$RESULTS/$name.out" 2> "$RESULTS/$name.err"; then
    echo "pass" > "$RESULTS/$name.status"
  else
    echo "fail" > "$RESULTS/$name.status"
    echo "[!] failed: $name"
    return 1
  fi
}

if [ ! -d "$APT2OSTREE_DIR/examples/nginx" ]; then
  echo "apt2ostree not found. Run install script first:"
  echo "sudo bash /mnt/hostshare/install-apt2ostree.sh"
  exit 1
fi

run_test python-import python3 -c "import apt2ostree; print(apt2ostree.__file__)"
run_test aptly-version aptly version
run_test ninja-version ninja --version
run_test ostree-version ostree --version

rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$APT2OSTREE_DIR/examples/nginx/." "$WORK/"
sed -i 's/ubuntu_apt_sources("xenial")/ubuntu_apt_sources("22.04")[:1]/' "$WORK/configure.py"
sed -i "s|sys.path.append(os.path.dirname(__file__) + '/../..')|sys.path.insert(0, '$APT2OSTREE_DIR')|" "$WORK/configure.py"

cd "$WORK"
mkdir -p _build/ostree

run_test ostree-init ostree init --mode=bare-user --repo=_build/ostree
run_test configure python3 ./configure.py
run_test update-apt-lockfiles ninja update-apt-lockfiles
run_test ninja-dry-run ninja -n

echo
echo "Smoke test done."
echo "Results saved in: $RESULTS"
echo
echo "To try the full build:"
echo "cd $WORK"
echo "ninja"
