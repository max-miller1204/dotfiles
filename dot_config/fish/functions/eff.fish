function eff
    set -l file (ff)
    if test -n "$file"
        $EDITOR $file
    end
end
