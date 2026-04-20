function compress
    if test -z "$argv[1]"
        echo "Usage: compress <directory>"
        return 1
    end
    set -l target (string trim -r -c "/" $argv[1])
    tar -czf "$target.tar.gz" $target
end
