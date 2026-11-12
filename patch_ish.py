#!/usr/bin/env python3
"""把 iSH 的 rootfs 下载步骤换成本地的 root.tar.gz，并改 bundle 名。"""
import re, sys, pathlib

root = pathlib.Path(sys.argv[1])          # ish 源码目录
pbx = root / "iSH.xcodeproj" / "project.pbxproj"
s = pbx.read_text()

old = 'curl -L \\"https://$ROOTFS_URL\\" -o \\"$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/root.tar.gz\\"'
new = 'cp \\"$ROOTFS_SRC\\" \\"$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/root.tar.gz\\"'

n = s.count(old)
s = s.replace(old, new)
pbx.write_text(s)
print(f"patched {n} build phase(s)")

print("done")
