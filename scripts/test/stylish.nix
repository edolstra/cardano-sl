{ runCommand, stylish-haskell, src, lib, git }:

let
  cleanSourceFilter = with lib;
    name: type: let baseName = baseNameOf (toString name); in (
      (type == "regular" && hasSuffix ".hs" baseName) ||
      (type == "regular" && hasSuffix ".yaml" baseName) ||
      (type == "directory")
    );
  src' = builtins.filterSource cleanSourceFilter src;
in
runCommand "cardano-stylish-check" { buildInputs = [ stylish-haskell git ]; } ''
  set +e
  cp -a ${src'} tmp-cardano
  chmod -R 0755 tmp-cardano
  cd tmp-cardano
  git init
  git add -A
  find . -type f -name "*hs" -not -path '.git' -not -path '*.stack-work*' -not -name 'HLint.hs' -exec stylish-haskell -i {} \;
  git diff --exit-code
  EXIT_CODE=$?
  if [[ $EXIT_CODE != 0 ]]
  then
    echo "*** Stylish-haskell found changes that need addressed first"
    echo "*** Please run scripts/haskell/stylish.sh and commit changes"
    exit $EXIT_CODE
  else
    echo $EXIT_CODE > $out
  fi
''
