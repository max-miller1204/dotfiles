function gwf
    set -l common_dir (realpath (git rev-parse --git-common-dir 2>/dev/null)); or begin
        echo "gwf: not inside a git repository" >&2
        return 1
    end
    set -l main_abs (realpath "$common_dir/..")

    set -l source_abs ""
    set -l branch ""
    set -l self_mode false

    if test (count $argv) -gt 0
        set branch $argv[1]
        set -l base (basename $main_abs)
        set -l parent (dirname $main_abs)
        set source_abs "$parent/$base--$branch"
        if not test -d $source_abs
            echo "gwf: no worktree found at $source_abs" >&2
            return 1
        end
    else
        set -l git_dir (git rev-parse --git-dir 2>/dev/null); or return 1
        set -l resolved_git_dir (realpath $git_dir)
        if test "$resolved_git_dir" = "$common_dir"
            echo "gwf: already in the main worktree; pass a branch name to fold a worktree" >&2
            return 1
        end
        set branch (git branch --show-current 2>/dev/null); or return 1
        set source_abs (pwd -P)
        set self_mode true
    end

    if not gum confirm "Apply '$branch' to main, stage, remove worktree, and close pane?"
        return 1
    end

    set -l has_tracked (git -C $source_abs diff HEAD --name-only; git -C $source_abs diff --cached --name-only)
    set -l untracked (git -C $source_abs ls-files --others --exclude-standard)

    if test -n "$has_tracked"
        git -C $source_abs diff HEAD | git -C $main_abs apply --index - 2>/dev/null
        or git -C $source_abs diff HEAD | git -C $main_abs apply --3way -
    end

    for f in $untracked
        mkdir -p (dirname "$main_abs/$f")
        cp "$source_abs/$f" "$main_abs/$f"
    end

    git -C $main_abs add .
    git -C $main_abs status --short
    echo "Applied and staged in $main_abs"

    set -l self_pane ""
    set -l other_panes
    if test -n "$TMUX"
        if test "$self_mode" = true
            set self_pane $TMUX_PANE
        else
            for line in (tmux list-panes -a -F "#{pane_id} #{pane_current_path}")
                set -l parts (string split -m 1 " " -- $line)
                set -l pid $parts[1]
                set -l ppath $parts[2]
                if test "$ppath" = "$source_abs"; or string match -q "$source_abs/*" -- $ppath
                    set -a other_panes $pid
                end
            end
        end
    end

    cd $main_abs; or return 1
    git worktree remove $source_abs --force; or return 1
    git branch -D $branch

    for pid in $other_panes
        tmux kill-pane -t $pid 2>/dev/null
    end
    if test -n "$self_pane"
        tmux kill-pane -t $self_pane 2>/dev/null
    end
end
