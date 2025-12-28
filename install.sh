#!/bin/bash

# APK自动下载和代理服务一键安装脚本
# 适用于CentOS 7/8/9 系统
# 服务器IP: 45.130.146.21

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置参数
INSTALL_DIR="/opt/apk-downloader"
PROXY_DIR="/opt/apk-proxy"
APK_DIR="/var/www/apk-downloads"
SERVICE_USER="root"
SERVER_IP="45.130.146.21"
SERVER_PORT="8080"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请以root权限运行此脚本"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_step "检查系统版本..."
    
    if [ ! -f /etc/centos-release ] && [ ! -f /etc/redhat-release ]; then
        log_error "此脚本仅支持CentOS/RHEL系统"
        exit 1
    fi
    
    if [ -f /etc/centos-release ]; then
        CENTOS_VERSION=$(cat /etc/centos-release | grep -oE '[0-9]+' | head -1)
        log_info "检测到CentOS $CENTOS_VERSION"
    else
        log_info "检测到RHEL系统"
    fi
}

# 检查内存
check_memory() {
    local available_mem=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    log_info "可用内存: ${available_mem}MB"
    
    if [ "$available_mem" -lt 200 ]; then
        log_warn "内存不足，尝试释放缓存..."
        sync
        echo 3 > /proc/sys/vm/drop_caches
        sleep 2
        log_info "缓存已释放，继续安装..."
    fi
}

