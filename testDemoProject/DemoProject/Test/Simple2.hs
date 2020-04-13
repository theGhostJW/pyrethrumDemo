
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}
-- https://github.com/haskell/haskell-ide-engine/issues/842
{-# LANGUAGE QuasiQuotes #-}

module DemoProject.Test.Simple2 where
  
import DemoProject.Test.Simple as T
import DemoProject.Config
import DSL.Interpreter
import           Polysemy
import           Pyrelude
import           Runner as R

endpoint :: (forall m1 m a. TestPlan m1 m a FullIOEffects) -> Sem FullIOEffects ()
endpoint = ep runConfig (IID 120)

data Dummy = Dummy

test :: forall effs. Effects effs => Test Item ApState DState effs
test = T.test { configuration = config {address = mkTestModule ''Dummy} }