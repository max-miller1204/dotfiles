function gwa
    set -l common_dir (realpath (git rev-parse --git-common-dir 2>/dev/null)); or begin
        echo "gwa: not inside a git repository" >&2
        return 1
    end
    set -l main_abs (realpath "$common_dir/..")

    set -l source_abs ""
    if test (count $argv) -gt 0
        set -l branch $argv[1]
        set -l base (basename $main_abs)
        set -l parent (dirname $main_abs)
        set source_abs "$parent/$base--$branch"
        if not test -d $source_abs
            echo "gwa: no worktree found at $source_abs" >&2
            return 1
        end
    else
        set -l git_dir (git rev-parse --git-dir 2>/dev/null); or return 1
        set -l resolved_git_dir (realpath $git_dir)
        if test "$resolved_git_dir" = "$common_dir"
            echo "gwa: already in the main worktree; pass a branch name to apply a worktree" >&2
            return 1
        end
        set source_abs (pwd -P)
    end

    set -l has_tracked (git -C $source_abs diff HEAD --name-only; git -C $source_abs diff --cached --name-only)
    set -l untracked (git -C $source_abs ls-files --others --exclude-standard)

    if test -z "$has_tracked" -a -z "$untracked"
        echo "Nothing to apply."
        return 0
    end

    if test -n "$has_tracked"
        git -C $source_abs diff HEAD | git -C $main_abs apply --index - 2>/dev/null
        or git -C $source_abs diff HEAD | git -C $main_abs apply --3way -
    end

    for f in $untracked
        mkdir -p (dirname "$main_abs/$f")
        cp "$source_abs/$f" "$main_abs/$f"
    end

    git -C $main_abs status --short
    echo "Applied to $main_abs"
end
