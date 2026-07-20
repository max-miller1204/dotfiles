# Narrow a package to an explicit list of bin commands so only the declared
# executables become global Home Manager owners.
{ lib, pkgs }:
name: package: commands:
pkgs.runCommand "${name}-${package.version}-commands" { } ''
  mkdir -p "$out/bin"
  ${lib.concatMapStringsSep "\n" (command: ''
    test -x "${package}/bin/${command}"
    ln -s "${package}/bin/${command}" "$out/bin/${command}"
  '') commands}
''
