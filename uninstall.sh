#!/bin/bash

# APK自动下载服务一键卸载脚本
# 适用于CentOS 7/8/9 系统

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

# 停止服务
stop_services() {
    log_step "停止服务..."

    # 停止APK下载服务
    if systemctl is-active --quiet apk-downloader 2>/dev/null; then
        systemctl stop apk-downloader
        log_info "✓ APK下载服务已停止"
    else
        log_info "APK下载服务未运行"
    fi

    # 停止HTTP服务器
    if systemctl is-active --quiet apk-server 2>/dev/null; then
        systemctl stop apk-server
        log_info "✓ HTTP服务器已停止"
    else
        log_info "HTTP服务器未运行"
    fi

    # 等待服务完全停止
    sleep 2
}

# 禁用服务
disable_services() {
    log_step "禁用服务..."

    # 禁用APK下载服务
    if systemctl is-enabled apk-downloader 2>/dev/null; then
        systemctl disable apk-downloader
        log_info "✓ APK下载服务已禁用"
    fi

    # 禁用HTTP服务器
    if systemctl is-enabled apk-server 2>/dev/null; then
        systemctl disable apk-server
        log_info "✓ HTTP服务器已禁用"
    fi
}

# 删除systemd服务文件
remove_service_files() {
    log_step "删除systemd服务文件..."

    # 删除服务文件
    if [ -f /etc/systemd/system/apk-downloader.service ]; then
        rm -f /etc/systemd/system/apk-downloader.service
        log_info "✓ 已删除 apk-downloader.service"
    fi

    if [ -f /etc/systemd/system/apk-server.service ]; then
        rm -f /etc/systemd/system/apk-server.service
        log_info "✓ 已删除 apk-server.service"
    fi

    # 重新加载systemd
    systemctl daemon-reload
    systemctl reset-failed
}

# 删除程序文件
remove_program_files() {
    log_step "删除程序文件..."

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        log_info "✓ 已删除程序目录: $INSTALL_DIR"
    else
        log_info "程序目录不存在"
    fi
}

# 询问是否删除APK文件
remove_apk_files() {
    log_step "清理APK文件..."

    if [ -d "$APK_DIR" ]; then
        echo ""
        log_warn "是否删除所有下载的APK文件？"
        log_warn "APK目录: $APK_DIR"
        read -p "删除APK文件？(y/N): " remove_apk

        if [ "$remove_apk" = "y" ] || [ "$remove_apk" = "Y" ]; then
            # 计算APK文件大小
            apk_size=$(du -sh "$APK_DIR" 2>/dev/null | awk '{print $1}')
            rm -rf "$APK_DIR"
            log_info "✓ 已删除APK目录 (释放空间: $apk_size)"
        else
            log_info "保留APK文件"
        fi
    else
        log_info "APK目录不存在"
    fi
}

# 询问是否删除GitHub Token
remove_github_token() {
    log_step "清理GitHub Token配置..."

    if grep -q "GITHUB_TOKEN" /etc/profile 2>/dev/null; then
        echo ""
        log_warn "是否删除GitHub Token配置？"
        log_warn "Token保存在: /etc/profile"
        read -p "删除GitHub Token？(y/N): " remove_token

        if [ "$remove_token" = "y" ] || [ "$remove_token" = "Y" ]; then
            # 备份profile
            cp /etc/profile /etc/profile.bak
            # 删除包含GITHUB_TOKEN的行
            sed -i '/GITHUB_TOKEN/d' /etc/profile
            log_info "✓ 已删除GitHub Token配置"
            log_info "  备份文件: /etc/profile.bak"
        else
            log_info "保留GitHub Token配置"
        fi
    else
        log_info "未找到GitHub Token配置"
    fi
}

# 关闭防火墙端口
close_firewall() {
    log_step "关闭防火墙端口..."

    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-port=8080/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_info "✓ 已关闭防火墙端口 8080"
    else
        log_info "未检测到firewalld"
    fi
}

# 清理日志文件
clean_logs() {
    log_step "清理日志文件..."

    # 删除日志文件
    if [ -f /var/log/apk-downloader.log ]; then
        rm -f /var/log/apk-downloader.log
        log_info "✓ 已删除下载服务日志"
    fi

    if [ -f /var/log/apk-server.log ]; then
        rm -f /var/log/apk-server.log
        log_info "✓ 已删除HTTP服务日志"
    fi

    # 清理journalctl日志
    journalctl --rotate >/dev/null 2>&1 || true
    journalctl --vacuum-time=1d >/dev/null 2>&1 || true
}

# 显示卸载摘要
show_summary() {
    echo ""
    log_info "========================================="
    log_info "卸载完成！"
    log_info "========================================="
    echo ""
    log_info "已删除："
    echo "  ✓ systemd服务配置"
    echo "  ✓ 程序文件 ($INSTALL_DIR)"
    echo "  ✓ 日志文件"
    echo "  ✓ 防火墙规则"
    echo ""
    log_info "如需重新安装，请运行："
    echo "  sudo bash install-new.sh"
    echo ""
}

# 主函数
main() {
    log_info "开始卸载APK自动下载服务..."

    echo ""
    log_warn "警告：此操作将删除所有服务配置和程序文件"
    log_warn "请确认您要继续卸载"
    echo ""
    read -p "确认卸载？(yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "取消卸载"
        exit 0
    fi

    check_root
    stop_services
    disable_services
    remove_service_files
    remove_program_files
    remove_apk_files
    remove_github_token
    close_firewall
    clean_logs
    show_summary
}

# 执行主函数
main "$@"