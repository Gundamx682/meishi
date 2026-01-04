# 项目概述

## 项目名称
meishi - APK自动下载和分发服务（支持多仓库）

## 项目目的
这是一个用于自动监控多个GitHub仓库并下载最新APK文件的自动化服务系统。系统会定期检查指定的GitHub Release仓库，自动下载最新的APK文件到独立目录，并通过HTTP服务器提供下载服务。同时包含一个Android客户端应用，用于自动下载APK到设备。

## 核心功能
- **多仓库监控**：同时监控多个GitHub仓库，每个仓库独立下载目录
- **自动下载服务**：每10分钟自动检查所有GitHub仓库的最新Release版本
- **HTTP下载服务器**：提供统一的Web界面，显示所有仓库的最新APK
- **Android客户端**：提供APK下载器应用，自动下载APK到设备
- **GitHub Token认证**：支持GitHub Personal Access Token以绕过API速率限制
- **自动清理**：每个仓库只保留最新的3个APK文件，自动清理旧版本
- **systemd服务管理**：使用systemd管理后台服务，支持自动重启

## 当前监控的仓库
- **NetaMade**：z0brk/netamade-releases
- **Neta Vehicle**：netcookies/Neta-Vehicle

## 技术栈
- **编程语言**：Bash脚本、Python 3、Java (Android)
- **Web服务器**：Python http.server (BaseHTTPRequestHandler)
- **服务管理**：systemd
- **目标系统**：CentOS 7/8/9、RHEL、Android 5.0+
- **依赖工具**：curl、python3、systemctl、Gradle

## 架构说明

### 核心组件

1. **apk-downloader.sh** - APK下载守护进程
   - 监控GitHub仓库：`z0brk/netamade-releases` 和 `netcookies/Neta-Vehicle`
   - 每10分钟检查一次最新Release
   - 自动下载APK文件到 `/var/www/apk-downloads/`
   - 记录日志到 `/var/log/apk-downloader.log`
   - 支持GitHub Token认证

2. **apk-server.py** - HTTP下载服务器
   - 监听端口：8080
   - 提供Web界面：`http://45.130.146.21:8080`
   - 直接下载链接：`http://45.130.146.21:8080/xiazai/{repo_name}`
   - 自动识别最新的APK文件
   - 记录日志到 `/var/log/apk-server.log`

3. **install.sh** - 一键安装脚本
   - 自动检测系统环境
   - 交互式配置GitHub Token
   - 部署所有脚本和服务
   - 配置防火墙和systemd服务

4. **download_latest_apk.sh** - 手动下载脚本
   - 用于一次性下载最新APK
   - 适用于临时需求或测试

