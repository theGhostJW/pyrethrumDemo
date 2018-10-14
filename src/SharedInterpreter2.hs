{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RankNTypes  #-}

module SharedInterpreter2 where

import           Control.Monad.Freer
import           Control.Monad.Freer.Error
import           DSL.Ensure
import           DSL.FileSystem
import           DSL.Logger
import           Foundation.Extended       hiding (writeFile)
import           ItemClass
import qualified Prelude                   as P

newtype RunConfig = RunConfig {dummyProp :: String}
newtype TestConfig = TestConfig {dummyPropT :: String}

data GenericTest testConfig runConfig item effs apState valState = GenericTest {
  address       :: String,
  configuration :: testConfig,
  components    :: TestComponents runConfig item effs apState valState
}

data TestComponents runConfig item apState effs valState = TestComponents {
  testItems      :: [item],
  testInteractor :: runConfig -> item -> effs,
  testPrepState  :: apState -> valState
}

type Test = GenericTest RunConfig TestConfig

test1 :: Test String Double String String
test1 = undefined

test2 :: Test Int Double Int Int
test2 = undefined

--runAllFull :: forall i as vs. Test i (Eff '[FileSystem, Logger, Ensure, Error FileSystemError, Error EnsureError, IO] as) as vs -> IO ()
runAllFull :: forall i as effs vs. Test i effs as vs -> IO ()
runAllFull = undefined

mergeIO :: [IO ()] -> IO ()
mergeIO = foldl' (>>) (pure ())

runTest :: IO ()
runTest =
   mergeIO [
      runAllFull test1,
      runAllFull test2
    ]

-- testRunner :: (forall i as vs effs. Members '[Logger, Ensure, FileSystem] effs => Test i (Eff effs as) as vs -> IO ()) -> IO ()
-- testRunner f =
--    mergeIO [
--       f test1,
--       f test2
--     ]
