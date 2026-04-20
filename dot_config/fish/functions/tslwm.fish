function tslwm
    if test (count $argv) -lt 2
        echo "Usage: tslwm <cmd> <branch1> [branch2 ...]"
        return 1
    end
    if test -z "$TMUX"
        echo "You must start tmux to use tslwm."
        return 1
    end
    set -l cmd $argv[1]
    set -l branches $argv[2..-1]

    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null); or begin
        echo "tslwm: not inside a git repository" >&2
        return 1
    end
    set -l main_abs (realpath "$common_dir/..")
    set -l base (basename $main_abs)
    set -l parent (dirname $main_abs)

    for branch in $branches
        set -l wt_path "$parent/$base--$branch"
        if not test -d $wt_path
            git -C $main_abs worktree add -b $branch $wt_path 2>/dev/null
            or git -C $main_abs worktree add $wt_path $branch
            or begin
                echo "tslwm: failed to create worktree for $branch" >&2
                continue
            end
        end
        set -l new_win (tmux new-window -c $wt_path -n $branch -P -F "#{pane_id}")
        if test -n "$cmd"
            tmux send-keys -t $new_win $cmd C-m
        end
    end
end
