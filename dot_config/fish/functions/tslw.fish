function tslw
    if test (count $argv) -lt 2
        echo "Usage: tslw <cmd> <branch1> [branch2 ...]"
        echo "  Pass \"\" as cmd to skip auto-running anything."
        return 1
    end
    if test -z "$TMUX"
        echo "You must start tmux to use tslw."
        return 1
    end
    set -l cmd $argv[1]
    set -l branches $argv[2..-1]

    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null); or begin
        echo "tslw: not inside a git repository" >&2
        return 1
    end
    set -l main_abs (realpath "$common_dir/..")
    set -l base (basename $main_abs)
    set -l parent (dirname $main_abs)

    set -l wt_paths
    for branch in $branches
        set -l wt_path "$parent/$base--$branch"
        if not test -d $wt_path
            git -C $main_abs worktree add -b $branch $wt_path 2>/dev/null
            or git -C $main_abs worktree add $wt_path $branch
            or begin
                echo "tslw: failed to create worktree for $branch" >&2
                return 1
            end
        end
        set -a wt_paths $wt_path
    end

    set -l new_panes
    set -l split_target $TMUX_PANE
    for wt in $wt_paths
        set -l new_pane (tmux split-window -h -t $split_target -c $wt -P -F "#{pane_id}")
        set -a new_panes $new_pane
        set split_target $new_pane
        tmux select-layout -t $TMUX_PANE tiled
    end
    if test -n "$cmd"
        for pane in $new_panes
            tmux send-keys -t $pane $cmd C-m
        end
    end
    tmux select-pane -t $new_panes[1]
end
