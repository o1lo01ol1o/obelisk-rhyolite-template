{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFoldable #-}
{-# HLINT ignore "Use newtype instead of data" #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Common.App where

import Common.Schema
import Control.Lens (_1)
import Control.Lens.TH (makeLenses)
import Data.Aeson (parseJSON, toJSON)
import qualified Data.Aeson as Json
import Data.Aeson.GADT.TH (deriveJSONGADT)
import Data.Aeson.TH (deriveJSON)
import Data.Align (Align (nil), Semialign (alignWith))
import Data.Coerce (coerce)
import Data.Constraint.Extras.TH (deriveArgDict)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Map.Monoidal (MonoidalMap)
import qualified Data.Map.Monoidal as MMap
import Data.Semigroup (First (..), Option (..))
import Data.Set (Set)
import Data.Text (Text)
import Data.Witherable (Filterable (mapMaybe), Witherable (wither))
import GHC.Generics
import Reflex.Patch (Group (negateG))
import Reflex.Query.Class (Query (QueryResult, crop), SelectedCount (..))
import Rhyolite.App (PositivePart (positivePart), standardPositivePart)

data PublicRequest a where
  PublicRequest_AddTask :: Text -> PublicRequest ()

deriving instance Show a => Show (PublicRequest a)

fmap concat $
  sequence
    [ deriveJSONGADT ''PublicRequest,
      deriveArgDict ''PublicRequest
    ]

data PrivateRequest a where
  PrivateRequest_NoOp :: PrivateRequest ()

fmap concat $
  sequence
    [ deriveJSONGADT ''PrivateRequest,
      deriveArgDict ''PrivateRequest
    ]

deriving instance Show a => Show (PrivateRequest a)

------------------

nullToNothing :: Foldable f => f a -> Maybe (f a)
nullToNothing a = if null a then Nothing else Just a

mapMaybe2Deep :: (Foldable t, Filterable f, Filterable t) => (a -> Maybe b) -> f (t a) -> f (t b)
mapMaybe2Deep f = mapMaybe (nullToNothing . mapMaybe f)

data ViewSelector a = ViewSelector
  { _viewSelector_tasks :: Option a
  }
  deriving (Eq, Functor, Generic, Show)

deriveJSON Json.defaultOptions 'ViewSelector

makeLenses 'ViewSelector

instance Semigroup a => Semigroup (ViewSelector a) where
  a <> b =
    ViewSelector
      { _viewSelector_tasks = _viewSelector_tasks a <> _viewSelector_tasks b
      }

instance Semigroup a => Monoid (ViewSelector a) where
  mempty = ViewSelector mempty
  mappend = (<>)

instance Semialign ViewSelector where
  alignWith f a b =
    ViewSelector
      { _viewSelector_tasks = alignWith f (_viewSelector_tasks a) (_viewSelector_tasks b)
      }

instance Align ViewSelector where
  nil = ViewSelector nil

instance (Group a) => Group (ViewSelector a) where
  negateG = fmap negateG

instance Filterable ViewSelector where
  mapMaybe f x =
    ViewSelector
      { _viewSelector_tasks = mapMaybe f (_viewSelector_tasks x)
      }

instance (Monoid a, Eq a) => Query (ViewSelector a) where
  type QueryResult (ViewSelector a) = View a
  crop vs v =
    View
      { _view_tasks = if null (_viewSelector_tasks vs) then mempty else _view_tasks v
      }

data View a = View
  { _view_tasks :: !(Option (a, MonoidalMap TaskId (First Task)))
  }
  deriving (Eq, Foldable, Functor, Generic, Show)

deriveJSON Json.defaultOptions 'View

makeLenses 'View

instance Monoid a => Semigroup (View a) where
  a <> b =
    View
      { _view_tasks = _view_tasks a <> _view_tasks b
      }

instance Monoid a => Monoid (View a) where
  mempty = View mempty
  mappend = (<>)

instance Filterable View where
  mapMaybe f x =
    View
      { _view_tasks = mapMaybeView f (_view_tasks x)
      }

mapMaybeView ::
  forall f v a b.
  (Filterable f) =>
  (a -> Maybe b) ->
  f (a, v) ->
  f (b, v)
mapMaybeView f = mapMaybe ((_1 :: (a -> Maybe b) -> (a, v) -> Maybe (b, v)) f)

restrictKeys :: forall k v. Ord k => MonoidalMap k v -> Set k -> MonoidalMap k v
restrictKeys = coerce (Map.restrictKeys :: Map k v -> Set k -> Map k v)
