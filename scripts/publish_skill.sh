#!/bin/bash
# Skill Publisher - 自动上传 WorkBuddy skill 到 GitHub
# 用法: bash publish_skill.sh --skill-path <path> --repo-name <name> [--sanitize]

set -e

# ============ 配置 ============
GITHUB_USER="MaoFelix009"
TOKEN_FILE="$HOME/.workbuddy/skills/skill-publisher/.github-token"

# ============ 参数解析 ============
SKILL_PATH=""
REPO_NAME=""
SANITIZE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skill-path)
      SKILL_PATH="$2"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="$2"
      shift 2
      ;;
    --sanitize)
      SANITIZE=true
      shift
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

# 展开波浪号
SKILL_PATH="${SKILL_PATH/#\~/$HOME}"

if [[ -z "$SKILL_PATH" || -z "$REPO_NAME" ]]; then
  echo "❌ 缺少必需参数"
  echo "用法: bash publish_skill.sh --skill-path <path> --repo-name <name> [--sanitize]"
  exit 1
fi

if [[ ! -d "$SKILL_PATH" ]]; then
  echo "❌ Skill 目录不存在: $SKILL_PATH"
  exit 1
fi

if [[ ! -f "$SKILL_PATH/SKILL.md" ]]; then
  echo "❌ 缺少 SKILL.md 文件"
  exit 1
fi

# ============ 读取 GitHub Token ============
if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "❌ 未找到 GitHub Token"
  echo "请先创建 Token 文件: echo 'ghp_YOUR_TOKEN' > $TOKEN_FILE"
  echo "然后执行: chmod 600 $TOKEN_FILE"
  exit 1
fi

GITHUB_TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n\r ')

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ Token 文件为空"
  exit 1
fi

echo "🔧 GitHub 用户: $GITHUB_USER"
echo "📦 仓库名称: $REPO_NAME"
echo "📁 Skill 路径: $SKILL_PATH"
echo ""

# ============ Step 1: 脱敏处理 ============
if [[ "$SANITIZE" == true ]]; then
  echo "[1/4] 🧹 脱敏处理..."
  
  TEMP_DIR=$(mktemp -d)
  cp -r "$SKILL_PATH"/* "$TEMP_DIR/"
  
  # 脱敏规则
  find "$TEMP_DIR" -type f \( -name "*.md" -o -name "*.py" -o -name "*.sh" -o -name "*.js" \) -exec sed -i '' \
    -e 's/ntn_[a-zA-Z0-9]\{32,\}/YOUR_NOTION_TOKEN/g' \
    -e 's/cli_[a-zA-Z0-9]\{16,\}/YOUR_FEISHU_APP_ID/g' \
    -e 's/ghp_[a-zA-Z0-9]\{36,\}/YOUR_GITHUB_TOKEN/g' \
    -e 's/secret_[a-zA-Z0-9]\{32,\}/YOUR_APP_SECRET/g' \
    {} \;
  
  # 针对 Python 配置区域的通用脱敏
  find "$TEMP_DIR" -type f -name "*.py" -exec sed -i '' \
    -e '/^FEISHU_APP_SECRET = /s/"[^"]\{20,\}"/"YOUR_FEISHU_APP_SECRET"/' \
    -e '/^NOTION_TOKEN = /s/"[^"]\{20,\}"/"YOUR_NOTION_TOKEN"/' \
    -e '/^NOTION_DATABASE_ID = /s/"[^"]\{20,\}"/"YOUR_NOTION_DATABASE_ID"/' \
    {} \;
  
  UPLOAD_DIR="$TEMP_DIR"
  echo "   ✅ 脱敏完成（临时目录: $TEMP_DIR）"
else
  UPLOAD_DIR="$SKILL_PATH"
  echo "[1/4] ⏭️  跳过脱敏"
fi

# ============ Step 2: 生成 README.md ============
echo "[2/4] 📝 检查 README.md..."

if [[ ! -f "$UPLOAD_DIR/README.md" ]]; then
  SKILL_NAME=$(grep -m1 "^name:" "$UPLOAD_DIR/SKILL.md" | sed 's/name: *//')
  SKILL_DESC=$(grep -m1 "^description:" "$UPLOAD_DIR/SKILL.md" | sed 's/description: *//')
  
  cat > "$UPLOAD_DIR/README.md" <<EOF
