#!/bin/sh
# 在 i386/alpine 容器里组装 rootfs：装 node24 + dsh，然后把自己打包。
set -eu

apk add --no-cache alpine-base nodejs npm bash curl ca-certificates tzdata

node -v
npm -v

mkdir -p /opt/dsh-app
cd /opt/dsh-app
echo '{"name":"dsh-go","private":true}' > package.json

npm config set registry https://registry.npmmirror.com
npm i --no-audit --no-fund @deepseek-ai/dsh@0.2.2-rc.1

mkdir -p /usr/local/bin
ln -sf /opt/dsh-app/node_modules/.bin/dsh /usr/local/bin/dsh
/opt/dsh-app/node_modules/.bin/dsh --version || true

cat > /opt/boot.sh <<'EOF'
#!/bin/sh
export PATH=/opt/dsh-app/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
cd /root
( nohup dsh web --port 3080 > /var/log/dsh-web.log 2>&1 & )
sleep 1
exec /bin/sh -l
EOF
chmod +x /opt/boot.sh

mkdir -p /etc/profile.d
printf 'export PATH=/opt/dsh-app/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\nexport HOME=/root\n' > /etc/profile.d/dsh.sh
chmod +x /etc/profile.d/dsh.sh

rm -rf /root/.npm /var/cache/apk/* /tmp/* 2>/dev/null || true
mkdir -p /tmp && chmod 1777 /tmp

cd /
set +e
tar --numeric-owner -czf /w/root.tar.gz \
  --exclude=./w --exclude=./proc --exclude=./sys --exclude=./dev -C / . 
rc=$?
echo "tar rc=$rc"
ls -lh /w/root.tar.gz || true
tar tzf /w/root.tar.gz 2>/dev/null | head -5
exit $rc
