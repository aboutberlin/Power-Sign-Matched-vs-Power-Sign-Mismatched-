#!/usr/bin/env bash
# 同步脚本：本地 <-> origin (GitHub)
#
# 流程：
#   1) fetch 远端
#   2) 如果远端比本地新 -> fast-forward / merge
#   3) 本地如果有改动 -> git add + commit
#   4) push
#
# 用法：
#   ./sync.sh                 # commit 信息自动带时间戳
#   ./sync.sh "some message"  # 自定义 commit 信息

set -e
cd "$(dirname "$0")"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
MSG="${1:-update $(date +'%Y-%m-%d %H:%M:%S')}"

echo "[sync] remote=origin branch=$BRANCH"

# 0) 保护：如果上次 merge/rebase 未完成，直接退出
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    echo "[sync] ERROR: a rebase is in progress. Run 'git rebase --abort' first."
    exit 1
fi
if [ -f .git/MERGE_HEAD ]; then
    echo "[sync] ERROR: a merge is in progress. Resolve it or run 'git merge --abort'."
    exit 1
fi

# 1) 拉取远端信息
echo "[sync] fetching..."
git fetch origin "$BRANCH"

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH")
BASE=$(git merge-base HEAD "origin/$BRANCH")

# 2) 根据关系处理 pull/merge
if [ "$LOCAL" = "$REMOTE" ]; then
    echo "[sync] local == remote, nothing to pull"
elif [ "$LOCAL" = "$BASE" ]; then
    echo "[sync] remote ahead, fast-forwarding"
    git merge --ff-only "origin/$BRANCH"
elif [ "$REMOTE" = "$BASE" ]; then
    echo "[sync] local ahead, will push after staging"
else
    echo "[sync] diverged, merging remote into local"
    if ! git merge --no-edit --no-ff "origin/$BRANCH"; then
        echo ""
        echo "[sync] MERGE CONFLICT. Resolve files, then run:"
        echo "         git add <files> && git commit"
        echo "         ./sync.sh"
        echo "       Or abort with: git merge --abort"
        exit 1
    fi
fi

# 3) 提交本地改动
git add -A
if git diff --cached --quiet; then
    echo "[sync] no local changes to commit"
else
    git commit -m "$MSG"
fi

# 4) 推送
echo "[sync] pushing..."
git push origin "$BRANCH"
echo "[sync] done"
