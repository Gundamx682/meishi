#!/bin/bash

# 直接下载最新APK脚本
# 从z0brk/netamade-releases仓库下载最新APK

set -e

# 配置参数
REPO_OWNER="z0brk"
REPO_NAME="netamade-releases"
GITHUB_API="https://api.github.com"
DOWNLOAD_DIR="/tmp/apk-downloads"
CURRENT_DIR="$(pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 获取最新release
get_latest_release() {
    log_info "获取 $REPO_OWNER/$REPO_NAME 最新release..."
    
    local api_url="${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    local response
    
    response=$(curl -s -H "Accept: application/vnd.github+json" -H "User-Agent: APK-Downloader" "$api_url")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_error "无法获取release信息"
        return 1
    fi
    
    if echo "$response" | grep -q '"message":'; then
        log_error "GitHub API错误: $(echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('message', 'Unknown error'))")"
        return 1
    fi
    
    echo "$response"
}

# 下载APK
download_latest_apk() {
    local release_info="$1"
    
    # 提取APK下载链接
    local apk_url
    apk_url=$(echo "$release_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
        break
")
    
    if [ -z "$apk_url" ]; then
        log_error "未找到APK文件"
        return 1
    fi
    
    # 获取APK文件名
    local apk_name
    apk_name=$(basename "$apk_url")
    
    log_info "找到APK: $apk_name"
    log_info "下载链接: $apk_url"
    
    # 下载APK
    log_info "开始下载..."
    if curl -L -o "$CURRENT_DIR/$apk_name" -H "User-Agent: APK-Downloader" "$apk_url"; then
        log_info "✓ 下载完成: $apk_name"
        log_info "文件位置: $CURRENT_DIR/$apk_name"
        
        # 显示文件信息
        ls -lh "$CURRENT_DIR/$apk_name"
        
        return 0
    else
        log_error "✗ 下载失败"
        return 1
    fi
}

# 主函数
main() {
    log_info "APK下载工具"
    log_info "目标仓库: $REPO_OWNER/$REPO_NAME"
    
    # 检查依赖
    for cmd in curl python3; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "缺少必要命令: $cmd"
            log_info "请安装: yum install -y curl python3"
            exit 1
        fi
    done
    
    # 获取最新release
    local release_info
    release_info=$(get_latest_release)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # 下载APK
    download_latest_apk "$release_info"
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    log_info "下载完成！"
}

main "$@"