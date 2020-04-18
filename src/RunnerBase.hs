module RunnerBase where

import DSL.Ensure
import Common (FilterErrorType, AppError)
import Pyrelude
import Polysemy
import Polysemy.Error
import RunElementClasses

type Ensurable e effs = Members '[Ensure, Error (AppError e)] effs

data GenericResult tc rslt = TestResult {
  configuration :: tc,
  results :: Either FilterErrorType [rslt]
} deriving Show

data PreRun effs = PreRun {
  runAction :: Sem effs (),
  checkHasRun :: Sem effs Bool
}

data TestGroup m1 m a effs =
  TestGroup {
        header :: Text,
        -- occurs once on client before group is run
        rollover :: PreRun effs,
        -- occurs once before test iteration is run
        goHome :: PreRun effs,
        -- a list of tests
        tests :: [m1 (m a)]
        -- eg [IO Either (AppError TestInfo)]
   }

instance Titled (TestGroup m1 m a effs) where
  title = header

data TestComponents e rc i as ds effs = TestComponents {
  testItems :: rc -> [i],
  testInteractor :: rc -> i -> Sem effs as,
  testPrepState :: forall psEffs. (Ensurable e) psEffs => i -> as -> Sem psEffs ds
}

data GenericTest e tc rc i as ds effs = GenericTest {
  configuration :: tc,
  components :: ItemClass i ds => TestComponents e  rc i as ds effs
}