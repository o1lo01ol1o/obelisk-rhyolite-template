{-# LANGUAGE CPP #-}

module Frontend.Selection where

import Control.Lens.Operators ((^.))
import Data.Text (Text)
import GHCJS.DOM.EventTargetClosures (unsafeEventName)
import qualified GHCJS.DOM as Dom
import qualified GHCJS.DOM.EventM as EventM
import qualified GHCJS.DOM.Node as Node
import qualified GHCJS.DOM.Selection as Selection
import qualified GHCJS.DOM.Types as Dom
import qualified GHCJS.DOM.Window as Window
import Language.Javascript.JSaddle.Object (js)
import Reflex.Dom.Core (
    Event, Prerender,
    ffor, mapMaybe, never, performEvent, prerender, switchDyn, wrapDomEvent, delay
  )

import Control.Exception (SomeException)
import Control.Monad.Catch (catch)

selectionStart :: (Prerender js t m, Applicative m) => m (Event t (Text, Int, Text, Int))
selectionStart = fmap switchDyn $ prerender (pure never) $ do
  window <- Dom.currentWindowUnchecked
  selectStarted' <- wrapDomEvent window (`EventM.on` selectstart) (pure ())
  -- In JSaddle calling 'getSelection' must be delayed by a frame in order to get
  -- the most recent result. However it doesn't have this problem in native GHCJS.
#if defined(ghcjs_HOST_OS)
  let selectedStart = selectStarted'
#else
  selectStarted <- delay 0 selectStarted'
#endif
  fmap (mapMaybe id) $ performEvent $ ffor selectStarted $ \() -> Dom.liftJSM $ do
    sel <- Window.getSelectionUnchecked window
    let liftA4 f a b c d = f <$> a <*> b <*> c <*> d
    (liftA4.liftA4) (,,,)
      (getStartData =<< Selection.getAnchorNode sel)
      (Just . fromIntegral <$> Selection.getAnchorOffset sel)
      (getStartData =<< Selection.getExtentNode sel)
      (Just . fromIntegral <$> Selection.getExtentOffset sel)

  where
    selectstart :: EventM.EventName self Dom.Event
    selectstart = unsafeEventName (Dom.toJSString (s_ "selectstart"))

    getStartData = \case
      Nothing -> pure Nothing
      Just node -> (do
          parentNode <- Node.getParentNodeUnchecked node
          Dom.fromJSVal @Text =<< Node.unNode parentNode ^. js (s_ "dataset") . js (s_ "start")
        ) `catch` \(_ :: SomeException) -> pure Nothing

    s_ :: String -> String = id
