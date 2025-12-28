#!/bin/bash

# APK自动下载和代理服务一键安装脚本（带Token输入功能）
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

# 获取GitHub Token
get_github_token() {
    log_step "获取GitHub Token..."
    
    echo ""
    log_info "========================================="
    log_info "GitHub Token 配置"
    log_info "========================================="
    echo ""
    log_info "为了绕过GitHub API速率限制，请提供您的GitHub Personal Access Token"
    echo ""
    log_info "获取Token方法："
    echo "1. 访问 https://github.com/settings/tokens"
    echo "2. 点击 'Generate new token'"
    echo "3. 选择 'Fine-grained personal access tokens' 或 'Classic personal access tokens'"
    echo "4. 生成并复制Token"
    echo ""
    
    read -s -p "请输入您的GitHub Token: " GITHUB_TOKEN
    echo ""
    
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "GitHub Token不能为空"
        exit 1
    fi
    
    # 验证Token
    log_info "验证GitHub Token..."
    if curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/user" >/dev/null 2>&1; then
        log_info "✓ Token验证成功"
    else
        log_error "✗ Token验证失败，请检查Token是否正确"
        exit 1
    fi
    
    # 将Token保存到临时变量
    export GITHUB_TOKEN="$GITHUB_TOKEN"
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
    
    # 创建带Token的下载脚本
    cat > "$INSTALL_DIR/apk-downloader.sh" << 'EOF'
#!/bin/bash
# 带GitHub Token认证的APK下载脚本

REPO_OWNER="z0brk"
REPO_NAME="netamade-releases"
APK_DIR="/var/www/apk-downloads"
CHECK_INTERVAL=600

# 从环境变量获取GitHub Token
GITHUB_TOKEN="$(grep -E "^export GITHUB_TOKEN=" /etc/profile 2>/dev/null | cut -d'"' -f2)"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a /var/log/apk-downloader.log
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a /var/log/apk-downloader.log
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a /var/log/apk-downloader.log
}

get_latest_release() {
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    
    if [ -n "$GITHUB_TOKEN" ]; then
        curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" "$api_url"
    else
        curl -s -H "Accept: application/vnd.github+json" "$api_url"
    fi
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
        log_warn "未找到APK文件"
        return 1
    fi
    
    # 下载每个APK
    while IFS= read -r download_url; do
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local apk_name
            apk_name=$(basename "$download_url")
            local apk_path="${APK_DIR}/${apk_name}"
            
            log_info "下载APK: $apk_name"
            if curl -L -o "$apk_path" -H "Authorization: Bearer $GITHUB_TOKEN" "$download_url"; then
                log_info "下载成功: $apk_name"
                chmod 644 "$apk_path"
                
                # 清理旧文件，只保留最新的3个
                cd "$APK_DIR" 2>/dev/null || return 0
                ls -t *.apk 2>/dev/null | tail -n +4 | xargs -r rm -f
                
                return 0
            else
                log_error "下载失败: $apk_name"
                rm -f "$apk_path"  # 删除可能的不完整文件
                return 1
            fi
        fi
    done <<< "$apk_urls"
}

main_loop() {
    log_info "APK下载服务启动"
    log_info "监控仓库: $REPO_OWNER/$REPO_NAME"
    log_info "检查间隔: ${CHECK_INTERVAL}秒"
    
    # 首次检查
    local release_info
    release_info=$(get_latest_release)
    if [ $? -eq 0 ] && [ -n "$release_info" ] && ! echo "$release_info" | grep -q "API rate limit exceeded"; then
        download_apk "$release_info"
    else
        log_error "无法获取仓库信息: $release_info"
    fi
    
    # 主循环
    while true; do
        sleep "$CHECK_INTERVAL"
        release_info=$(get_latest_release)
        if [ $? -eq 0 ] && [ -n "$release_info" ] && ! echo "$release_info" | grep -q "API rate limit exceeded"; then
            download_apk "$release_info"
        else
            log_warn "API访问问题，跳过本次检查"
        fi
    done
}

main_loop
EOF

    # 创建HTTP服务器脚本
    cat > "$INSTALL_DIR/apk-server.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import logging
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

class SimpleAPKHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.apk_dir = '/var/www/apk-downloads'
        super().__init__(*args, **kwargs)
    
    def log_message(self, format, *args):
        """自定义日志格式"""
        logging.info(f"{self.address_string()} - {format%args}")
    
    def do_GET(self):
        """处理GET请求"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/xiazai':
            self.handle_download()
        elif parsed_path.path == '/':
            self.send_simple_response()
        else:
            self.send_error(404, "Not Found")
    
    def handle_download(self):
        """处理直接下载请求"""
        try:
            # 获取最新的APK文件
            latest_apk = self.get_latest_apk()
            
            if not latest_apk:
                self.send_error(404, "No APK file available")
                return
            
            apk_path = os.path.join(self.apk_dir, latest_apk['name'])
            
            if not os.path.exists(apk_path):
                self.send_error(404, "APK file not found")
                return
            
            # 发送文件
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.android.package-archive')
            self.send_header('Content-Disposition', f'attachment; filename="{latest_apk["name"]}"')
            self.send_header('Content-Length', str(latest_apk['size']))
            self.end_headers()
            
            with open(apk_path, 'rb') as f:
                self.wfile.write(f.read())
            
            logging.info(f"APK下载: {latest_apk['name']} ({latest_apk['size_mb']} MB)")
            
        except Exception as e:
            logging.error(f"下载处理错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def send_simple_response(self):
        """发送简单响应"""
        try:
            latest_apk = self.get_latest_apk()
            
            if latest_apk:
                html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK下载</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 600px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .download-btn {{
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 15px 30px;
            text-decoration: none;
            border-radius: 5px;
            font-size: 18px;
            margin: 20px 0;
        }}
        .download-btn:hover {{
            background: #45a049;
        }}
        .info {{
            color: #666;
            margin: 10px 0;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 APK下载</h1>
        <p class="info">最新版本: {latest_apk['name']}</p>
        <p class="info">文件大小: {latest_apk['size_mb']} MB</p>
        <p class="info">更新时间: {latest_apk['modified'][:19].replace('T', ' ')}</p>
        <a href="/xiazai" class="download-btn">立即下载</a>
        <p class="info">或直接访问: <code>http://45.130.146.21:8080/xiazai</code></p>
    </div>
</body>
</html>"""
            else:
                html_content = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK下载</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 APK下载</h1>
        <p>暂无APK文件，系统正在同步中...</p>
        <p>请稍后再试</p>
    </div>
</body>
</html>"""
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(html_content.encode('utf-8'))
            
        except Exception as e:
            logging.error(f"响应生成错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def get_latest_apk(self):
        """获取最新的APK文件"""
        try:
            if not os.path.exists(self.apk_dir):
                return None
            
            apk_files = []
            for filename in os.listdir(self.apk_dir):
                if filename.endswith('.apk'):
                    filepath = os.path.join(self.apk_dir, filename)
                    stat = os.stat(filepath)
                    
                    apk_files.append({
                        'name': filename,
                        'size': stat.st_size,
                        'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                        'size_mb': round(stat.st_size / (1024 * 1024), 2)
                    })
            
            if not apk_files:
                return None
            
            # 按修改时间排序，返回最新的
            apk_files.sort(key=lambda x: x['modified'], reverse=True)
            return apk_files[0]
            
        except Exception as e:
            logging.error(f"获取APK文件错误: {e}")
            return None

def setup_logging():
    """设置日志"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('/var/log/apk-server.log'),
            logging.StreamHandler(sys.stdout)
        ]
    )

def main():
    """主函数"""
    # 设置日志
    setup_logging()
    
    # 确保APK目录存在
    apk_dir = '/var/www/apk-downloads'
    os.makedirs(apk_dir, exist_ok=True)
    
    # 服务器配置
    server_address = ('0.0.0.0', 8080)
    httpd = HTTPServer(server_address, SimpleAPKHandler)
    
    logging.info(f"APK下载服务器启动")
    logging.info(f"直接下载地址: http://45.130.146.21:8080/xiazai")
    logging.info(f"主页地址: http://45.130.146.21:8080")
    logging.info(f"APK目录: {apk_dir}")
    logging.info("按 Ctrl+C 停止服务器")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logging.info("正在停止服务器...")
        httpd.server_close()
        logging.info("服务器已停止")

if __name__ == '__main__':
    main()
EOF

    # 设置执行权限
    chmod +x "$INSTALL_DIR/apk-downloader.sh"
    chmod +x "$INSTALL_DIR/apk-server.py"
    
    # 将Token保存到系统环境
    echo "export GITHUB_TOKEN=\"$GITHUB_TOKEN\"" >> /etc/profile
    
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
    echo ""
    log_info "✅ GitHub Token已配置，API速率限制问题已解决"
}

# 主函数
main() {
    log_info "开始安装APK自动下载服务..."
    log_info "服务器IP: $SERVER_IP"
    
    check_root
    check_system
    check_memory
    get_github_token
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