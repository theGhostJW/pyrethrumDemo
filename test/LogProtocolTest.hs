module LogProtocolTest where

import           Pyrelude as P
import           Pyrelude.Test as T
import DSL.LogProtocol
import Data.Functor.Identity
import Data.Functor
import DemoProject.Config
import RunElementClasses
import Data.Set as S
import Common
import TestFilter
import RunnerBase
import Data.Aeson hiding (Error)
import Data.ByteString.Lazy as B
import Hedgehog.Internal.Property
import Control.Monad.IO.Class
import Data.Traversable
import Data.Char
import Data.Aeson.TH
import qualified Check as C

genStr :: Gen Text
genStr = text (linear 0 1000) ascii

genTestModule :: Gen TestModule
genTestModule = TestModule <$> genStr

genTestConfig :: Gen TestConfig
genTestConfig =
  let
    set' :: (Enum a, Ord a) => Gen (Set a)
    set' = (S.fromList <$>) <$> subsequence $ enumList 
  in
    TestConfig 
      <$> genStr 
      <*> genTestModule
      <*> set'
      <*> set'
      <*> element enumList
      <*> T.bool

genRunConfig :: Gen RunConfig
genRunConfig =
    RunConfig 
      <$> genStr 
      <*> element enumList
      <*> element enumList
      <*> element enumList

genDetailedInfo:: Gen DetailedInfo
genDetailedInfo = DetailedInfo <$> genStr <*> genStr

genTestDisplayInfo:: Gen TestDisplayInfo
genTestDisplayInfo = TestDisplayInfo 
                                <$> genTestModule
                                <*> genStr 
                                <*> (toJSON <$> genTestConfig)

genFilterResult:: Gen FilterResult
genFilterResult = FilterResult 
                            <$> genTestDisplayInfo
                            <*> T.maybe genStr

genFilterResults :: Gen [FilterResult]
genFilterResults =
         T.list (linear 0 20) genFilterResult

genInt :: Gen Int
genInt = integral $ T.linear 0 1000

genItemId :: Gen ItemId
genItemId  = ItemId <$> genTestModule <*> genInt

genError :: Gen AppError
genError = AppUserError <$> genStr

genDocActionInfo :: Gen DocActionInfo
genDocActionInfo = choice [
  ActionInfo <$> genStr,
  ActionInfoM <$> genStr <*> genStr
 ]

genResultExpectation :: Gen C.ResultExpectation
genResultExpectation = choice [
  pure C.ExpectPass, 
  C.ExpectFailure <$> pure C.Inactive <*> genStr,
  C.ExpectFailure <$> pure C.Active <*> genStr 
 ]

genGateStatus :: Gen C.GateStatus
genGateStatus = choice [
  pure C.StandardCheck,
  pure C.GateCheck
 ]

genLogProtocol :: Gen LogProtocol
genLogProtocol = choice [
                    BoundaryLog <$> (StartRun <$> (RunTitle <$> genStr) <*> (toJSON <$> genRunConfig)), 
                    BoundaryLog . StartGroup <$> (GroupTitle <$> genStr),
                    BoundaryLog . EndGroup <$> (GroupTitle <$> genStr),
                    BoundaryLog . StartTest <$> genTestDisplayInfo,
                    BoundaryLog . EndTest <$> genTestModule,
                    BoundaryLog <$> (StartIteration <$> genItemId <*> (WhenClause <$> genStr) <*> (ThenClause <$> genStr) <*> (toJSON <$> genRunConfig)), --- using runconfig as an easy proxy for item
                    BoundaryLog . EndIteration <$> genItemId,
                    BoundaryLog . FilterLog <$> genFilterResults,
                    pure $ BoundaryLog EndRun,

                    logDoc . DocAction <$> genDocActionInfo,
                    logDoc . DocIOAction <$> genStr,
                    logDoc <$> (DocCheck <$> genItemId <*> genStr <*>  genResultExpectation <*> genGateStatus),
                    logDoc . DocMessage <$> genStr,
                    logDoc . DocMessage' <$> genDetailedInfo,
                  
                    logDoc . DocWarning <$> genStr,
                    logDoc . DocWarning' <$> genDetailedInfo,
                    logDoc . DocError <$> genError,

                    logRun . IOAction <$> genStr,
                    logRun <$> (InteractorSuccess <$> genItemId <*> (ApStateDisplay <$> genStr)),
                    logRun <$> (InteractorFailure <$> genItemId <*> genError),

                    logRun <$> (PrepStateSuccess <$> genItemId <*> (DStateDisplay <$> genStr)),
                    logRun <$> (PrepStateFailure <$> genItemId <*> genError),

                    logRun . Message <$> genStr,
                    logRun . Message' <$> genDetailedInfo,
                  
                    logRun . Warning <$> genStr,
                    logRun . Warning' <$> genDetailedInfo,
                    logRun . Error <$> genError
                 ]




hprop_log_protocol_round_trip :: Property
hprop_log_protocol_round_trip = property $ do
  lp <- forAll genLogProtocol
  let 
    serialised :: B.ByteString
    serialised = encode lp

    unserialised :: Either Text LogProtocol
    unserialised = mapLeft txt $ eitherDecode serialised

  eitherf unserialised
    (\s -> footnote (toS s) *> failure)
    (lp ===)
