
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}
-- should not need this: https://github.com/haskell/haskell-ide-engine/issues/842
{-# LANGUAGE QuasiQuotes #-}

module Rough2 where

import Rough as T
import Config
import DSL.Interpreter
import           Polysemy
import           Pyrelude
import           Runner as R

endpoint :: (forall m1 m a. TestPlan m1 m a FullIOMembers) -> Sem FullIOMembers ()
endpoint = ep runConfig (IID 120)

data Dummy = Dummy

test :: forall effs. T.Effects effs => Test Item ApState DState effs
test = T.test { R.config = T.config {address = mkTestModule ''Dummy} }