5. **APKDOO/** - Android客户端项目
   - Android应用：APK下载器
   - 自动从服务器下载APK到设备
   - 支持Android 5.0+
   - 使用Gradle构建

### 目录结构
```
/opt/apk-downloader/          # 主程序目录
  ├── apk-downloader.sh       # 下载守护进程
  └── apk-server.py           # HTTP服务器

/var/www/apk-downloads/       # APK文件存储基础目录
  ├── netamade/               # NetaMade仓库的APK文件
  └── vehicle/                # Neta Vehicle仓库的APK文件

APKDOO/                       # Android客户端项目
  ├── app/                    # 应用源码
  ├── build.gradle            # 构建配置
  ├── gradlew                 # Gradle包装器
  └── README.md               # 项目说明

/etc/systemd/system/          # systemd服务配置
  ├── apk-downloader.service  # 下载服务
  └── apk-server.service      # HTTP服务

/var/log/                     # 日志目录
  ├── apk-downloader.log      # 下载服务日志
  └── apk-server.log          # HTTP服务日志
```

## 安装和部署

### 一键安装服务端
```bash
# 下载安装脚本
curl -fsSL https://raw.githubusercontent.com/Gundamx682/meishi/main/install.sh -o install.sh

# 运行安装脚本（需要root权限）
sudo bash install.sh
```

安装过程中需要输入GitHub Personal Access Token以绕过API速率限制。

### 手动部署服务端
如果需要手动部署，请按以下步骤操作：

1. **创建目录结构**
```bash
sudo mkdir -p /opt/apk-downloader
sudo mkdir -p /var/www/apk-downloads
```

2. **部署脚本文件**
```bash
# 复制脚本到目标目录
sudo cp apk-downloader.sh /opt/apk-downloader/
sudo cp apk-server.py /opt/apk-downloader/
sudo chmod +x /opt/apk-downloader/apk-downloader.sh
sudo chmod +x /opt/apk-downloader/apk-server.py
```

3. **配置systemd服务**
```bash
# 复制服务配置文件
sudo cp apk-downloader.service /etc/systemd/system/
sudo cp apk-server.service /etc/systemd/system/

# 重新加载systemd
sudo systemctl daemon-reload

# 启用服务
sudo systemctl enable apk-downloader
sudo systemctl enable apk-server
```

4. **启动服务**
```bash
sudo systemctl start apk-downloader
sudo systemctl start apk-server
```

5. **配置防火墙**
```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

## Android客户端构建

### 项目信息
- **应用名称**: APK下载器
- **包名**: com.netamade.apkdownloader
- **最低版本**: Android 5.0 (API 21)
- **目标版本**: Android 14 (API 34)
- **构建工具**: Gradle

### 方法1: 使用Gradle命令行构建

#### Windows系统
```bash
cd APKDOO
gradlew.bat assembleDebug
```

#### Linux/Mac系统
```bash
cd APKDOO
chmod +x gradlew
./gradlew assembleDebug
```

**APK输出位置**: `APKDOO/app/build/outputs/apk/debug/app-debug.apk`

### 方法2: 使用Android Studio构建

1. 打开Android Studio
2. 选择 "Open" 并选择 `APKDOO` 目录
3. 等待Gradle同步完成
4. 点击菜单: **Build > Build Bundle(s) / APK(s) > Build APK(s)**
5. 构建完成后，点击通知中的 "locate" 查看APK位置

### 方法3: 使用GitHub Actions自动构建

本项目已配置GitHub Actions，可以自动编译APK。

1. 访问项目的 **Actions** 页面
2. 选择最近的构建任务
3. 在底部 **Artifacts** 区域下载:
   - `APK-Debug` - 调试版本(用于测试)
   - `APK-Release` - 正式版本

### 构建配置修改

如需修改下载地址或保存目录，编辑:
`APKDOO/app/src/main/java/com/netamade/apkdownloader/MainActivity.java`

```java
// 下载地址
private static final String DOWNLOAD_URL = "http://45.130.146.21:8080/xiazai";

// 保存目录
private static final String BASE_DIR = "/storage/emulated/0/Netamade/APK";
```

### Android客户端功能
- ✅ 自动从指定服务器下载APK
- ✅ 保存到 `/storage/emulated/0/Netamade/APK` 目录
- ✅ 实时显示下载进度
- ✅ 下载完成后自动关闭应用
- ✅ 自动请求存储权限(支持Android 11+)

## 服务管理

### 查看服务状态
```bash
# 查看下载服务状态
sudo systemctl status apk-downloader

# 查看HTTP服务状态
sudo systemctl status apk-server
```

### 重启服务
```bash
# 重启所有服务
sudo systemctl restart apk-downloader apk-server

# 单独重启下载服务
sudo systemctl restart apk-downloader

# 单独重启HTTP服务
sudo systemctl restart apk-server
```

### 查看日志
```bash
# 实时查看下载服务日志
sudo journalctl -u apk-downloader -f

# 实时查看HTTP服务日志
sudo journalctl -u apk-server -f

# 查看文件日志
sudo tail -f /var/log/apk-downloader.log
sudo tail -f /var/log/apk-server.log
```

### 停止服务
```bash
sudo systemctl stop apk-downloader apk-server
```

## 使用方法

### 下载APK

**方法1：通过Web界面**
1. 访问 `http://45.130.146.21:8080`
2. 在页面中选择要下载的应用
3. 点击对应的"立即下载"按钮

**方法2：直接下载链接**
```bash
# 下载NetaMade最新版本
curl -O http://45.130.146.21:8080/xiazai/netamade

# 下载Neta Vehicle最新版本
curl -O http://45.130.146.21:8080/xiazai/vehicle
```

**方法3：使用Android客户端**
1. 构建Android客户端APK（见上方构建说明）
2. 安装到Android设备
3. 打开应用，授予权限
4. 应用自动下载APK到设备

**方法4：手动触发下载**
```bash
# 重启下载服务，触发立即检查所有仓库
sudo systemctl restart apk-downloader

# 或手动运行下载脚本
sudo /opt/apk-downloader/apk-downloader.sh
```

**方法5：使用下载脚本**
```bash
# 下载最新APK到当前目录（仅支持单个仓库）
curl -fsSL https://raw.githubusercontent.com/Gundamx682/meishi/main/download_latest_apk.sh | bash
```

### 检查APK文件
```bash
# 查看所有仓库的APK文件
ls -la /var/www/apk-downloads/

# 查看NetaMade仓库的APK
ls -la /var/www/apk-downloads/netamade/

# 查看Neta Vehicle仓库的APK
ls -la /var/www/apk-downloads/vehicle/

# 查看最新的APK
ls -lt /var/www/apk-downloads/*/ | head -n 10
```

## 配置说明

### GitHub Token配置
GitHub Token用于绕过API速率限制。配置方法：

1. 访问 https://github.com/settings/tokens
2. 点击 "Generate new token"
3. 选择权限（至少需要 `public_repo`）
4. 生成并复制Token
5. 运行安装脚本时输入Token

Token会被保存到 `/etc/profile`：
```bash
export GITHUB_TOKEN="your_token_here"
```

### 添加新仓库
编辑 `/opt/apk-downloader/apk-downloader.sh`，在 `REPOS` 关联数组中添加新仓库：
```bash
declare -A REPOS=(
    ["netamade"]="z0brk/netamade-releases"
    ["vehicle"]="netcookies/Neta-Vehicle"
    ["newrepo"]="owner/new-repo-name"  # 添加新仓库
)
```

同时编辑 `/opt/apk-downloader/apk-server.py`，在 `repos` 字典中添加新仓库信息：
```python
self.repos = {
    'netamade': {
        'name': 'NetaMade',
        'path': 'z0brk/netamade-releases'
    },
    'vehicle': {
        'name': 'Neta Vehicle',
        'path': 'netcookies/Neta-Vehicle'
    },
    'newrepo': {  # 添加新仓库
        'name': '显示名称',
        'path': 'owner/new-repo-name'
    }
}
```

修改完成后，重启服务：
```bash
sudo systemctl restart apk-downloader apk-server
```

### 修改检查间隔
编辑 `/opt/apk-downloader/apk-downloader.sh`：
```bash
CHECK_INTERVAL=600  # 单位：秒，默认600秒（10分钟）
```

### 修改服务器端口
编辑 `/opt/apk-downloader/apk-server.py`：
```python
server_address = ('0.0.0.0', 8080)  # 修改端口
```

同时更新防火墙规则：
```bash
sudo firewall-cmd --permanent --add-port=新端口/tcp
sudo firewall-cmd --reload
```

## 开发和调试

### 测试下载功能
```bash
# 手动运行下载脚本测试
sudo /opt/apk-downloader/apk-downloader.sh
```

### 测试HTTP服务器
```bash
# 直接运行HTTP服务器
sudo python3 /opt/apk-downloader/apk-server.py

