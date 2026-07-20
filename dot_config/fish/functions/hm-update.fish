function hm-update --description 'Update, check, and build the pinned Home Manager flake'
    if not command -q nix
        echo 'hm-update: nix is not available' >&2
        return 1
    end
    if not command -q chezmoi
        echo 'hm-update: chezmoi is not available' >&2
        return 1
    end
    if not command -q jq
        echo 'hm-update: jq is not available' >&2
        return 1
    end

    set -l source_dir (chezmoi source-path)
    or return
    set -l state_home $HOME/.local/state
    if set -q XDG_STATE_HOME
        set state_home $XDG_STATE_HOME
    end
    set -l configuration_file $state_home/dotfiles/home-manager-configuration
    set -l configuration
    if test -r $configuration_file
        set configuration (string trim < $configuration_file)
    else
        set configuration (chezmoi data --format=json | \
            jq -r '.homeManagerConfiguration // empty')
        or return
    end
    if test -z "$configuration"
        echo 'hm-update: no activated Home Manager configuration is recorded' >&2
        return 1
    end

    set -l flake "path:$source_dir/nix"
    echo "==> Updating $source_dir/nix/flake.lock"
    nix flake update --flake "$flake"
    or return

    echo '==> Checking Home Manager flake'
    nix flake check --no-write-lock-file "$flake"
    or return

    echo "==> Building $configuration"
    nix build --no-link --no-write-lock-file \
        "$flake#homeConfigurations.\"$configuration\".activationPackage"
    or return

    echo "Home Manager update is ready for review in $source_dir/nix/flake.lock"
end
