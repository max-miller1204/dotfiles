function gwc
    set -l common_dir (realpath (git rev-parse --git-common-dir 2>/dev/null)); or begin
        echo "gwc: not inside a git repository" >&2
        return 1
    end
    set -l main_abs (realpath "$common_dir/..")

    set -l branch ""
    set -l source_abs ""
    if test (count $argv) -gt 0
        set branch $argv[1]
        set -l base (basename $main_abs)
        set -l parent (dirname $main_abs)
        set source_abs "$parent/$base--$branch"
        if not test -d $source_abs
            echo "gwc: no worktree found at $source_abs" >&2
            return 1
        end
    else
        set -l git_dir (git rev-parse --git-dir 2>/dev/null); or return 1
        set -l resolved_git_dir (realpath $git_dir)
        if test "$resolved_git_dir" = "$common_dir"
            echo "gwc: already in the main worktree; pass a branch name to cherry-pick" >&2
            return 1
        end
        set branch (git branch --show-current 2>/dev/null); or return 1
        set source_abs (pwd -P)
    end

    set -l target (git -C $main_abs branch --show-current 2>/dev/null)
    if test -z "$target"
        echo "gwc: main worktree is detached; cannot determine target branch" >&2
        return 1
    end
    if test "$target" = "$branch"
        echo "gwc: '$branch' is already checked out in the main worktree" >&2
        return 1
    end

    set -l commits (git -C $main_abs rev-list --reverse $target..$branch)
    if test -z "$commits"
        echo "gwc: no commits on '$branch' ahead of '$target' — use gwa for uncommitted diffs"
        return 0
    end

    set -l n (count $commits)
    echo "Cherry-picking $n commit(s) from '$branch' onto '$target':"
    for c in $commits
        git -C $main_abs log -1 --oneline $c
    end

    git -C $main_abs cherry-pick $commits
    set -l rc $status

    # Drive the sequencer to completion, --skipping commits that are
    # patch-equivalent to ones already on the integration branch. Handles
    # both single-redundant and mixed cases without dropping non-empty
    # siblings. Use --absolute-git-dir so the check works when invoked
    # from a chunk worktree with no args.
    set -l git_dir (git -C $main_abs rev-parse --absolute-git-dir 2>/dev/null)
    set -l skipped 0
    while test $rc -ne 0
        set -l porcelain (git -C $main_abs status --porcelain --untracked-files=no)
        if test -n "$git_dir" -a -e "$git_dir/CHERRY_PICK_HEAD" -a -z "$porcelain"
            set skipped (math $skipped + 1)
            git -C $main_abs cherry-pick --skip >/dev/null 2>&1
            set rc $status
            continue
        end
        echo ""
        echo "gwc: cherry-pick stopped. Resolve in $main_abs, then:"
        echo "  git -C $main_abs add <files>"
        echo "  git -C $main_abs cherry-pick --continue"
        echo "Or abort: git -C $main_abs cherry-pick --abort"
        return $rc
    end

    if test $skipped -eq $n
        echo ""
        echo "gwc: all $n commit(s) from '$branch' are already on '$target' (skipped)."
        echo "  If '$branch' is fully folded, run gwf '$branch' to tear it down."
    else if test $skipped -gt 0
        echo "Cherry-picked "(math $n - $skipped)" commit(s); skipped $skipped already-applied into $main_abs"
    else
        echo "Cherry-picked into $main_abs"
    end
end
