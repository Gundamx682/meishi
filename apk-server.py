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
        self.base_dir = '/var/www/apk-downloads'
        self.repos = {
            'netamade': {
                'name': 'NetaMade',
                'path': 'z0brk/netamade-releases'
            },
            'vehicle': {
                'name': 'Neta Vehicle',
                'path': 'netcookies/Neta-Vehicle'
            }
        }
        super().__init__(*args, **kwargs)
    
    def log_message(self, format, *args):
        """自定义日志格式"""
        logging.info(f"{self.address_string()} - {format%args}")
    
    def do_GET(self):
        """处理GET请求"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/xiazai':
            self.handle_download('netamade')
        elif parsed_path.path.startswith('/xiazai/'):
            # 从路径中提取仓库名称，如 /xiazai/vehicle
            repo_name = parsed_path.path.split('/')[2]
            self.handle_download(repo_name)
        elif parsed_path.path == '/':
            self.send_simple_response()
        else:
            self.send_error(404, "Not Found")
    
    def handle_download(self, repo_name):
        """处理直接下载请求"""
        try:
            # 验证仓库名称
            if repo_name not in self.repos:
                self.send_error(404, f"Unknown repository: {repo_name}")
                return
            
            # 获取最新的APK文件
            latest_apk = self.get_latest_apk(repo_name)
            
            if not latest_apk:
                self.send_error(404, "No APK file available")
                return
            
            repo_dir = os.path.join(self.base_dir, repo_name)
            apk_path = os.path.join(repo_dir, latest_apk['name'])
            
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
            
            logging.info(f"[{repo_name}] APK下载: {latest_apk['name']} ({latest_apk['size_mb']} MB)")
            
        except Exception as e:
            logging.error(f"下载处理错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def send_simple_response(self):
        """发送简单响应"""
        try:
            # 获取所有仓库的最新APK
            repos_info = []
            for repo_key in self.repos.keys():
                latest_apk = self.get_latest_apk(repo_key)
                if latest_apk:
                    repos_info.append({
                        'key': repo_key,
                        'name': self.repos[repo_key]['name'],
                        'path': self.repos[repo_key]['path'],
                        'apk': latest_apk
                    })
            
            # 生成HTML内容
            if repos_info:
                repos_html = ""
                for repo in repos_info:
                    repos_html += f"""
                    <div class="repo-card">
                        <h2>📦 {repo['name']}</h2>
                        <p class="repo-path">仓库: {repo['path']}</p>
                        <p class="info">文件名: {repo['apk']['name']}</p>
                        <p class="info">文件大小: {repo['apk']['size_mb']} MB</p>
                        <p class="info">更新时间: {repo['apk']['modified'][:19].replace('T', ' ')}</p>
                        <a href="/xiazai/{repo['key']}" class="download-btn">立即下载</a>
                    </div>"""
                
                html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK下载中心</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            padding: 30px;
            background-color: #f5f5f5;
            margin: 0;
        }}
        .container {{
            max-width: 800px;
            margin: 0 auto;
        }}
        .header {{
            text-align: center;
            margin-bottom: 40px;
        }}
        .header h1 {{
            color: #333;
            margin: 0 0 10px 0;
        }}
        .repo-card {{
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }}
        .repo-card h2 {{
            margin: 0 0 15px 0;
            color: #2c3e50;
        }}
        .repo-path {{
            color: #7f8c8d;
            font-size: 14px;
            margin-bottom: 15px;
        }}
        .info {{
            color: #666;
            margin: 8px 0;
            font-size: 14px;
        }}
        .download-btn {{
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 12px 25px;
            text-decoration: none;
            border-radius: 5px;
            font-size: 16px;
            margin-top: 15px;
            transition: background 0.3s;
        }}
        .download-btn:hover {{
            background: #45a049;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📱 APK下载中心</h1>
            <p style="color: #666;">选择要下载的应用</p>
        </div>
        {repos_html}
    </div>
</body>
</html>"""
            else:
                html_content = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK下载中心</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background-color: #f5f5f5;
            margin: 0;
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
        <h1>📱 APK下载中心</h1>
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
    
    def get_latest_apk(self, repo_name):
        """获取指定仓库的最新APK文件"""
        try:
            repo_dir = os.path.join(self.base_dir, repo_name)
            
            if not os.path.exists(repo_dir):
                return None
            
            apk_files = []
            for filename in os.listdir(repo_dir):
                if filename.lower().endswith('.apk'):
                    filepath = os.path.join(repo_dir, filename)
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
    
    # 确保基础目录存在
    base_dir = '/var/www/apk-downloads'
    os.makedirs(base_dir, exist_ok=True)
    
    # 服务器配置
    server_address = ('0.0.0.0', 8080)
    httpd = HTTPServer(server_address, SimpleAPKHandler)
    
    logging.info("APK下载服务器启动")
    logging.info("主页地址: http://45.130.146.21:8080")
    logging.info(f"基础目录: {base_dir}")
    logging.info("按 Ctrl+C 停止服务器")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logging.info("正在停止服务器...")
        httpd.server_close()
        logging.info("服务器已停止")

if __name__ == '__main__':
    main()