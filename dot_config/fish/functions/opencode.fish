function opencode --wraps opencode --description 'Launch the OpenCode TUI in auto mode'
    if test (count $argv) -eq 0
        command opencode --auto
    else
        command opencode $argv
    end
end
