module RunnerBase where

import DSL.Ensure
import Common (FilterError, EnsureError)
import Pyrelude
import Polysemy
import Polysemy.Error
import RunElementClasses

type Ensurable effs = Members '[Ensure, Error EnsureError] effs

data GenericResult tc rslt = TestResult {
  configuration :: tc,
  results :: Either FilterError [rslt]
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

data TestComponents rc i effs as ds = TestComponents {
  testItems :: rc -> [i],
  testInteractor :: rc -> i -> Sem effs as,
  testPrepState :: forall pEffs. Ensurable pEffs => i -> as -> Sem pEffs ds
}

data GenericTest tc rc i effs as ds = GenericTest {
  configuration :: tc,
  components :: ItemClass i ds => TestComponents rc i effs as ds
}