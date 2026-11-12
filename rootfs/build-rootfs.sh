#!/bin/sh
# 在 alpine:edge (x86_64) 容器里交叉装一个 32 位 x86 的 Alpine rootfs，
# 里面预装 node 24 + dsh，iSH 直接拿它当启动盘。
set -eu

ROOT=/rootfs
ALPINE_BRANCH=edge
MIRROR=https://dl-cdn.alpinelinux.org/alpine

rm -rf "$ROOT"
mkdir -p "$ROOT"

apk add --no-cache --arch x86 --root "$ROOT" --initdb --no-scripts -U \
  --repository "$MIRROR/$ALPINE_BRANCH/main" \
  --repository "$MIRROR/$ALPINE_BRANCH/community" \
  alpine-base nodejs npm bash curl ca-certificates tzdata shadow

cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
mkdir -p "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/tmp" "$ROOT/root"
chmod 1777 "$ROOT/tmp"

# chroot 里 node 要 /dev/urandom，容器默认有 CAP_MKNOD
[ -e "$ROOT/dev/null" ] || mknod -m 666 "$ROOT/dev/null" c 1 3
[ -e "$ROOT/dev/urandom" ] || mknod -m 666 "$ROOT/dev/urandom" c 1 9
[ -e "$ROOT/dev/random" ] || mknod -m 666 "$ROOT/dev/random" c 1 8
[ -e "$ROOT/dev/zero" ] || mknod -m 666 "$ROOT/dev/zero" c 1 5
[ -e "$ROOT/dev/tty" ] || mknod -m 666 "$ROOT/dev/tty" c 5 0

# 在 x86 内核的 IA32 兼容层下直接跑 32 位 musl
chroot "$ROOT" /bin/sh -eu -c '
  node -v
  npm -v
  mkdir -p /opt/dsh-app
  cd /opt/dsh-app
  echo "{\"name\":\"dsh-go\",\"private\":true}" > package.json
  npm i --ignore-engines --legacy-peer-deps --no-audit --no-fund @deepseek-ai/dsh@0.2.2-rc.1
  mkdir -p /opt/dsh-app/bin
  ln -sf /opt/dsh-app/node_modules/.bin/dsh /usr/local/bin/dsh
  dsh --version || true
'

# 启动脚本：起 dsh web（127.0.0.1:3080），再留一个 shell
cat > "$ROOT/opt/boot.sh" <<'EOF'
#!/bin/sh
export PATH=/opt/dsh-app/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
cd /root
if [ -z "$(pidof node 2>/dev/null)" ]; then
  (nohup dsh web --port 3080 > /var/log/dsh-web.log 2>&1 &) 
fi
exec /bin/sh -l
EOF
chmod +x "$ROOT/opt/boot.sh"

printf 'export PATH=/opt/dsh-app/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\nexport HOME=/root\n' > "$ROOT/etc/profile.d/dsh.sh"
chmod +x "$ROOT/etc/profile.d/dsh.sh"

# 清缓存，压包
rm -rf "$ROOT/root/.npm" "$ROOT/var/cache/apk"/* "$ROOT/tmp"/* 2>/dev/null || true
mkdir -p "$ROOT/tmp" && chmod 1777 "$ROOT/tmp"

cd "$ROOT"
tar --numeric-owner --owner=0 --group=0 -czf /out/root.tar.gz .
ls -lh /out/root.tar.gz
