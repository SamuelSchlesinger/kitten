{-# LANGUAGE OverloadedStrings #-}

module Kitten.Interpret
  ( interpret
  ) where

import Data.IORef (newIORef, modifyIORef', readIORef, writeIORef)
import Kitten.Definition (mainName)
import Kitten.Dictionary (Dictionary)
import Kitten.Name
import Kitten.Term (Term(..), Value(..))
import Kitten.Type (Type(..))
import Text.PrettyPrint.HughesPJClass (Pretty(..))
import qualified Kitten.Dictionary as Dictionary
import qualified Kitten.Entry as Entry
import qualified Text.PrettyPrint as Pretty

interpret :: Dictionary -> IO ()
interpret dictionary = do
  stackRef <- newIORef []
  localsRef <- newIORef []
  currentClosureRef <- newIORef []
  let

    word :: Qualified -> IO ()
    word name = case Dictionary.lookup name dictionary of
      Just (Entry.Word _ _ _ _ _ Nothing) -> error "nobody home"
      Just (Entry.Word _ _ _ _ _ (Just body)) -> term body
      _ -> error "not a word about this"

    term :: Term Type -> IO ()
    term t = case t of
      Call _ _ -> call
      Compose _ a b -> term a >> term b
      Drop _ _ -> modifyIORef' stackRef tail
      Generic _ _ _ -> error "generic"
      Group t' -> term t'
      Identity _ _ -> return ()
      If _ _true _false _ -> error "if"
      Lambda _ _name _ body _ -> do
        (a : r) <- readIORef stackRef
        ls <- readIORef localsRef
        writeIORef stackRef r
        writeIORef localsRef (a : ls)
        term body
        modifyIORef' localsRef tail
      Match _ _cases _mElse _ -> error "match"
      New _ _index _ -> error "new"
      NewClosure _ size _ -> do
        r <- readIORef stackRef
        let (Name name : closure, r') = splitAt (size + 1) r
        writeIORef stackRef (Closure name closure : r')
      NewVector _ _size _ -> error "new.vector"
      Push _ value _ -> push value
      Swap _ _ -> do
        (a : b : r) <- readIORef stackRef
        writeIORef stackRef (b : a : r)
      With _ _ _ -> call
      Word _ _ (QualifiedName name) _args _ -> word name
      Word _ _ name _ _ -> error "unresolved word name"

    call :: IO ()
    call = do
      (Closure name closure : r) <- readIORef stackRef
      writeIORef stackRef r
      modifyIORef' currentClosureRef (closure :)
      word name
      modifyIORef' currentClosureRef tail

    push :: Value Type -> IO ()
    push value = case value of
      Closed (ClosureIndex index) -> do
        (currentClosure : _) <- readIORef currentClosureRef
        modifyIORef' stackRef ((currentClosure !! index) :)
      Local (LocalIndex index) -> do
        locals <- readIORef localsRef
        modifyIORef' stackRef ((locals !! index) :)
      _ -> modifyIORef' stackRef (value :)

  word mainName
  stack <- readIORef stackRef
  case stack of
    [] -> return ()
    _ -> putStrLn $ Pretty.render $ Pretty.vcat $ "Stack:" : map pPrint stack
