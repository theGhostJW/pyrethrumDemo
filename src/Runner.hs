

{-# LANGUAGE NoPolyKinds #-} 
-- TODO: work out why this is needed - investigate polykinds

module Runner (
    module Runner
  , module RB
  , module ItemFilter
  , module C
) where

import qualified Check as CK
import Common
import DSL.Interpreter
import DSL.Logger
import DSL.LogProtocol as LP
import DSL.Ensure
import Pyrelude as P
import Pyrelude.IO
import Polysemy
import qualified Data.DList as D
import           ItemFilter  (ItemFilter (..), filterredItemIds)
import qualified Data.Set as S
import RunElementClasses as C
import Text.Show.Pretty
import AuxFiles
import OrphanedInstances()
import Data.Aeson
import TestFilter
import RunnerBase as RB
import qualified System.IO as SIO
import qualified Data.Map as M
import qualified Data.Foldable as F
import qualified Prelude

type TestPlanBase tc rc m1 m a effs = (forall i as ds. (ItemClass i ds, Show i, Show as, Show ds, ToJSON as, ToJSON ds) => GenericTest tc rc i effs as ds -> m1 (m a)) -> [TestGroup m1 m a effs]

--- Reapplying test Filters to Items ---

applyTestFilters :: forall i tc rc. TestConfigClass tc => [TestFilter rc tc] -> rc -> (i -> tc) -> [i] -> [i]
applyTestFilters fltrs rc cvtr itms = 
    fst <$> filter (isNothing . snd) (applyTestFiltersToItemsShowReason fltrs rc cvtr itms) 

-- debugging
applyTestFiltersToItemsShowReason :: forall i tc rc. TestConfigClass tc => [TestFilter rc tc] -> rc -> (i -> tc) -> [i] -> [(i, Maybe Text)]
applyTestFiltersToItemsShowReason fltrs rc cvtr itms = 
  let 
    fltrItm :: i -> (i, Maybe Text)
    fltrItm i = (i, reasonForRejection . filterTestCfg fltrs rc $ cvtr i)
  in 
    fltrItm <$> itms

---

showAndLogItems :: Show a => [a] -> IO ()
showAndLogItems = showAndLogList "items"

showAndLogList :: Show a => Text -> [a] -> IO ()
showAndLogList logSuffix items = 
      let 
        logSpec :: M.Map (Text, FileExt) ()
        logSpec = M.singleton (logSuffix, FileExt ".log") ()

        hndle :: IO (Either AppError HandleInfo)
        hndle = either
                  Left
                  (
                    maybe
                      (Left $ AppUserError "showAndLogList - no Handle returned")
                      (Right . snd)
                    . head
                  ) 
                <$> logFileHandles logSpec

        log2Both :: SIO.Handle -> Text -> IO ()
        log2Both fileHndl lgStr = putLines SIO.stdout lgStr *> putLines fileHndl lgStr

        listItems :: SIO.Handle -> IO ()
        listItems h = sequence_ $ log2Both h . txtPretty <$> items
      in
        hndle >>=
                either pPrint (\HandleInfo{..} -> 
                                  listItems fileHandle `finally` SIO.hClose fileHandle
                                  *> putStrLn ""
                                  *> putStrLn "--- Log Files ---"
                                  *> putStrLn (toS . toFilePath $ path)
                                  *> putStrLn ""
                              )


data Step a = Step {
                  filePrefix :: Maybe Text,
                  result :: Either AppError [(a, HandleInfo)]
                }

logFileHandles :: forall a. M.Map (Text, FileExt) a -> IO (Either AppError [(a, HandleInfo)])
logFileHandles mpSuffixExt = 
  let
    seed :: IO (Step a)
    seed = pure $ Step {
      filePrefix = Nothing,
      result = Right []
    }

    step :: IO (Step a) -> (Text, FileExt) -> a -> IO (Step a)
    step accum (suff, ext) a = 
      do 
        iStep <- accum
        let 
          iResult = result iStep
          iPrefix = filePrefix iStep 
          
        eitherf iResult 
          (const $ pure iStep)
          (
            \hInfoLst -> 
              do 
                eHandInfo <- logFileHandle iPrefix suff ext
                pure $ eitherf eHandInfo
                        (\ioErr -> (iStep :: Step a) {result = Left $ AppIOError' "Error creating log file" ioErr} )
                        (
                          \hi@HandleInfo{..} -> Step {
                                                    filePrefix = Just prefix,
                                                    result = Right $ hInfoLst <> [(a, hi)]
                                                  }
                        )
          )

    finalRslt :: IO (Step a)
    finalRslt = M.foldlWithKey' step seed mpSuffixExt
  in 
     result <$> finalRslt 

doNothing :: PreRun effs
doNothing = PreRun {
  runAction = pure (),
  checkHasRun = pure True
}

disablePreRun :: TestGroup m m1 a effs -> TestGroup m m1 a effs
disablePreRun tg = tg {
                        rollover = doNothing,
                        goHome = doNothing
                      }

testAddress :: forall tc rc i effs as ds. TestConfigClass tc => GenericTest tc rc i effs as ds -> TestModule
testAddress =  moduleAddress . (configuration :: GenericTest tc rc i effs as ds -> tc)


-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Run Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

normalExecution :: forall m effs rc tc i as ds. (Monad m, MonadCatch m, MonadMask m, ItemClass i ds, ToJSON as, ToJSON ds, TestConfigClass tc) =>
     (LogProtocol -> m ())                                 -- logger
     -> (rc -> i -> Sem effs as)                           -- Interactor          
     -> (i -> as -> Ensurable ds)                          -- prepstate
     -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
     -> tc                                                 -- TestConfig
     -> rc                                                 -- RunConfig
     -> i                                                  -- item
     -> m ()                                               -- result
normalExecution logger interactor prepState intrprt tc rc i  = 
    let
      iid :: ItemId
      iid = ItemId (moduleAddress tc) (identifier i)

      logRunItem :: RunProtocol -> m ()
      logRunItem = logger . logRun

      logChk :: CK.CheckReport -> m ()
      logChk cr = logRunItem $ CheckOutcome iid cr

      handler :: SomeException -> m ()
      handler e = logger . logRun . LP.Error . AppGenericError' ("Unexpected Error Executing iteration: " <> txt iid) . toS $ displayException e

      recordSkippedChecks :: m ()
      recordSkippedChecks = do 
                              logRunItem StartChecks 
                              F.traverse_ logChk $ D.toList $ CK.skipChecks (checkList i)

      normalExecution' :: m ()
      normalExecution' = 
        let
          runChecks :: ds -> m ()
          runChecks ds = F.traverse_ logChk $ D.toList $ CK.calcChecks ds (checkList i)
        in 
          do 
            logRunItem StartInteraction
            ethas <- onError 
                        (intrprt $ interactor rc i) 
                        (logger . logRun . LP.Error $ AppGenericError "Interactor Exception")

            eitherf ethas
              (\e -> logRunItem (InteractorFailure iid e) *> recordSkippedChecks)
              (\as -> 
                  do 
                    logRunItem . InteractorSuccess iid . ApStateJSON . toJSON $ as
                    
                    let 
                      eds :: Either EnsureError ds
                      eds = fullEnsureInterpreter $ prepState i as
                    
                    logRunItem StartPrepState
                    eitherf eds
                      (\e -> (logRunItem . PrepStateFailure iid $ AppEnsureError e) *> recordSkippedChecks)
                      (
                        \ds -> 
                          do
                            logRunItem . PrepStateSuccess iid . DStateJSON . toJSON $ ds
                            logRunItem StartChecks
                            runChecks ds
                      )
              )
  in 
    catch
        normalExecution'
        handler

docExecution :: forall m effs rc tc i as ds. (Monad m, ItemClass i ds, TestConfigClass tc) =>
     (LogProtocol -> m ())                                 -- logger
     -> (rc -> i -> Sem effs as)                           -- Interactor          
     -> (i -> as -> Ensurable ds)                          -- prepstate
     -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
     -> tc                                                 -- TestConfig
     -> rc                                                 -- RunConfig
     -> i                                                  -- item
     -> m ()                                               -- result
docExecution logger interactor _ intrprt tc rc i = 
  let
    iid :: ItemId
    iid = ItemId (moduleAddress tc) $ identifier i

    docLog = logger . logDoc

    logChecks :: m ()
    logChecks =  P.sequence_ $  (\chk -> docLog $ DocCheck iid (CK.header (chk :: CK.Check ds)) (CK.expectation chk) (CK.gateStatus chk)) <$> D.toList (checkList i)
  in 
    do 
      docLog DocInteraction
      intrprt (interactor rc i)
      docLog DocChecks
      logChecks


runTestItems :: forall i as ds tc rc effs m. (Show as, Show ds, Monad m, TestConfigClass tc, ItemClass i ds, Member Logger effs) =>
      tc
      -> Maybe (S.Set Int)                                                    -- target Ids
      -> [i]                                                                  -- items
      -> (rc -> i -> Sem effs as)                                             -- interactor
      -> (i -> as -> Ensurable ds)                                            -- prepstate
      -> rc                                                                   -- runconfig
      -> (forall a. Sem effs a -> m (Either AppError a))                      -- interpreter
      -> ((Show as, Show ds) =>                               -- item runner logger - this does all the work and logs results as side effect
          (LogProtocol -> m ())                                 -- logger
          -> (rc -> i -> Sem effs as)                           -- interactor    
          -> (i -> as -> Ensurable ds)                          -- prepstate
          -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
          -> tc                                                 -- TestConfig
          -> rc                                                 -- RunConfig
          -> i                                                  -- item
          -> m ()                                               -- result
      )
      -> [m ()]
runTestItems tc iIds items interactor prepState rc intrprt runnerLogger =
  let
    logPrtcl :: LogProtocol -> m ()
    logPrtcl = logger' intrprt
    
    logBoundry :: BoundaryEvent -> m ()
    logBoundry = logPrtcl . BoundaryLog

    startTest :: m ()
    startTest = logBoundry . StartTest $ mkDisplayInfo tc

    endTest :: m ()
    endTest = logBoundry . EndTest $ moduleAddress tc

    filteredItems :: [i]
    filteredItems = filter inTargIds items

    runItem :: i -> m ()
    runItem i =  let
                    iid :: ItemId
                    iid = ItemId (moduleAddress tc) (identifier i)
                  in
                    do
                      logBoundry . StartIteration iid (WhenClause $ whenClause i) (ThenClause $ thenClause i) $ toJSON i
                      runnerLogger logPrtcl interactor prepState intrprt tc rc i
                      logBoundry $ EndIteration iid

    inTargIds :: i -> Bool
    inTargIds i = maybe True (S.member (identifier i)) iIds

  in
    case filteredItems of
      [] -> []
      [x] -> [startTest *> runItem x *> endTest]
      x : xs -> (startTest *> runItem x)
                : (runItem <$> Prelude.init xs)
                <> [runItem (Prelude.last xs) *> endTest]

runTest ::  forall i rc as ds m tc effs. (Monad m, ItemClass i ds, Show as, Show ds, TestConfigClass tc, Member Logger effs) =>
                   Maybe (S.Set Int)                                                        -- target Ids
                   -> FilterList rc tc                                                      -- filters
                   -> (                               -- item runner logger - this does all the work and logs results as side effect
                      (LogProtocol -> m ())                                 -- logger
                      -> (rc -> i -> Sem effs as)                           -- interactor           
                      -> (i -> as -> Ensurable ds)                               -- prepstate
                      -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
                      -> tc                                                 -- TestConfig
                      -> rc                                                 -- RunConfig
                      -> i                                                  -- item
                      -> m ()                                               -- result
                   )
                   -> rc                                                                    -- runConfig
                   -> (forall a. Sem effs a -> m (Either AppError a))                       -- interpreter
                   -> GenericTest tc rc i effs as ds                                        -- Test Case
                   -> [m ()]                                                                -- [TestIterations]
runTest iIds fltrs runnerLogger rc intrprt GenericTest{..} =
        let
          runItems :: TestComponents rc i effs as ds -> [m ()]
          runItems TestComponents{..} = runTestItems configuration iIds (testItems rc) testInteractor testPrepState rc intrprt runnerLogger 

          include :: Bool
          include = acceptFilter $ filterTestCfg fltrs rc configuration
        in
          include
              ? runItems components
              $ []

logger' :: forall m effs. (Member Logger effs, Functor m) =>
                 (forall a. Sem effs a -> m (Either AppError a)) -- interpreter
                 -> LogProtocol
                 -> m ()
logger' intrprt = void . intrprt . logItem

testRunOrEndpoint :: forall rc tc m effs. (Monad m, RunConfigClass rc, TestConfigClass tc, EFFLogger effs) =>
                    Maybe (S.Set Int)                                    -- a set of item Ids used for test case endpoints
                   -> (forall a mo mi. TestPlanBase tc rc mo mi a effs)  -- test case processor function is applied to a hard coded list of test groups and returns a list of results
                   -> FilterList rc tc                                  -- filters
                   -> (forall as ds i. (ItemClass i ds, Show as, Show ds, ToJSON as, ToJSON ds) =>                                -- item runner logger - this does all the work and logs results as side effect
                        (LogProtocol -> m ())                                 -- logger
                        -> (rc -> i -> Sem effs as)                           -- interactor   
                        -> (i -> as -> Ensurable ds)                               -- prepstate
                        -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
                        -> tc                                                 -- TestConfig
                        -> rc                                                 -- RunConfig
                        -> i                                                  -- item
                        -> m ()                                               -- result
                    )
                   -> (forall a. Sem effs a -> m (Either AppError a)) -- interpreter
                   -> rc                                              -- runConfig
                   -> m ()
testRunOrEndpoint iIds runner fltrs runnerLogger intrprt rc =
        let
          preRun :: PreRun effs -> PreTestStage ->  m (Either AppError ())
          preRun PreRun{..} stage = 
            do
              let
                stageStr :: Text
                stageStr = txt stage

                stageExLabel :: Text
                stageExLabel = "Execution of " <> stageStr

                msgPrefix :: Text
                msgPrefix = case stage of
                              Rollover -> "No tests run in group. "
                              GoHome -> "No items run for test. "

                verifyAction :: Either AppError Bool -> Either AppError ()
                verifyAction  = either
                                          (Left . AppPreTestCheckExecutionError stage (msgPrefix <> stageExLabel <> " check"))
                                          (\hmChk -> hmChk ?
                                                        Right () $
                                                        Left
                                                            $ AppPreTestCheckError stage
                                                              $ msgPrefix
                                                              <> stageStr
                                                              <> " action ran without exception but completion check returned False. Looks like "
                                                              <> stageStr
                                                              <> " did not run as expected"
                                          )

              preRunRslt <- intrprt runAction
              runCheck <- intrprt checkHasRun
              pure $ either
                        (Left . AppPreTestError stage stageExLabel)
                        (\_ -> verifyAction runCheck)
                        preRunRslt

          -- filterInfo :: [[FilterResult]]
          filterInfo = filterGroups runner fltrs rc

          filterFlags :: [Bool]
          filterFlags = filterGroupFlags filterInfo

          -- prepResults :: [TestGroup [] m () effs]
          prepResults = runner $ runTest iIds fltrs runnerLogger rc intrprt

          firstDuplicateGroupTitle :: Maybe Text
          firstDuplicateGroupTitle = toS <$> firstDuplicate (toS . C.title <$> prepResults :: [Prelude.String])

          runTuples ::  [(Bool, TestGroup [] m () effs)]
          runTuples = P.zip filterFlags prepResults
          
          logPtcl :: LogProtocol -> m ()
          logPtcl = logger' intrprt
          
          logBoundry :: BoundaryEvent -> m ()
          logBoundry = logPtcl . BoundaryLog

          logLPError :: AppError -> m ()
          logLPError = logPtcl . logRun . LP.Error

          exeGroup :: (Bool, TestGroup [] m () effs) -> m ()
          exeGroup (include, tg) =
            let
              -- when running an endpoint go home and rolllover are not run
              -- if the application is already home
              isEndpoint :: Bool
              isEndpoint = isJust iIds

              preRunGuard ::  m (Either AppError Bool)
              preRunGuard = (
                              isEndpoint ?
                                  intrprt (not <$> checkHasRun (goHome tg)) $ -- we only want to run if is NOT already home
                                  pure $ Right True
                            )

              guardedPreRun :: (TestGroup [] m () effs -> PreRun effs) -> PreTestStage -> m (Either AppError ())
              guardedPreRun sel stg =
                do
                  wantRun <- preRunGuard
                  either
                    (pure . Left)
                    (bool
                      (pure $ Right ()) $
                      preRun (sel tg) stg
                    )
                    wantRun

              grpRollover :: m (Either AppError ())
              grpRollover = guardedPreRun rollover Rollover

              grpGoHome :: m (Either AppError ())
              grpGoHome = guardedPreRun goHome GoHome

              logFailOrRun :: m (Either AppError ()) -> m () -> m ()
              logFailOrRun prerun mRun = do
                                          pr <- prerun
                                          either logLPError (const mRun) pr

              runTestIteration :: m () -> m ()
              runTestIteration = logFailOrRun grpGoHome

              runTest' :: [m ()] -> m ()
              runTest' testIterations = sequence_ (runTestIteration <$> testIterations)

              testList :: [[m ()]]
              testList = filter (not . null) $ tests tg

              runGroupAfterRollover :: m ()
              runGroupAfterRollover = sequence_ $ runTest' <$> testList

              runGrp :: m ()
              runGrp = 
                    let 
                      hdr = GroupTitle $ RB.header tg
                    in
                      do
                        logBoundry $ StartGroup hdr
                        logFailOrRun grpRollover runGroupAfterRollover
                        logBoundry $ EndGroup hdr
           in
              include ? runGrp $ pure ()
        in
          maybef firstDuplicateGroupTitle
          (
            do
              logBoundry . StartRun (RunTitle $ C.title rc) $ toJSON rc
              logBoundry . FilterLog $ filterLog filterInfo
              sequence_ $ exeGroup <$> runTuples
              logBoundry EndRun
          )
          (\dupeTxt -> logLPError . AppGenericError $ "Test Run Configuration Error. Duplicate Group Names: " <> dupeTxt)
          

testRun :: forall rc tc m effs. (Monad m, RunConfigClass rc, TestConfigClass tc, EFFLogger effs) =>
                   (forall a mo mi. TestPlanBase tc rc mo mi a effs)  -- test case processor function is applied to a hard coded list of test goups and returns a list of results                                                -- test case processor function is applied to a hard coded list of test goups and returns a list of results
                   -> FilterList rc tc                               -- filters
                   -> (forall as ds i. (ItemClass i ds, Show as, Show ds, ToJSON as, ToJSON ds) =>  -- item runner logger - this does all the work and logs results as side effect
                        (LogProtocol -> m ())                                 -- logger
                        -> (rc -> i -> Sem effs as)                           -- interactor          
                        -> (i -> as -> Ensurable ds)                               -- prepstate
                        -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
                        -> tc                                                 -- TestConfig
                        -> rc                                                 -- RunConfig
                        -> i                                                  -- item
                        -> m ()                                               -- result
                    )
                   -> (forall a. Sem effs a -> m (Either AppError a)) -- interpreter
                   -> rc                                              -- runConfig
                   -> m ()
testRun = testRunOrEndpoint Nothing

testEndpointBase :: forall rc tc m effs. (Monad m, RunConfigClass rc, TestConfigClass tc, EFFLogger effs) =>
                   FilterList rc tc                               -- filters
                   -> (forall as ds i. (ItemClass i ds, Show as, ToJSON as, ToJSON ds) => -- item runner logger - this does all the work and logs results as side effect
                        (LogProtocol -> m ())                                 -- logger
                        -> (rc -> i -> Sem effs as)                           -- interactor          
                        -> (i -> as -> Ensurable ds)                          -- prepstate
                        -> (forall a. Sem effs a -> m (Either AppError a))    -- interpreter
                        -> tc                                                 -- TestConfig
                        -> rc                                                 -- RunConfig
                        -> i                                                  -- item
                        -> m ()                                               -- result
                    )
                   -> (forall a. Sem effs a -> m (Either AppError a)) -- interpreter
                   -> TestModule                                      -- test address
                   -> rc                                              -- runConfig
                   -> Either FilterError (S.Set Int)                  -- a set of item Ids used for test case endpoints
                   -> (forall a mo mi. TestPlanBase tc rc mo mi a effs)  -- test case processor function is applied to a hard coded list of test goups and returns a list of results                                                -- test case processor function is applied to a hard coded list of test goups and returns a list of results
                   -> m ()
testEndpointBase fltrs runnerLogger intrprt tstAddress rc iIds runner =
  let
    logPtcl :: LogProtocol -> m ()
    logPtcl = logger' intrprt

    endpointFilter :: TestModule -> TestFilter rc tc
    endpointFilter targAddress = TestFilter {
      title = "test address does not match endpoint target: " <> toString targAddress,
      predicate = \_ tc -> moduleAddress tc == targAddress
    }

    allFilters :: [TestFilter rc tc]
    allFilters = endpointFilter tstAddress : fltrs
  in
    eitherf iIds
      (logPtcl . logRun . LP.Error . AppFilterError)
      (\idSet -> testRunOrEndpoint (Just idSet) runner allFilters runnerLogger intrprt rc)