# 访问测试
curl http://localhost:8080
curl http://localhost:8080/xiazai
```

### 验证URL引用
```bash
# 检查GitHub仓库中的文件引用是否正确
bash check_urls.sh
```

### Android客户端调试

**查看构建日志**
```bash
cd APKDOO
./gradlew assembleDebug --info
```

**清理构建缓存**
```bash
cd APKDOO
./gradlew clean
```

**常见问题**
- 构建失败：检查Actions日志查看具体错误
- APK无法安装：确保启用"未知来源应用"
- 下载失败：检查网络连接和服务器地址
- 权限问题：确保授予存储权限

### 常见问题

**问题1：下载失败，提示API速率限制**
- 解决：配置GitHub Token（见上方配置说明）

**问题2：服务无法启动**
- 检查日志：`sudo journalctl -u apk-downloader -n 50`
- 检查权限：确保脚本有执行权限
- 检查依赖：确保已安装curl和python3

**问题3：无法访问Web界面**
- 检查防火墙：`sudo firewall-cmd --list-all`
- 检查服务状态：`sudo systemctl status apk-server`
- 检查端口：`sudo netstat -tlnp | grep 8080`

**问题4：APK文件未更新**
- 检查仓库是否有新Release
- 查看下载日志：`sudo tail -f /var/log/apk-downloader.log`
- 手动触发：`sudo systemctl restart apk-downloader`

**问题5：Android客户端无法连接**
- 检查服务器是否运行：`sudo systemctl status apk-server`
- 检查网络连接
- 确认服务器地址正确：`http://45.130.146.21:8080/xiazai`

