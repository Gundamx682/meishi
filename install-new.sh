#!/bin/bash

# APK自动下载和分发服务一键安装脚本（多仓库版本）
# 适用于CentOS 7/8/9 系统
# 服务器IP: 45.130.146.21
# 支持多仓库：netamade, vehicle

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置参数
INSTALL_DIR="/opt/apk-downloader"
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

    # 读取GitHub Token，确保等待用户输入
    while true; do
        read -s -p "请输入您的GitHub Token: " GITHUB_TOKEN
        echo ""

        if [ -z "$GITHUB_TOKEN" ]; then
            log_error "GitHub Token不能为空，请重新输入"
            continue
        fi

        # 验证Token
        log_info "验证GitHub Token..."
        if curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
            "https://api.github.com/user" >/dev/null 2>&1; then
            log_info "✓ Token验证成功"
            break
        else
            log_error "✗ Token验证失败，请检查Token是否正确，然后重新输入"
            continue
        fi
    done

    # 将Token保存到临时变量
    export GITHUB_TOKEN="$GITHUB_TOKEN"

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

    # 尝试使用yum安装
    if command -v yum &> /dev/null; then
        log_info "使用yum安装依赖..."
        yum install -y curl python3 systemd 2>/dev/null || true
    fi

    # 再次检查
    if command -v curl &> /dev/null; then
        log_info "✓ curl 已安装"
    fi

    if command -v python3 &> /dev/null; then
        log_info "✓ python3 已安装"
    fi

    if command -v systemctl &> /dev/null; then
        log_info "✓ systemctl 已安装"
    fi

    log_info "✓ 依赖检查完成"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$APK_DIR"
    mkdir -p "/var/log"

    # 设置权限
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$APK_DIR"

    log_info "目录结构创建完成"
}

# 部署脚本文件
deploy_scripts() {
    log_step "部署脚本文件..."

    # 检查本地文件是否存在
    if [ ! -f "apk-downloader.sh" ]; then
        log_error "未找到 apk-downloader.sh 文件"
        exit 1
    fi

    if [ ! -f "apk-server.py" ]; then
        log_error "未找到 apk-server.py 文件"
        exit 1
    fi

    # 复制脚本到目标目录
    cp apk-downloader.sh "$INSTALL_DIR/"
    cp apk-server.py "$INSTALL_DIR/"

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

    # 检查服务文件是否存在
    if [ ! -f "apk-downloader.service" ]; then
        log_error "未找到 apk-downloader.service 文件"
        exit 1
    fi

    if [ ! -f "apk-server.service" ]; then
        log_error "未找到 apk-server.service 文件"
        exit 1
    fi

    # 复制服务文件
    cp apk-downloader.service /etc/systemd/system/
    cp apk-server.service /etc/systemd/system/

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
    log_info "⬇️ 下载链接:"
    log_info "   - NetaMade: http://${SERVER_IP}:${SERVER_PORT}/xiazai/netamade"
    log_info "   - Neta Vehicle: http://${SERVER_IP}:${SERVER_PORT}/xiazai/vehicle"
    log_info "📋 服务管理命令:"
    echo "  查看状态: systemctl status apk-downloader apk-server"
    echo "  重启服务: systemctl restart apk-downloader apk-server"
    echo "  查看日志: journalctl -u apk-downloader -f"
    echo "  查看日志: journalctl -u apk-server -f"
    echo ""
    log_info "📁 APK目录: ${APK_DIR}"
    log_info "📱 系统每10分钟自动检查一次GitHub仓库更新"
    echo ""
    log_info "🎯 监控的仓库:"
    log_info "   - NetaMade: https://github.com/z0brk/netamade-releases"
    log_info "   - Neta Vehicle: https://github.com/netcookies/Neta-Vehicle"
    echo ""
    log_info "✅ GitHub Token已配置，API速率限制问题已解决"
}

# 主函数
main() {
    log_info "开始安装APK自动下载服务（多仓库版本）..."
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