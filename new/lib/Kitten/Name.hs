{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Kitten.Name
  ( GeneralName(..)
  , Closed(..)
  , ClosureIndex(..)
  , ConstructorIndex(..)
  , LocalIndex(..)
  , Qualified(..)
  , Qualifier(..)
  , Root(..)
  , Unqualified(..)
  , isOperatorName
  , toParts
  , qualifiedFromQualifier
  , qualifierFromName
  ) where

import Control.Applicative (liftA2)
import Data.Char (isLetter)
import Data.Hashable (Hashable(..))
import Data.Text (Text)
import GHC.Exts (IsString(..))
import Text.PrettyPrint.HughesPJClass (Pretty(..))
import qualified Data.Text as Text
import qualified Text.PrettyPrint as Pretty

-- Names are complex. A qualified name consists of an unqualified name ('x')
-- plus a qualifier ('q::'). Name resolution is necessary because the referent
-- of an unqualified name is ambiguous without non-local knowledge.

data GeneralName
  = QualifiedName !Qualified
  | UnqualifiedName !Unqualified
  | LocalName !LocalIndex
  deriving (Eq, Ord, Show)

instance IsString GeneralName where
  fromString = UnqualifiedName . fromString

data Qualified = Qualified
  { qualifierName :: !Qualifier
  , unqualifiedName :: !Unqualified
  } deriving (Eq, Ord, Show)

data Qualifier = Qualifier !Root [Text]
  deriving (Eq, Ord, Show)

data Root = Relative | Absolute
  deriving (Eq, Ord, Show)

data Unqualified = Unqualified Text
  deriving (Eq, Ord, Show)

data Closed = ClosedLocal !LocalIndex | ClosedClosure !ClosureIndex
  deriving (Eq, Show)

newtype ClosureIndex = ClosureIndex Int
  deriving (Eq, Ord, Show)

newtype ConstructorIndex = ConstructorIndex Int
  deriving (Eq, Ord, Show)

newtype LocalIndex = LocalIndex Int
  deriving (Eq, Ord, Show)

-- TODO: Use types, not strings.
isOperatorName :: Qualified -> Bool
isOperatorName = match . unqualifiedName
  where
  match (Unqualified name) = not
    $ liftA2 (||) (Text.all isLetter) (== "_")
    $ Text.take 1 name

toParts :: Qualified -> [Text]
toParts (Qualified (Qualifier _root parts) (Unqualified part))
  = parts ++ [part]

qualifiedFromQualifier :: Qualifier -> Qualified
qualifiedFromQualifier qualifier = case qualifier of
  Qualifier _ [] -> error "qualifiedFromQualifier: empty qualifier"
  Qualifier root parts -> Qualified
    (Qualifier root $ init parts) $ Unqualified $ last parts

qualifierFromName :: Qualified -> Qualifier
qualifierFromName (Qualified (Qualifier root parts) (Unqualified name))
  = Qualifier root (parts ++ [name])

instance Hashable Qualified where
  hashWithSalt s (Qualified qualifier unqualified)
    = hashWithSalt s (0 :: Int, qualifier, unqualified)

instance Hashable Qualifier where
  hashWithSalt s (Qualifier root parts)
    = hashWithSalt s (0 :: Int, root, Text.concat parts)

instance Hashable Root where
  hashWithSalt s root = hashWithSalt s $ case root of
    Relative -> 0 :: Int
    Absolute -> 1 :: Int

instance Hashable Unqualified where
  hashWithSalt s (Unqualified name) = hashWithSalt s (0 :: Int, name)

instance IsString Unqualified where
  fromString = Unqualified . Text.pack

instance Pretty Qualified where
  pPrint qualified = pPrint (qualifierName qualified)
    Pretty.<> "::" Pretty.<> pPrint (unqualifiedName qualified)

instance Pretty Qualifier where
  pPrint (Qualifier Absolute parts) = pPrint $ Qualifier Relative $ "_" : parts
  pPrint (Qualifier Relative parts) = Pretty.text
    $ Text.unpack $ Text.intercalate "::" parts

instance Pretty Unqualified where
  pPrint (Unqualified unqualified) = Pretty.text $ Text.unpack unqualified

instance Pretty GeneralName where
  pPrint name = case name of
    QualifiedName qualified -> pPrint qualified
    UnqualifiedName unqualified -> pPrint unqualified
    LocalName (LocalIndex i) -> "local." Pretty.<> Pretty.int i

instance Pretty Closed where
  pPrint (ClosedLocal (LocalIndex index)) = Pretty.hcat
    ["local.", Pretty.int index]
  pPrint (ClosedClosure (ClosureIndex index)) = Pretty.hcat
    ["closure.", Pretty.int index]
