#!/bin/bash

# BLE HTTP Server 启动脚本
echo "🔄 构建 BLE HTTP Server..."

# 清理旧构建
rm -rf .build

# 构建项目
if swift build -c release; then
    echo "✅ 构建成功！"
    echo ""
    echo "🚀 启动 BLE HTTP Server..."
    echo "========================================"
    echo "🌐 服务地址: http://localhost:8080"
    echo "📡 蓝牙权限需要系统授权"
    echo "🛑 按 Ctrl+C 停止服务器"
    echo "========================================"
    echo ""
    
    # 运行服务器
    .build/release/Run serve --hostname 0.0.0.0 --port 8080
else
    echo "❌ 构建失败"
    exit 1
fi