## 相关仓库

- **APK源仓库**：
  - https://github.com/z0brk/netamade-releases
  - https://github.com/netcookies/Neta-Vehicle
- **程序仓库**：https://github.com/Gundamx682/meishi

## 安全建议

1. **限制访问**：考虑使用反向代理（如Nginx）添加认证
2. **HTTPS**：生产环境建议配置SSL证书
3. **防火墙**：仅开放必要端口
4. **Token管理**：定期更换GitHub Token，使用最小权限原则
5. **日志监控**：定期检查日志，发现异常及时处理
6. **APK签名**：Android客户端建议使用正式签名发布

## 维护建议

1. **定期清理**：系统会自动保留最新的3个APK文件
2. **日志轮转**：建议配置logrotate管理日志文件
3. **监控服务**：建议配置监控工具（如Prometheus）监控服务状态
4. **备份配置**：定期备份 `/opt/apk-downloader` 目录
5. **更新系统**：定期更新系统和依赖包
6. **Android更新**：定期更新Android客户端版本

## 文件清单

### 服务端文件
- `install.sh` - 一键安装脚本
- `apk-downloader.sh` - APK下载守护进程（支持多仓库）
- `apk-server.py` - HTTP下载服务器（支持多仓库显示）
- `apk-downloader.service` - systemd服务配置（下载服务）
- `apk-server.service` - systemd服务配置（HTTP服务）
- `download_latest_apk.sh` - 手动下载脚本
- `check_urls.sh` - URL验证工具
- `apk-proxy.sh` - APK代理脚本
- `install_apk_proxy.sh` - APK代理安装脚本
- `no-yum-install.sh` - 无YUM环境依赖安装脚本
- `README.md` - 项目说明文档
- `IFLOW.md` - 项目技术文档（本文件）

### Android客户端文件
- `APKDOO/` - Android客户端项目目录
  - `app/` - 应用源码
  - `build.gradle` - 应用构建配置
  - `settings.gradle.kts` - Gradle设置
  - `gradlew` - Gradle包装器（Linux/Mac）
  - `gradlew.bat` - Gradle包装器（Windows）
  - `README.md` - Android项目说明

## 多仓库特性说明

### 仓库目录结构
每个仓库都有独立的下载目录：
```
/var/www/apk-downloads/
├── netamade/          # NetaMade仓库的APK
│   ├── app-v1.0.apk
│   ├── app-v1.1.apk
│   └── app-v1.2.apk
└── vehicle/           # Neta Vehicle仓库的APK
    ├── vehicle-v2.0.apk
    └── vehicle-v2.1.apk
```

### 下载链接格式
- 主页：`http://45.130.146.21:8080`
- NetaMade下载：`http://45.130.146.21:8080/xiazai/netamade`
- Neta Vehicle下载：`http://45.130.146.21:8080/xiazai/vehicle`

### 自动清理策略
每个仓库独立管理，自动保留最新的3个APK文件，旧版本会被自动清理。

### 日志格式
下载日志中会包含仓库名称标识，方便追踪：
```
[2026-01-04 10:00:00] [INFO] [netamade] 下载APK: app-v1.2.apk
[2026-01-04 10:00:00] [INFO] [vehicle] 下载APK: vehicle-v2.1.apk
```

## 版本历史

### v1.0 (当前版本)
- 支持多仓库监控
- 添加Android客户端
- 支持GitHub Token认证
- 自动清理旧版本
- Web界面显示所有仓库