# $SKILL_NAME

$SKILL_DESC

## 安装

\`\`\`bash
git clone https://github.com/$GITHUB_USER/$REPO_NAME.git ~/.workbuddy/skills/$REPO_NAME
\`\`\`

## 使用

详见 [SKILL.md](./SKILL.md)

## 配置

首次使用前，请根据 SKILL.md 中的说明配置必要的凭证和参数。
EOF
  
  echo "   ✅ 已生成 README.md"
else
  echo "   ✅ README.md 已存在"
fi

# ============ Step 3: 创建/检查仓库 ============
echo "[3/4] 🏗️  检查 GitHub 仓库..."

REPO_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME")

if [[ "$REPO_CHECK" == "404" ]]; then
  echo "   📦 仓库不存在，创建中..."
  
  CREATE_RESULT=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.github.com/user/repos" \
    -d "{\"name\":\"$REPO_NAME\",\"description\":\"WorkBuddy Skill: $REPO_NAME\",\"private\":false}")
  
  if echo "$CREATE_RESULT" | grep -q '"html_url"'; then
    echo "   ✅ 仓库创建成功"
  else
    echo "   ❌ 仓库创建失败:"
    echo "$CREATE_RESULT" | python3 -m json.tool
    exit 1
  fi
elif [[ "$REPO_CHECK" == "200" ]]; then
  echo "   ✅ 仓库已存在，将更新文件"
else
  echo "   ❌ 检查仓库失败 (HTTP $REPO_CHECK)"
  exit 1
fi

# ============ Step 4: 上传文件 ============
echo "[4/4] 📤 上传文件到 GitHub..."

upload_file() {
  local file_path="$1"
  local rel_path="${file_path#$UPLOAD_DIR/}"
  
  echo "   📄 上传: $rel_path"
  
  # 获取现有文件的 SHA（如果存在）
  SHA_RESULT=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/contents/$rel_path")
  
  SHA=$(echo "$SHA_RESULT" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r.get('sha',''))" 2>/dev/null || echo "")
  
  # Base64 编码文件内容
  CONTENT=$(base64 -i "$file_path" | tr -d '\n')
  
  # 构建 JSON payload
  if [[ -n "$SHA" ]]; then
    PAYLOAD="{\"message\":\"Update $rel_path\",\"content\":\"$CONTENT\",\"sha\":\"$SHA\"}"
  else
    PAYLOAD="{\"message\":\"Add $rel_path\",\"content\":\"$CONTENT\"}"
  fi
  
  # 上传
  UPLOAD_RESULT=$(curl -s -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/contents/$rel_path" \
    -d "$PAYLOAD")
  
  if echo "$UPLOAD_RESULT" | grep -q '"html_url"'; then
    echo "      ✅ 成功"
  else
    echo "      ❌ 失败:"
    echo "$UPLOAD_RESULT" | python3 -m json.tool | head -20
    return 1
  fi
}

# 递归上传所有文件
export -f upload_file
export GITHUB_TOKEN GITHUB_USER REPO_NAME UPLOAD_DIR

find "$UPLOAD_DIR" -type f | while read file; do
  upload_file "$file"
done

# ============ 清理临时目录 ============
if [[ "$SANITIZE" == true ]]; then
  rm -rf "$TEMP_DIR"
fi

# ============ 完成 ============
echo ""
echo "=========================================="
echo "✅ Skill 发布成功！"
echo ""
echo "🔗 仓库地址:"
echo "   https://github.com/$GITHUB_USER/$REPO_NAME"
echo ""
echo "📦 安装命令:"
echo "   git clone https://github.com/$GITHUB_USER/$REPO_NAME.git ~/.workbuddy/skills/$REPO_NAME"
echo "=========================================="
