#!/bin/zsh

print_green()  { echo -e "\033[0;32m$1\033[0m"; }
print_red()    { echo -e "\033[0;31m$1\033[0m"; }
print_yellow() { echo -e "\033[0;33m$1\033[0m"; }

LAST_PATH_FILE="$HOME/.last_sourcetree_path"
BASE_DIR=""

print_green "🛠️ 脚本功能："
print_green "1️⃣ 遍历你指定的大文件夹，查找所有 Git 仓库"
print_green "2️⃣ 自动执行 git add / commit"
print_green "3️⃣ 跳过无改动或无效仓库"
echo ""

# ✅ 读取上一次路径（如果有）
if [[ -f "$LAST_PATH_FILE" ]]; then
  LAST_PATH=$(<"$LAST_PATH_FILE")
  print_yellow "📌 上次使用的路径是：$LAST_PATH"
  read "?👉 直接回车使用上次路径，或拖入新路径：" USER_INPUT
  USER_INPUT=${USER_INPUT%\"}
  USER_INPUT=${USER_INPUT#\"}

  if [[ -z "$USER_INPUT" ]]; then
    BASE_DIR="$LAST_PATH"
  else
    BASE_DIR="$USER_INPUT"
  fi
else
  # 第一次运行时强制输入
  read "?👉 请拖入你 Sourcetree 项目集合的总文件夹，然后按回车确认：" BASE_DIR
  BASE_DIR=${BASE_DIR%\"}
  BASE_DIR=${BASE_DIR#\"}
fi

# 🚨 验证输入路径
while [[ ! -d "$BASE_DIR" ]]; do
  print_red "❌ 输入的路径无效，请重新拖入有效文件夹路径"
  read "?👉 请拖入你 Sourcetree 项目集合的总文件夹，然后按回车确认：" BASE_DIR
  BASE_DIR=${BASE_DIR%\"}
  BASE_DIR=${BASE_DIR#\"}
done

# ✅ 保存路径
echo "$BASE_DIR" > "$LAST_PATH_FILE"

print_yellow "📂 开始扫描目录：$BASE_DIR"
REPO_PATHS=($(find "$BASE_DIR" -type d -name ".git" -exec dirname {} \; | sort -u))

if [[ ${#REPO_PATHS[@]} -eq 0 ]]; then
  print_red "❌ 未找到任何 Git 仓库，请检查路径是否正确"
  exit 1
fi

for repo in "${REPO_PATHS[@]}"; do
  print_yellow "\n📁 正在处理：$repo"
  cd "$repo" || continue

  if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "自动提交：$(date '+%F %T')" 2>/dev/null && \
      print_green "✅ 已提交更改" || \
      print_red "⚠️ 无需提交"
  else
    print_green "✅ 无改动，跳过"
  fi
done

echo ""
print_green "🏁 所有项目处理完成"
