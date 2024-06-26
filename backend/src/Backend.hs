{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}

module Backend where

import Backend.NotifyHandler (notifyHandler)
import Backend.RequestHandler (requestHandler)
import Backend.Schema (withDb)
import Backend.Transaction (Transaction, runTransaction)
import Backend.ViewSelectorHandler (viewSelectorHandler)
import Common.Route (BackendRoute (..), FrontendRoute, fullRouteEncoder)
import Control.Exception.Safe (finally)
import Control.Monad.IO.Class (MonadIO)
import Obelisk.Backend (Backend (..))
import Obelisk.Route
import qualified Rhyolite.Backend.App as RhyoliteApp
import qualified Snap.Core as Snap

backend :: Backend BackendRoute FrontendRoute
backend =
  Backend
    { _backend_run = backendRun,
      _backend_routeEncoder = fullRouteEncoder
    }

backendRun :: MonadIO m => ((R BackendRoute -> Snap.Snap ()) -> IO a) -> m a
backendRun serve = withDb $ \dbPool -> do
  let runTransaction' :: Transaction mode a -> IO a
      runTransaction' = runTransaction dbPool
  (handleListen, wsFinalizer) <-
    RhyoliteApp.serveDbOverWebsockets
      (RhyoliteApp.convertPostgresPool dbPool)
      (requestHandler runTransaction')
      (notifyHandler runTransaction')
      (RhyoliteApp.QueryHandler $ viewSelectorHandler runTransaction')
      RhyoliteApp.functorFromWire
      RhyoliteApp.standardPipeline
  flip finally wsFinalizer $
    serve $ \case
      BackendRoute_Missing :/ _ -> Snap.writeText "404 Page not found"
      BackendRoute_Listen :/ _ -> handleListen