# 安装系统依赖
install_dependencies() {
    log_step "安装系统依赖..."
    
    # 尝试下载并运行无yum安装脚本
    local no_yum_url="https://raw.githubusercontent.com/Gundamx682/meishi/main/no-yum-install.sh"
    local temp_script="/tmp/no-yum-install.sh"
    
    # 如果有curl，尝试下载无yum脚本
    if command -v curl &> /dev/null; then
        if curl -fsSL --max-time 30 --retry 2 "$no_yum_url" -o "$temp_script"; then
            log_info "使用无YUM安装脚本..."
            chmod +x "$temp_script"
            if bash "$temp_script"; then
                log_info "✓ 无YUM依赖安装成功"
                rm -f "$temp_script"
                return 0
            else
                log_warn "无YUM安装失败，尝试其他方式..."
            fi
            rm -f "$temp_script"
        fi
    fi
    
    # 检查系统中已有的工具
    log_info "检查现有工具..."
    local has_curl=false
    local has_python3=false
    local has_systemctl=false
    
    if command -v curl &> /dev/null; then
        log_info "✓ curl 已存在"
        has_curl=true
    fi
    
    if command -v python3 &> /dev/null; then
        log_info "✓ python3 已存在"
        has_python3=true
    fi
    
    if command -v systemctl &> /dev/null; then
        log_info "✓ systemctl 已存在"
        has_systemctl=true
    fi
    
    # 如果关键工具都有，跳过安装
    if [ "$has_curl" = true ] && [ "$has_python3" = true ] && [ "$has_systemctl" = true ]; then
        log_info "✓ 所有关键工具已存在，跳过依赖安装"
        return 0
    fi
    
    # 尝试使用wget下载安装脚本
    if command -v wget &> /dev/null && [ "$has_curl" = false ]; then
        log_info "尝试使用wget下载安装脚本..."
        if wget --timeout=30 --tries=2 -q "$no_yum_url" -O "$temp_script"; then
            chmod +x "$temp_script"
            if bash "$temp_script"; then
                log_info "✓ 依赖安装成功"
                rm -f "$temp_script"
                return 0
            fi
            rm -f "$temp_script"
        fi
    fi
    
    # 最后的尝试：检查系统是否已经足够运行
    if [ "$has_python3" = true ] && [ "$has_systemctl" = true ]; then
        log_warn "curl不可用，但python3和systemctl存在"
        log_warn "创建curl替代方案..."
        
        # 创建curl的wget替代
        if command -v wget &> /dev/null; then
            cat > /usr/local/bin/curl << 'EOF'
#!/bin/bash
wget -O- "$@"
EOF
            chmod +x /usr/local/bin/curl
            log_info "✓ 创建curl替代方案"
            return 0
        fi
    fi
    
    # 如果还是缺少关键工具，给出手动安装建议
    local critical_missing=()
    if [ "$has_python3" = false ]; then
        critical_missing+=("python3")
    fi
    if [ "$has_systemctl" = false ]; then
        critical_missing+=("systemctl")
    fi
    
    if [ ${#critical_missing[@]} -gt 0 ]; then
        log_error "缺少关键工具: ${critical_missing[*]}"
        log_error "请手动安装这些工具后重试"
        exit 1
    fi
    
    log_info "✓ 依赖检查完成"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$PROXY_DIR"
    mkdir -p "$APK_DIR"
    mkdir -p "/var/log"
    
    # 设置权限
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$PROXY_DIR"
    chmod 755 "$APK_DIR"
    
    log_info "目录结构创建完成"
}

# 部署脚本文件
deploy_scripts() {
    log_step "部署脚本文件..."
    
    # 部署主下载脚本
    local apk_downloader_url="https://raw.githubusercontent.com/Gundamx682/meishi/main/apk-downloader.sh"
    local apk_server_url="https://raw.githubusercontent.com/Gundamx682/meishi/main/apk-server.py"
    local apk_proxy_url="https://raw.githubusercontent.com/Gundamx682/meishi/main/apk-proxy.sh"
    
    log_info "下载主下载脚本..."
    if curl -fsSL --max-time 30 --retry 2 "$apk_downloader_url" -o "$INSTALL_DIR/apk-downloader.sh"; then
        chmod +x "$INSTALL_DIR/apk-downloader.sh"
        log_info "✓ apk-downloader.sh 部署完成"
    else
        log_warn "无法下载 apk-downloader.sh，创建基础版本"
        cat > "$INSTALL_DIR/apk-downloader.sh" << 'EOF'
#!/bin/bash
# 基础APK下载脚本

REPO_OWNER="z0brk"
REPO_NAME="netamade-releases"
APK_DIR="/var/www/apk-downloads"
CHECK_INTERVAL=600

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a /var/log/apk-downloader.log
}

get_latest_release() {
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    curl -s -H "Accept: application/vnd.github+json" "$api_url"
}

download_apk() {
    local release_info="$1"
    local apk_urls
    apk_urls=$(echo "$release_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
")
    
    if [ -z "$apk_urls" ]; then
        log_info "未找到APK文件"
        return 1
    fi
    
    while IFS= read -r download_url; do
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local apk_name
            apk_name=$(basename "$download_url")
            local apk_path="${APK_DIR}/${apk_name}"
            
            log_info "下载APK: $apk_name"
            if curl -L -o "$apk_path" "$download_url"; then
                log_info "下载成功: $apk_name"
                chmod 644 "$apk_path"
                return 0
            else
                log_info "下载失败: $apk_name"
                return 1
            fi
        fi
    done <<< "$apk_urls"
}

main_loop() {
    log_info "APK下载服务启动"
    while true; do
        local release_info
        release_info=$(get_latest_release)
        if [ $? -eq 0 ]; then
            download_apk "$release_info"
        fi
        sleep "$CHECK_INTERVAL"
    done
}

main_loop
EOF
        chmod +x "$INSTALL_DIR/apk-downloader.sh"
    fi
    
    # 部署HTTP服务器脚本
    log_info "下载HTTP服务器脚本..."
    if curl -fsSL --max-time 30 --retry 2 "$apk_server_url" -o "$INSTALL_DIR/apk-server.py"; then
        chmod +x "$INSTALL_DIR/apk-server.py"
        log_info "✓ apk-server.py 部署完成"
    else
        log_warn "无法下载 apk-server.py，创建基础版本"
        cat > "$INSTALL_DIR/apk-server.py" << 'EOF'
#!/usr/bin/env python3
# 基础APK下载服务器

import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse

class APKDownloadHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.apk_dir = '/var/www/apk-downloads'
        super().__init__(*args, directory=self.apk_dir, **kwargs)
    
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/xiazai':
            self.handle_download()
        elif parsed_path.path == '/':
            self.send_simple_response()
        else:
            super().do_GET()
    
    def handle_download(self):
        # 获取最新APK文件
        apk_files = []
        if os.path.exists(self.apk_dir):
            for filename in os.listdir(self.apk_dir):
                if filename.endswith('.apk'):
                    filepath = os.path.join(self.apk_dir, filename)
                    apk_files.append((filename, os.path.getmtime(filepath)))
        
        if not apk_files:
            self.send_error(404, "No APK files available")
            return
        
        # 获取最新的APK文件
        latest_apk = max(apk_files, key=lambda x: x[1])
        latest_filename = latest_apk[0]
        apk_path = os.path.join(self.apk_dir, latest_filename)
        
        if not os.path.exists(apk_path):
            self.send_error(404, "APK file not found")
            return
        
        # 发送文件
        self.send_response(200)
        self.send_header('Content-Type', 'application/vnd.android.package-archive')
        self.send_header('Content-Disposition', f'attachment; filename="{latest_filename}"')
        self.send_header('Content-Length', str(os.path.getsize(apk_path)))
        self.end_headers()
        
        with open(apk_path, 'rb') as f:
            self.wfile.write(f.read())
    
    def send_simple_response(self):
        try:
            # 检查APK文件
            apk_files = []
            if os.path.exists(self.apk_dir):
                for filename in os.listdir(self.apk_dir):
                    if filename.endswith('.apk'):
                        filepath = os.path.join(self.apk_dir, filename)
                        apk_files.append((filename, os.path.getmtime(filepath)))
            
            if apk_files:
                latest_apk = max(apk_files, key=lambda x: x[1])
                latest_filename = latest_apk[0]
                html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>APK下载</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>📱 APK下载</h1>
    <p>最新版本: {latest_filename}</p>
    <a href="/xiazai" style="display:inline-block; padding:10px 20px; background:#4CAF50; color:white; text-decoration:none; border-radius:5px;">点击下载</a>
</body>
</html>"""
            else:
                html_content = """<!DOCTYPE html>
<html>
<head>
    <title>APK下载</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>📱 APK下载</h1>
    <p>暂无APK文件，系统正在同步中...</p>
    <p>请稍后再试</p>
</body>
</html>"""
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(html_content.encode('utf-8'))
            
        except Exception as e:
            self.send_error(500, "Internal Server Error")

if __name__ == '__main__':
    apk_dir = '/var/www/apk-downloads'
    os.makedirs(apk_dir, exist_ok=True)
    
    server_address = ('0.0.0.0', 8080)
    httpd = HTTPServer(server_address, APKDownloadHandler)
    
    import logging
    logging.basicConfig(level=logging.INFO)
    
    httpd.serve_forever()
EOF
        chmod +x "$INSTALL_DIR/apk-server.py"
    fi
    
    log_info "脚本文件部署完成"
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    # 启动firewalld
    systemctl enable firewalld 2>/dev/null || true
    systemctl start firewalld 2>/dev/null || true
    
    # 开放HTTP端口
    firewall-cmd --permanent --add-port="${SERVER_PORT}/tcp" 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    
    log_info "防火墙配置完成，已开放端口 ${SERVER_PORT}"
}

# 配置systemd服务
setup_services() {
    log_step "配置systemd服务..."
    
    # 创建apk-downloader服务
    cat > /etc/systemd/system/apk-downloader.service << EOF
[Unit]
Description=APK Auto Downloader Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/apk-downloader
ExecStart=/opt/apk-downloader/apk-downloader.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=apk-downloader

[Install]
WantedBy=multi-user.target
EOF

    # 创建apk-server服务
    cat > /etc/systemd/system/apk-server.service << EOF
[Unit]
Description=APK Download HTTP Server
After=network.target apk-downloader.service
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/apk-downloader
ExecStart=/usr/bin/python3 /opt/apk-downloader/apk-server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=apk-server

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable apk-downloader 2>/dev/null || true
    systemctl enable apk-server 2>/dev/null || true
    
    log_info "systemd服务配置完成"
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    # 启动APK下载服务
    systemctl start apk-downloader 2>/dev/null || true
    
    # 等待几秒
    sleep 3
    
    # 启动HTTP服务器
    systemctl start apk-server 2>/dev/null || true
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet apk-downloader; then
        log_info "✓ APK下载服务启动成功"
    else
        log_warn "⚠ APK下载服务启动状态未知"
    fi
    
    if systemctl is-active --quiet apk-server; then
        log_info "✓ HTTP服务器启动成功"
    else
        log_warn "⚠ HTTP服务器启动状态未知"
    fi
}

# 验证安装
verify_installation() {
    log_step "验证安装..."
    
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="
    echo ""
    log_info "🌐 访问地址: http://${SERVER_IP}:${SERVER_PORT}"
    log_info "⬇️ 直接下载: http://${SERVER_IP}:${SERVER_PORT}/xiazai"
    log_info "📋 服务管理命令:"
    echo "  查看状态: systemctl status apk-downloader apk-server"
    echo "  重启服务: systemctl restart apk-downloader apk-server"
    echo "  查看日志: journalctl -u apk-downloader -f"
    echo "  查看日志: journalctl -u apk-server -f"
    echo ""
    log_info "📁 APK目录: ${APK_DIR}"
    log_info "📱 系统每10分钟自动检查一次GitHub仓库更新"
    echo ""
    log_info "🎯 监控仓库: https://github.com/z0brk/netamade-releases"
    log_info "📦 程序仓库: https://github.com/Gundamx682/meishi"
}

# 主函数
main() {
    log_info "开始安装APK自动下载服务..."
    log_info "服务器IP: $SERVER_IP"
    
    check_root
    check_system
    check_memory
    install_dependencies
    create_directories
    deploy_scripts
    configure_firewall
    setup_services
    start_services
    verify_installation
}

# 执行主函数
main "$@"