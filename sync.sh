#!/usr/bin/env bash
# 同步脚本：本地 <-> GitHub(origin) + Overleaf(overleaf)
#
# 流程：
#   1) 本地改动自动 add/commit
#   2) 拉取并合并 origin/<当前分支>
#   3) 拉取并合并 overleaf/master
#   4) 推送到 origin/<当前分支>
#   5) 推送到 overleaf/master
#
# 用法：
#   ./sync.sh                 # commit 信息自动带时间戳
#   ./sync.sh "some message"  # 自定义 commit 信息
#
# 可选环境变量：
#   OVERLEAF_URL  # overleaf remote 不存在时自动添加的地址

set -euo pipefail
cd "$(dirname "$0")"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
MSG="${1:-update $(date +'%Y-%m-%d %H:%M:%S')}"
OVERLEAF_URL_DEFAULT="https://git.overleaf.com/69ef9039aaa2cee52e381529"
OVERLEAF_URL="${OVERLEAF_URL:-$OVERLEAF_URL_DEFAULT}"
OVERLEAF_REMOTE="overleaf"
OVERLEAF_BRANCH="master"

echo "[sync] branch=$BRANCH"

# 0) 保护：如果上次 merge/rebase 未完成，直接退出
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    echo "[sync] ERROR: a rebase is in progress. Run 'git rebase --abort' first."
    exit 1
fi
if [ -f .git/MERGE_HEAD ]; then
    echo "[sync] ERROR: a merge is in progress. Resolve it or run 'git merge --abort'."
    exit 1
fi

# 1) 提交本地改动（先提交，避免后续 merge 被工作区阻塞）
git add -A
if git diff --cached --quiet; then
    echo "[sync] no local changes to commit"
else
    git commit -m "$MSG"
fi

# 2) 确保 overleaf remote 存在
if git remote get-url "$OVERLEAF_REMOTE" >/dev/null 2>&1; then
    echo "[sync] $OVERLEAF_REMOTE remote exists"
else
    echo "[sync] adding $OVERLEAF_REMOTE remote: $OVERLEAF_URL"
    git remote add "$OVERLEAF_REMOTE" "$OVERLEAF_URL"
fi

sync_from_remote() {
    local remote_name="$1"
    local remote_branch="$2"
    local allow_unrelated="${3:-0}"
    local remote_ref="${remote_name}/${remote_branch}"

    if ! git show-ref --verify --quiet "refs/remotes/${remote_ref}"; then
        echo "[sync] ${remote_ref} not found after fetch, skip merge"
        return 0
    fi

    local local_sha remote_sha base_sha
    local_sha="$(git rev-parse HEAD)"
    remote_sha="$(git rev-parse "$remote_ref")"
    base_sha="$(git merge-base HEAD "$remote_ref")"

    if [ "$local_sha" = "$remote_sha" ]; then
        echo "[sync] HEAD == ${remote_ref}, nothing to merge"
    elif [ "$local_sha" = "$base_sha" ]; then
        echo "[sync] ${remote_ref} ahead, fast-forwarding"
        git merge --ff-only "$remote_ref"
    elif [ "$remote_sha" = "$base_sha" ]; then
        echo "[sync] local ahead of ${remote_ref}, no merge needed"
    else
        echo "[sync] diverged from ${remote_ref}, merging"
        if [ "$allow_unrelated" = "1" ]; then
            if ! git merge --no-edit --no-ff --allow-unrelated-histories "$remote_ref"; then
                echo "[sync] MERGE CONFLICT with ${remote_ref}."
                echo "[sync] Resolve conflicts then rerun ./sync.sh"
                exit 1
            fi
        else
            if ! git merge --no-edit --no-ff "$remote_ref"; then
                echo "[sync] MERGE CONFLICT with ${remote_ref}."
                echo "[sync] Resolve conflicts then rerun ./sync.sh"
                exit 1
            fi
        fi
    fi
}

# 3) fetch 两个 remote
echo "[sync] fetching origin/$BRANCH"
git fetch origin "$BRANCH"
echo "[sync] fetching $OVERLEAF_REMOTE/$OVERLEAF_BRANCH"
git fetch "$OVERLEAF_REMOTE" "$OVERLEAF_BRANCH" || true

# 4) 先同步 origin，再同步 overleaf
sync_from_remote "origin" "$BRANCH" "0"
sync_from_remote "$OVERLEAF_REMOTE" "$OVERLEAF_BRANCH" "1"

# 5) 推送到 GitHub 与 Overleaf
echo "[sync] pushing origin/$BRANCH"
git push origin "$BRANCH"
echo "[sync] pushing $OVERLEAF_REMOTE $BRANCH:$OVERLEAF_BRANCH"
git push "$OVERLEAF_REMOTE" "$BRANCH:$OVERLEAF_BRANCH"

echo "[sync] done"
