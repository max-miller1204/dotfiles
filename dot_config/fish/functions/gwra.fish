function gwra
    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null); or begin
        echo "gwra: not inside a git repository" >&2
        return 1
    end
    set -l main_abs (realpath "$common_dir/..")
    set -l base (basename $main_abs)
    set -l parent (dirname $main_abs)
    set -l prefix "$parent/$base--"

    set -l targets
    set -l target_branches
    set -l current_path ""
    set -l current_branch ""
    for line in (git -C $main_abs worktree list --porcelain)
        if string match -q "worktree *" -- $line
            set current_path (string replace "worktree " "" -- $line)
        else if string match -q "branch refs/heads/*" -- $line
            set current_branch (string replace "branch refs/heads/" "" -- $line)
            if string match -q "$prefix*" -- $current_path
                set -a targets $current_path
                set -a target_branches $current_branch
            end
            set current_path ""
            set current_branch ""
        end
    end

    if test (count $targets) -eq 0
        echo "gwra: no swarm worktrees to remove"
        return 0
    end

    echo "Will remove:"
    for i in (seq (count $targets))
        echo "  $targets[$i]  ($target_branches[$i])"
    end
    if not gum confirm "Remove all listed worktrees and branches?"
        return 1
    end

    cd $main_abs; or return 1

    if test -n "$TMUX"
        for line in (tmux list-panes -a -F "#{pane_id} #{pane_current_path}")
            set -l parts (string split -m 1 " " -- $line)
            set -l pid $parts[1]
            set -l ppath $parts[2]
            if test "$pid" = "$TMUX_PANE"
                continue
            end
            for t in $targets
                if test "$ppath" = "$t"; or string match -q "$t/*" -- $ppath
                    tmux kill-pane -t $pid 2>/dev/null
                    break
                end
            end
        end
    end

    for i in (seq (count $targets))
        git worktree remove --force $targets[$i]
        git branch -D $target_branches[$i]
    end
end
