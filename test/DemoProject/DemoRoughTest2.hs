
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}
-- should not need this: https://github.com/haskell/haskell-ide-engine/issues/842
{-# LANGUAGE QuasiQuotes #-}

module DemoProject.DemoRoughTest2 where

import DemoProject.DemoRoughTest as T
import DemoProject.DemoConfig
import           Foundation.Extended  hiding (Item)
import           Runner as R

data Dummy = Dummy

test :: forall effs. Effects effs => Test Item effs ApState ValState
test = T.test { configuration = config {address = moduleOf ''Dummy} }