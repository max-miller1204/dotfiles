function open
    if test (uname) = Linux
        xdg-open $argv >/dev/null 2>&1 &
        disown
    else
        command open $argv
    end
end
