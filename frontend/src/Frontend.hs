{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecursiveDo #-}

module Frontend where

import Control.Lens
import qualified Data.IntervalSet as IntervalSet
import Data.IntervalMap.Interval (Interval (..))
import qualified Data.Map.Monoidal as MMap
import Data.Semigroup (First (..))
import qualified Data.Text as T
import qualified Control.Category as Cat
import Control.Monad.Fix (MonadFix)
import Obelisk.Configs (HasConfigs (getConfig))
import Obelisk.Frontend (Frontend (..))
import Obelisk.Route.Frontend
import Reflex.Dom.Core
import Rhyolite.Api (ApiRequest, public)
import Rhyolite.Frontend.App (RhyoliteWidget, runObeliskRhyoliteWidget, watchViewSelector)

import Common.App
import Common.Route
import Common.Prelude
import Common.Schema
import Obelisk.Generated.Static

frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = el "title" $ text "Obelisk Minimal Example"
  , _frontend_body = runAppWidget appWidget
  }

runAppWidget ::
  ( HasConfigs m
  , TriggerEvent t m
  , PerformEvent t m
  , MonadHold t m
  , PostBuild t m
  , MonadFix m
  , Prerender x t m
  )
  => RoutedT t (R FrontendRoute) (RhyoliteWidget (ViewSelector SelectedCount) (ApiRequest () PublicRequest PrivateRequest) t m) a
  -> RoutedT t (R FrontendRoute) m a
runAppWidget = runObeliskRhyoliteWidget
  Cat.id
  "common/route"
  checkedFullRouteEncoder
  (BackendRoute_Listen :/ ())

type HasApp t m =
  ( MonadQuery t (ViewSelector SelectedCount) m
  , Requester t m
  , Request m ~ ApiRequest () PublicRequest PrivateRequest
  , Response m ~ Identity
  )

defaultTranslation :: TranslationId
defaultTranslation = TranslationId 1

appWidget :: forall m t. (HasApp t m, DomBuilder t m, PostBuild t m, MonadHold t m, MonadFix m) => m ()
appWidget = do
  translations <- watchTranslations
  dyn_ $ ffor translations $ \case
    Nothing -> text "Loading..."
    Just ts -> do
      text "Translations"
      el "ol" $
        for_ ts $ \t -> el "li" $ text $ _translationName t

  upClicked <- fmap (domEvent Click . fst) $ el' "div" $ text "Up"
  rec
    versesWidget <=< watchVerses $ (defaultTranslation, ) <$> range
    downClicked <- fmap (domEvent Click . fst) $ el' "div" $ text "Down"
    range <- foldDyn ($) (IntervalCO (VerseReferenceT (BookId 1) 1 1) (VerseReferenceT (BookId 1) 3 9999)) $ leftmost
     [ upClicked $> \(IntervalCO (VerseReferenceT book1 chap1 _) _) ->
         IntervalCO
           (if chap1 == 1
             then VerseReferenceT (BookId $ max 1 (unBookId book1 - 1)) 1 1
             else VerseReferenceT book1 (chap1 - 1) 1)
           (VerseReferenceT book1 (chap1 + 3) 9999)
     , downClicked $> \(IntervalCO (VerseReferenceT book1 chap1 _) _) ->
         IntervalCO (VerseReferenceT book1 (chap1 + 1) 1) (VerseReferenceT book1 (chap1 + 4) 9999)
     ]

  pure ()

  where
    versesWidget verses = mdo
      (_, selectWord) <- fmap (second (fmap getFirst)) $ runEventWriterT $
        listWithKey (fromMaybe mempty . coerce <$> verses) $ \vref vDyn ->
          el "p" $ do
            let yellow = "style" =: "background-color: yellow;"
            let blue = "style" =: "background-color: blue;"
            text $ showVerseReference vref
            dyn_ $ ffor vDyn $ \v -> ifor_ (T.words v) $ \i w ->
              elDynAttr "span" (ffor selections $ \sels -> if null (IntervalSet.containing sels (vref, i)) then mempty else yellow) $ do
                (elmnt, _) <- elDynAttr' "a" (ffor highlightState $ \firstWord -> if firstWord == Just (vref, i) then blue else mempty) $ text w
                text " "
                tellEvent $ First (vref, i) <$ domEvent Click elmnt

      let
        -- Given a new value @a@ and a previous 'Maybe', flip 'Just _' to 'Nothing' and 'Nothing' to @Just a@.
        toggleMaybes :: a -> Maybe a -> Maybe a
        toggleMaybes a = \case
          Nothing -> Just a
          Just _ -> Nothing

      -- Highlight state enters "highlighting" when you select your first word, then goes back when you select the second.
      -- Thus this state always stores the first word of a highlight or 'Nothing' if not highlighting.
      highlightState <- foldDyn toggleMaybes Nothing selectWord

      let
        captureRange :: Maybe (VerseReference, Int) -> (VerseReference, Int) -> Maybe (Interval (VerseReference, Int))
        captureRange firstWord lastWord = firstWord <&> \fstWord -> if lastWord >= fstWord
          then ClosedInterval fstWord lastWord
          else ClosedInterval lastWord fstWord

        highlightFinished :: Event t (Interval (VerseReference, Int)) = fmapMaybe id $ captureRange <$> current highlightState <@> selectWord

      selections <- foldDyn IntervalSet.insert mempty highlightFinished
      _ <- requestingIdentity $ ffor highlightFinished $ \(ClosedInterval start end) -> -- TODO: Partial match
        public $ PublicRequest_AddTag $ TagOccurrence "test" defaultTranslation start end
      pure ()

watchTranslations
  :: (HasApp t m, MonadHold t m, MonadFix m)
  => m (Dynamic t (Maybe (MonoidalMap TranslationId Translation)))
watchTranslations =
  (fmap . fmap) (fmap (fmap getFirst . snd) . getOption . _view_translations) $
    watchViewSelector $ pure $ mempty { _viewSelector_translations = Option $ Just 1 }

watchVerses
  :: (HasApp t m, MonadHold t m, MonadFix m)
  => Dynamic t (TranslationId, Interval VerseReference)
  -> m (Dynamic t (Maybe (MonoidalMap VerseReference Text)))
watchVerses rng = do
  result <- watchViewSelector $ ffor rng $ \(translationId, interval) -> mempty
    { _viewSelector_verseRanges = MMap.singleton translationId $ MMap.singleton interval 1 }
  pure $ ffor2 rng result $ \(translationId, _interval) result' -> -- TODO: Filter out verses that fit interval
    (fmap.fmap) (getFirst . snd) $ result' ^? view_verses . ix translationId
