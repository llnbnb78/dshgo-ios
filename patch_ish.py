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


# 开机命令换成我们的启动脚本
ad = root / "app" / "AppDelegate.m"
t = ad.read_text()
old_cmd = "command = UserPreferences.shared.bootCommand;"
new_cmd = 'command = @[@"/bin/sh", @"/opt/boot.sh"];'
if old_cmd in t:
    t = t.replace(old_cmd, new_cmd)
    ad.write_text(t)
    print("boot command patched")


# 把 WebView 控制器拷进 app/ 并改 SceneDelegate 的入口
import shutil
here = pathlib.Path(__file__).parent
for f in ["DSHWebViewController.h", "DSHWebViewController.m"]:
    shutil.copy(here / "patch" / f, root / "app" / f)

sd = root / "app" / "SceneDelegate.m"
t = sd.read_text()
if "#import \"DSHWebViewController.h\"" not in t:
    t = t.replace('#import "SceneDelegate.h"', '#import "SceneDelegate.h"\n#import "DSHWebViewController.h"', 1)
wrap = """
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        static BOOL dshShown = NO;
        if (dshShown || vc.view.window == nil) return;
        dshShown = YES;
        DSHWebViewController *web = [DSHWebViewController new];
        web.modalPresentationStyle = UIModalPresentationFullScreen;
        [vc presentViewController:web animated:NO completion:nil];
    });
"""
if "DSHWebViewController *web" not in t:
    t = t.replace("        [vc startNewSession];", "        [vc startNewSession];\n" + wrap, 1)
sd.write_text(t)
print("scene delegate patched")

print("done")
