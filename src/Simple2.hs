
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}
-- https://github.com/haskell/haskell-ide-engine/issues/842
{-# LANGUAGE QuasiQuotes #-}

module Simple2 where
  
import Simple as S
import Config
import DSL.Interpreter
import           Polysemy
import           Pyrelude
import           Runner as R

endpoint :: (forall m1 m a. TestPlan m1 m a FullIOMembers) -> Sem FullIOMembers ()
endpoint = ep runConfig (IID 120)

data Dummy = Dummy

test :: forall effs. Effects effs => Test Item ApState DState effs
test = S.test { R.config = S.config {address = mkTestModule ''Dummy} }
