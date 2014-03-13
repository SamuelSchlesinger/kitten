{-# LANGUAGE OverloadedStrings #-}

module Kitten.Resolve
  ( resolve
  ) where

import Control.Applicative hiding (some)
import Control.Arrow
import Data.Maybe
import Data.Monoid
import Data.Text (Text)
import Data.Vector (Vector)
import GHC.Exts

import qualified Data.Text as T
import qualified Data.Traversable as T
import qualified Data.Vector as V

import Kitten.Def
import Kitten.Error
import Kitten.Fragment
import Kitten.Location
import Kitten.Name
import Kitten.Operator
import Kitten.Resolve.Monad
import Kitten.Tree
import Kitten.Util.Function

resolve
  :: Fragment ParsedTerm
  -> Either [ErrorGroup] (Fragment ResolvedTerm)
resolve fragment = do
  case reportDuplicateDefs allNamesAndLocs of
    [] -> return ()
    errors -> Left errors
  evalResolution emptyEnv $ guardLiftM2
    (\defs terms -> fragment
      { fragmentDefs = defs
      , fragmentTerms = terms
      })
    (resolveDefs (fragmentDefs fragment))
    (guardMapM resolveTerm (fragmentTerms fragment))
  where
  allNamesAndLocs = namesAndLocs (fragmentDefs fragment)
  emptyEnv = Env
    { envDefs = fragmentDefs fragment
    , envScope = []
    }

namesAndLocs :: Vector (Def a) -> [(Text, Location)]
namesAndLocs = map (defName &&& defLocation) . V.toList

reportDuplicateDefs
  :: [(Text, Location)]
  -> [ErrorGroup]
reportDuplicateDefs param = mapMaybe reportDuplicate . groupWith fst $ param
  where
  reportDuplicate defs = case defs of
    [] -> Nothing
    [_] -> Nothing
    ((name, loc) : duplicates) -> Just . ErrorGroup
      $ CompileError loc Error ("duplicate definition of " <> name)
      : for duplicates
        (\ (_, here) -> CompileError here Note "also defined here")

resolveDefs
  :: Vector (Def ParsedTerm)
  -> Resolution (Vector (Def ResolvedTerm))
resolveDefs = guardMapM resolveDef
  where
  resolveDef :: Def ParsedTerm -> Resolution (Def ResolvedTerm)
  resolveDef def = do
    defTerm' <- T.traverse resolveTerm (defTerm def)
    return def { defTerm = defTerm' }

resolveTerm :: ParsedTerm -> Resolution ResolvedTerm
resolveTerm unresolved = case unresolved of
  Builtin name loc -> return $ Builtin name loc
  Call hint name loc -> resolveName hint name loc
  Compose hint terms loc -> Compose hint
    <$> guardMapM resolveTerm terms
    <*> pure loc
  Lambda name term loc -> withLocal name $ Lambda name
    <$> resolveTerm term
    <*> pure loc
  PairTerm as bs loc -> PairTerm
    <$> resolveTerm as
    <*> resolveTerm bs
    <*> pure loc
  Push value loc -> Push <$> resolveValue value <*> pure loc
  VectorTerm items loc -> VectorTerm
    <$> guardMapM resolveTerm items
    <*> pure loc

resolveValue :: ParsedValue -> Resolution ResolvedValue
resolveValue unresolved = case unresolved of
  Bool value loc -> return $ Bool value loc
  Char value loc -> return $ Char value loc
  Closed{} -> error "FIXME 'Closed' appeared before resolution"
  Closure{} -> error "FIXME 'Closure' appeared before resolution"
  Float value loc -> return $ Float value loc
  Int value loc -> return $ Int value loc
  Local{} -> error "FIXME 'Local' appeared before resolution"
  Quotation term loc -> Quotation <$> resolveTerm term <*> pure loc
  String value loc -> return $ String value loc

resolveName
  :: FixityHint
  -> Text
  -> Location
  -> Resolution ResolvedTerm
resolveName hint name loc = do
  mLocalIndex <- getsEnv $ localIndex name
  case mLocalIndex of
    Just index -> return $ Push (Local (Name index) loc) loc
    Nothing -> do
      indices <- getsEnv $ defIndices name
      index <- case V.toList indices of
        [index] -> return index
        [] -> err ["undefined word '", name, "'"]
        _ -> err ["ambiguous word '", name, "'"]
      return $ Call hint (Name index) loc
  where
  err = compileError . oneError . CompileError loc Error . T.concat
