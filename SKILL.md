---
name: skill-publisher
description: Publish WorkBuddy skills to GitHub automatically. Use when user says "上传这个skill到GitHub", "发布skill", "把技能传到GitHub", "publish skill to GitHub". Handles secret removal, file encoding, and GitHub API upload with stored credentials.
---

# Skill Publisher - 自动发布 Skill 到 GitHub

## 触发条件
- 用户说"上传这个 skill 到 GitHub"、"发布 skill"、"把技能传到 GitHub"
- 用户说"publish skill to GitHub"
- 完成 skill 开发后想要分享

## 功能
自动将 WorkBuddy skill 上传到 GitHub 公开仓库，包括：
- 自动脱敏（移除硬编码的 token/secret）
- 生成 README.md（如果不存在）
- 使用 GitHub REST API 上传所有文件
- 使用存储的 GitHub Token，无需每次输入

## 工作流程

### Step 1: 确认 skill 路径和仓库名
询问用户：
1. **Skill 路径**：要上传的 skill 目录（例如 `~/.workbuddy/skills/feishu-meeting`）
2. **仓库名**：GitHub 仓库名称（例如 `feishu-meeting`）
3. **是否需要脱敏**：是否包含需要移除的 secret（默认是）

### Step 2: 执行上传脚本
调用 `scripts/publish_skill.sh`：

```bash
bash ~/.workbuddy/skills/skill-publisher/scripts/publish_skill.sh \
  --skill-path "~/.workbuddy/skills/feishu-meeting" \
  --repo-name "feishu-meeting" \
  --sanitize
```

脚本会：
1. 检查 skill 目录结构（必须有 SKILL.md）
2. 如果 `--sanitize` 开启，自动脱敏所有文件中的 secret
3. 生成 README.md（如果不存在）
4. 使用 GitHub API 创建仓库（如果不存在）
5. 上传所有文件到 GitHub
6. 输出仓库链接和安装命令

### Step 3: 告知结果
告诉用户：
- ✅ 仓库链接：`https://github.com/MaoFelix009/{repo-name}`
- 📦 安装命令：`git clone https://github.com/MaoFelix009/{repo-name}.git ~/.workbuddy/skills/{repo-name}`

## 配置

### GitHub 凭证存储
Token 存储在：`~/.workbuddy/skills/skill-publisher/.github-token`

**首次使用时会提示输入 GitHub Token**，之后自动读取。

如需更新 Token：
```bash
echo "ghp_YOUR_NEW_TOKEN" > ~/.workbuddy/skills/skill-publisher/.github-token
chmod 600 ~/.workbuddy/skills/skill-publisher/.github-token
```

### 脱敏规则
自动检测并替换以下模式：
- Notion Token: `ntn_[a-zA-Z0-9]+` → `YOUR_NOTION_TOKEN`
- 飞书 App ID: `cli_[a-zA-Z0-9]+` → `YOUR_FEISHU_APP_ID`
- 飞书 App Secret: 32位字母数字 → `YOUR_FEISHU_APP_SECRET`
- GitHub Token: `ghp_[a-zA-Z0-9]+` → `YOUR_GITHUB_TOKEN`
- 通用 API Key: `[a-zA-Z0-9]{32,}` 在配置区域 → `YOUR_API_KEY`

## 注意事项
1. **仓库默认公开**：所有上传的 skill 都是 public 仓库
2. **脱敏检查**：上传前会自动检查是否有遗漏的 secret
3. **覆盖保护**：如果仓库已存在，会更新文件而不是删除重建
4. **GitHub 用户名**：默认使用 `MaoFelix009`，可在脚本中修改
5. **网络问题**：使用 REST API 而非 git push，更稳定

## 文件结构要求
待上传的 skill 必须包含：
- ✅ `SKILL.md`（必需）
- 📄 `README.md`（可选，不存在会自动生成）
- 📁 `scripts/`（可选）
- 📁 其他文件/目录（可选）

## 示例

### 上传新 skill
```
用户：把 feishu-meeting 这个 skill 上传到 GitHub
AI：好的，开始上传...
    [执行脚本]
    ✅ 已上传到 https://github.com/MaoFelix009/feishu-meeting
    📦 安装命令：git clone https://github.com/MaoFelix009/feishu-meeting.git ~/.workbuddy/skills/feishu-meeting
```

### 更新已有 skill
```
用户：更新 tmc-huidan 的 GitHub 仓库
AI：检测到仓库已存在，将更新文件...
    [执行脚本]
    ✅ 已更新 https://github.com/MaoFelix009/tmc-huidan
```
