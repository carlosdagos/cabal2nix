module Distribution.Nixpkgs.Haskell.FromCabal.Normalize ( normalize, normalizeCabalFlags ) where

import Data.Function
import Data.List
import Data.Set ( Set )
import qualified Data.Set as Set
import Data.String
import Distribution.Nixpkgs.Haskell
import Distribution.Nixpkgs.Haskell.FromCabal.CorePackages
import Distribution.Nixpkgs.Meta
import Distribution.Package
import Distribution.PackageDescription ( FlagAssignment, FlagName(..) )
import Distribution.Simple.Utils ( lowercase )
import Internal.Lens
import Internal.Regex ( regsubmatch )
import Language.Nix hiding ( quote )

normalize :: Derivation -> Derivation
normalize drv = drv
  & over libraryDepends (normalizeBuildInfo (packageName drv))
  & over executableDepends (normalizeBuildInfo (packageName drv))
  & over testDepends (normalizeBuildInfo (packageName drv))
  & over metaSection normalizeMeta
  & over cabalFlags normalizeCabalFlags
  & jailbreak %~ (&& (packageName drv /= PackageName "jailbreak-cabal"))

normalizeBuildInfo :: PackageName -> BuildInfo -> BuildInfo
normalizeBuildInfo (PackageName pname) bi = bi
  & haskell %~ (Set.filter (\b -> view localName b /= fromString pname))
  & tool %~ (Set.filter (\b -> view localName b /= fromString pname))
  & tool %~ Set.filter (\n -> n^.localName.ident `notElem` coreBuildTools)

  {-
  {
  , testDepends  = normalizeNixNames (Set.delete pname testDepends)
  , extraLibs    = normalizeNixLibs extraLibs
  , pkgConfDeps  = normalizeNixLibs pkgConfDeps
  , configureFlags = normalizeSet configureFlags
  }
-}

normalizeMeta :: Meta -> Meta
normalizeMeta = over description normalizeSynopsis
              . over maintainers normalizeMaintainers
              . over platforms normalizePlatforms

normalizeSynopsis :: String -> String
normalizeSynopsis desc
  | null desc                                             = []
  | last desc == '.' && length (filter ('.'==) desc) == 1 = normalizeSynopsis (init desc)
  | otherwise                                             = quote (unwords (words desc))

quote :: String -> String
quote ('\\':c:cs) = '\\' : c : quote cs
quote ('"':cs)    = '\\' : '"' : quote cs
quote (c:cs)      = c : quote cs
quote []          = []

normalizeSet :: Set String -> Set String
normalizeSet = Set.filter (not . null)

-- normalizeNixNames :: Set String -> Set String
-- normalizeNixNames = normalizeSet . Set.map toNixName

-- normalizeNixLibs :: Set String -> Set String
-- normalizeNixLibs = normalizeSet . Set.fromList . concatMap libNixName . Set.toList

-- normalizeNixBuildTools :: Set Identifier -> Set Identifier
-- normalizeNixBuildTools = Set.fromList . concatMap buildToolNixName . Set.toList

-- |Strip any kind of path prefix from maintainer names, filter duplicates, and
-- sort the resulting list alphabetically.
--
-- >>> normalizeMaintainers $ Set.fromList ["self.stdenv.lib.maintainers.foobar", "foobar"]
-- fromList ["foobar"]
--
-- >>> normalizeMaintainers $ Set.fromList ["any.prefix.is.recognized.yo", "abc.def"]
-- fromList ["def","yo"]

normalizeMaintainers :: Set String -> Set String
normalizeMaintainers = normalizeSet . Set.map
  (\m -> (m `regsubmatch` "^([^.].*\\.)?([^.]+)$") !! 1)

normalizePlatforms :: Set String -> Set String
normalizePlatforms = normalizeSet . Set.map
  (\p -> if '.' `elem` p then p else "stdenv.lib.platforms." ++ p)


-- |When a flag is specified multiple times, the first occurrence
-- counts. This is counter-intuitive, IMHO, but it's how cabal does it.
-- Flag names are spelled in all lowercase.
--
-- >>> normalizeCabalFlags [(FlagName "foo", True), (FlagName "FOO", True), (FlagName "Foo", False)]
-- [(FlagName "foo",True)]

normalizeCabalFlags :: FlagAssignment -> FlagAssignment
normalizeCabalFlags flags' = nubBy ((==) `on` fst) (sortBy (compare `on` fst) flags)
  where
    flags = [ (FlagName (lowercase n), b) | (FlagName n, b) <- flags' ]