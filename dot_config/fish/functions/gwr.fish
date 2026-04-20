function gwr
    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null); or begin
        echo "gwr: not inside a git repository" >&2
        return 1
    end
    set -l repo_root (realpath "$common_dir/..")

    set -l target_path ""
    set -l target_branch ""
    set -l self_mode false

    if test (count $argv) -gt 0
        set target_branch $argv[1]
        set -l base (basename $repo_root)
        set -l parent (dirname $repo_root)
        set target_path "$parent/$base--$target_branch"
        if not test -d $target_path
            echo "gwr: no worktree found at $target_path" >&2
            return 1
        end
    else
        set -l git_dir (git rev-parse --git-dir 2>/dev/null); or return 1
        set -l resolved_git_dir (realpath $git_dir)
        set -l resolved_common_dir (realpath $common_dir)
        if test "$resolved_git_dir" = "$resolved_common_dir"
            echo "gwr: current directory is the main worktree; pass a branch name to remove a worktree" >&2
            return 1
        end
        set target_path (pwd)
        set target_branch (git branch --show-current 2>/dev/null); or return 1
        set self_mode true
    end

    if not gum confirm "Remove worktree '$target_path' and branch '$target_branch'?"
        return 1
    end

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
                if test "$ppath" = "$target_path"; or string match -q "$target_path/*" -- $ppath
                    set -a other_panes $pid
                end
            end
        end
    end

    cd $repo_root; or return 1
    git worktree remove $target_path --force; or return 1
    git branch -D $target_branch

    for pid in $other_panes
        tmux kill-pane -t $pid 2>/dev/null
    end
    if test -n "$self_pane"
        tmux kill-pane -t $self_pane 2>/dev/null
    end
end
