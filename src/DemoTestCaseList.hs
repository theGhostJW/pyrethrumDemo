module DemoTestCaseList where

import           Control.Monad.Freer
import           Control.Monad.Freer.Error
import           Control.Monad.Freer.Writer
import           DemoConfig
import           DemoRoughTest as RT
import           DemoRoughTestSimple
import           DSL.Ensure
import           DSL.FileSystem
import           DSL.Interpreter
import           DSL.Logger
import           Foundation.Extended
import qualified Prelude                    as P
import           Runner


-- -- interactor :: Effects effs => (ItemClass Item ValState) => RunConfig -> Item -> Eff effs ApState
-- testRun :: forall i vs as effs. (ItemClass i vs, Show i, Show as, Show vs, EFFFileSystem effs) => (Test i (Eff effs as) as vs -> IO ()) -> IO ()
-- testRun runner = let
--                    testResultList = [
--                      DemoRoughTest.execute runner,
--                      DemoRoughTestSimple.execute runner
--                     ]
--                   in
--                    undefined
-- --runIOList $ (testExecutor runner) <$> testResultList

runIOList :: [IO ()] -> IO ()
runIOList = foldl' (>>) (pure ())

type FullRunner = forall rc tc i as vs effs. (ItemClass i vs, Show i, Show as, Show vs, EFFFileSystem effs) => GenericTest rc tc i (Eff effs as) as vs -> IO ()
type FullTestRunner = forall i as vs effs. (ItemClass i vs, Show i, Show as, Show vs, EFFFileSystem effs) => Test i (Eff effs as) as vs -> IO ()

type SystemRunner = forall i as vs. (ItemClass i vs, Show i, Show as, Show vs) => Test i (Eff '[FileSystem, Logger, Ensure, Error FileSystemError, Error EnsureError, IO] as) as vs -> IO ()

blahh :: [IO ()]
blahh = [
  RT.execute runAllFull,
  DemoRoughTestSimple.execute runAllFull
  ]

-- blahh1 :: (forall i as vs effs. (ItemClass i vs, Show i, Show as, Show vs, EFFFileSystem effs) => Test i (Eff effs as) as vs -> IO ()) -> [IO ()]
-- blahh1 f = [
--   RT.execute f,
--   DemoRoughTestSimple.execute f
--   ]
--
--
-- -- fulllIORunner :: FullTestRunner
-- -- fulllIORunner = runAllFull
--
-- runFullList :: FullTestRunner -> IO ()
-- runFullList runner = runIOList [
--     runner RT.test
--   --  runner DemoRoughTestSimple.test
--   ]

--runFullListDemo = runFullList runAllFull

  -- runIOList [
  -- runner DemoRoughTest.test,
  -- runner DemoRoughTestSimple.test
  -- ]


-- test :: Effects effs => Test Item (Eff effs ApState) ApState ValState

testRun' :: IO ()
testRun' =
     runIOList [
        runAllFull RT.test,
        runAllFull DemoRoughTestSimple.test
      ]

testRunDoc :: IO ()
testRunDoc = runIOList [
  runAllDoc RT.test,
  runAllDoc DemoRoughTestSimple.test
  ]

-- A2 Hard Coded
a2TestRunDoc :: IO ()
a2TestRunDoc = runIOList [
  a2ExecuteFileSystemInIO RT.interactorEffs,
  a2ExecuteFileSystemInIO DemoRoughTestSimple.interactorEffs
  ]

a2TestPriv :: (Eff effs () -> IO ()) -> IO ()
a2TestPriv interpreter = runIOList $ interpreter <$> [
     RT.interactorEffs,
     DemoRoughTestSimple.interactorEffs
  ]

sampleUse1 = a2TestPriv a2ExecuteFileSystemInIO
sampleUse2 = a2TestPriv a2ExecuteFileSystemDocument




--a2RunAll =

-- runner :: (forall i as vs effs. (ItemClass i vs, Show i, Show as, Show vs, EFFFileSystem effs) => Test i (Eff effs as) as vs -> IO ()) -> IO ()
-- runner f = runIOList $ [
--   f RT.test,
--   f DemoRoughTestSimple.test
--   ]
--
-- demo :: IO ()
-- demo = runner runAllFull
