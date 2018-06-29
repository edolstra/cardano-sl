{ stylish-haskell, writeScriptBin }:

writeScriptBin "cardano-stylish-cleanup" ''
  find . -type f -name "*hs" -not -path '.git' -not -path '*.stack-work*' -not -name 'HLint.hs' -exec ${stylish-haskell}/bin/stylish-haskell -i {} \;
''
