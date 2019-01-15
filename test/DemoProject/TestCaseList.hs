
module DemoProject.TestCaseList where

import           Control.Monad.Freer
import           DemoProject.Config
import           DemoProject.Test.Rough as RT
import           DemoProject.Test.Rough2 as RT2
import           DemoProject.Test.Simple as ST
import Control.Monad
import           DemoProject.Test.Simple2 as ST2
import  Data.Functor (($>))
import           DSL.Common
import           DSL.Interpreter
import           DSL.Logger
import           Foundation.List.DList
import           Foundation.Extended
import qualified Prelude                    as P
import           Runner as R
import Control.Exception as E


ioRun :: (forall m1 m a. TestPlan m1 m a FullIOEffects) -> IO ()
ioRun pln = testRun pln filters testInfoFull executeInIOConsolePretty runConfig

ioRunRaw :: (forall m1 m a. TestPlan m1 m a FullIOEffects) -> IO ()
ioRunRaw pln = testRun pln filters testInfoFull executeInIOConsoleRaw runConfig

ioRunToFile :: (forall m1 m a. TestPlan m1 m a FullIOEffects) -> IO ()
ioRunToFile pln = testRun pln filters testInfoFull executeInIOFilePretty runConfig

docRunRaw :: (forall m1 m a. TestPlan m1 m a FullDocEffects) -> DList String
docRunRaw pln = extractDocLog $ testRun pln filters testInfoFull executeDocumentRaw runConfig

docRun :: (forall m1 m a. TestPlan m1 m a FullDocEffects) -> DList String
docRun pln = extractDocLog $ testRun pln filters testInfoFull executeDocumentPretty runConfig

runInIO :: IO ()
runInIO = ioRun plan

runInIOLogToFile :: IO ()
runInIOLogToFile = ioRunToFile plan

runInIORaw :: IO ()
runInIORaw = ioRunRaw plan

runNZInIO :: IO ()
runNZInIO = testRun plan filters testInfoFull executeInIOConsoleRaw runConfig {country = NZ}

runDocument :: DList String
runDocument = docRun plan

runDocumentToConsole :: IO ()
runDocumentToConsole = sequence_ . toList $ putStrLn <$> runDocument

validPlan :: forall m m1 effs a. EFFAllEffects effs =>
  PreRun effs
  -> PreRun effs
  -> PreRun effs
  -> PreRun effs
  ->  TestPlan m1 m a effs
validPlan ro0 gh0 ro1 gh1 f =
  [

    TestGroup {
           header = "Group 1",
           rollover = ro0,
           goHome = gh0,
           tests = [
               f RT.test,
               f ST.test -- 6 iterations
             ]
      },

    TestGroup {
          header = "Group 2",
          rollover = ro1,
          goHome = gh1,
          tests = [
              f RT2.test,
              f ST2.test -- 6 iterations
            ]
     }

    ]

plan :: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
plan = validPlan doNothing doNothing doNothing doNothing

alwaysFailCheck :: PreRun effs
alwaysFailCheck = PreRun {
  runAction = pure (),
  checkHasRun = pure False
}

testRunFailHomeG2 :: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
testRunFailHomeG2 = validPlan doNothing doNothing doNothing alwaysFailCheck

runFailHomeG2IO :: IO ()
runFailHomeG2IO = ioRun testRunFailHomeG2

runFailHomeG2Document :: DList String
runFailHomeG2Document = docRun testRunFailHomeG2

testRunFailRolloverG1 :: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
testRunFailRolloverG1 = validPlan alwaysFailCheck doNothing doNothing doNothing

runFailRolloverG1Document :: DList String
runFailRolloverG1Document = docRun testRunFailRolloverG1

runFailRolloverG1IO :: IO ()
runFailRolloverG1IO = ioRun testRunFailRolloverG1

ioException :: Eff effs Bool
ioException = (E.throw $ P.userError "Pretend IO Error") :: Eff effs Bool

exceptionInCheck :: PreRun effs
exceptionInCheck = PreRun {
  runAction = pure (),
  checkHasRun = ioException
}

testRunFailExceptG2GoHomeCheck :: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
testRunFailExceptG2GoHomeCheck = validPlan doNothing doNothing doNothing exceptionInCheck

runExceptG2GoHomeCheckIO :: IO ()
runExceptG2GoHomeCheckIO = ioRun testRunFailExceptG2GoHomeCheck

exceptionInRollover :: PreRun effs
exceptionInRollover = PreRun {
  runAction = void ioException,
  checkHasRun = pure True
}

testRunExceptG1Rollover:: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
testRunExceptG1Rollover = validPlan exceptionInRollover doNothing doNothing doNothing

runExceptG1Rollover :: IO ()
runExceptG1Rollover = ioRun testRunExceptG1Rollover

justLogPreRun :: EFFLogger effs => PreTestStage -> PreRun effs
justLogPreRun stage = PreRun {
  runAction = log $ "Run Action: " <> show stage,
  checkHasRun = log ("Check Action Run: " <> show stage) $> True
}

testG1GoHomeLogging:: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
testG1GoHomeLogging = validPlan (justLogPreRun Rollover) (justLogPreRun GoHome) doNothing doNothing

justLogPreRunFailCheck :: EFFLogger effs => PreTestStage -> PreRun effs
justLogPreRunFailCheck stage = PreRun {
  runAction = log $ "Run Action: " <> show stage,
  checkHasRun = log ("Check Action Run: " <> show stage) $> False
}

testG1GoHomeLoggingFailCheck :: forall m m1 effs a. EFFAllEffects effs => TestPlan m1 m a effs
testG1GoHomeLoggingFailCheck = validPlan (justLogPreRun Rollover) (justLogPreRunFailCheck GoHome) doNothing doNothing