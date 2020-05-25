{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.Zettelkasten.Query.Eval where

import Control.Monad.Except
import Control.Monad.Writer
import Data.Dependent.Sum
import Data.Some
import Neuron.Zettelkasten.Connection
import Neuron.Zettelkasten.Query (runZettelQuery)
import Neuron.Zettelkasten.Query.Error
import Neuron.Zettelkasten.Query.Parser (queryFromURILink)
import Neuron.Zettelkasten.Zettel
import Reflex.Dom.Pandoc.URILink (URILink, queryURILinks)
import Relude
import Text.Pandoc.Definition (Pandoc)

-- | Evaluate the given query link and return its results.
--
-- Return Nothing if the link is not a query.
--
-- We need the full list of zettels, for running the query against.
evalQueryLink ::
  ( MonadError QueryParseError m,
    MonadReader [Zettel] m
  ) =>
  URILink ->
  m (Maybe (DSum ZettelQuery Identity))
evalQueryLink link =
  queryFromURILink link >>= \case
    Nothing -> pure Nothing
    Just someQ -> fmap Just $ do
      withSome someQ $ \q -> do
        zs <- ask
        let res = runZettelQuery zs q
        pure $ q :=> Identity res

queryConnections ::
  forall m.
  ( -- Errors are written aside, accumulating valid connections.
    MonadWriter [QueryParseError] m,
    -- Running queries requires the zettels list.
    MonadReader [Zettel] m
  ) =>
  Pandoc ->
  m [(Maybe Connection, Zettel)]
queryConnections doc =
  fmap concat $ forM (queryURILinks doc) $ \ul -> do
    emres <- runExceptT $ evalQueryLink ul
    case emres of
      Left e -> do
        tell [e]
        pure []
      Right mres ->
        pure $ maybe [] getConnections mres
  where
    getConnections :: DSum ZettelQuery Identity -> [(Maybe Connection, Zettel)]
    getConnections = \case
      ZettelQuery_ZettelByID _ mconn :=> Identity mres ->
        maybe [] pure $ (mconn,) <$> mres
      ZettelQuery_ZettelsByTag _ mconn _mview :=> Identity res ->
        (mconn,) <$> res
      ZettelQuery_Tags _ :=> _ ->
        mempty
