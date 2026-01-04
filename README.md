如果您想让它立即下载最新APK，可以使用以下方法：
git clone https://github.com/Gundamx682/meishi.git
cd meishi

sudo bash install-new.sh

  🔄 方法1：重启下载服务（推荐）
   1 # 立即重启服务，触发一次下载检查
   2 sudo systemctl restart apk-downloader

  🔄 方法2：手动触发下载
   1 # 手动运行下载脚本一次
   2 sudo /opt/apk-downloader/apk-downloader.sh

  🔄 方法3：使用我们之前创建的下载脚本
   1 # 直接下载最新APK到当前目录
   2 curl -fsSL https://raw.githubusercontent.com/Gundamx682/meishi/main/download_latest_apk.sh | bash

  📊 方法4：检查当前状态
   1 # 查看下载目录中的APK文件
   2 ls -la /var/www/apk-downloads/
   3
   4 # 查看下载服务日志
   5 journalctl -u apk-downloader -f

✦ 推荐使用方法1，重启服务后它会立即执行一次下载检查，然后继续按10分钟间隔自动检查。


   1 # 首先下载脚本到本地
   2 curl -fsSL https://raw.githubusercontent.com/Gundamx682/meishi/main/install.sh -o install.sh
   3
   4 # 然后直接运行脚本（这样可以读取输入）
   5 sudo bash install.sh
