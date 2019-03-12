
{-# LANGUAGE PolyKinds #-}

module DSL.LogProtocol where

import           Common (DetailedInfo, AppError)
import           Check
import           Foundation.Extended
import           RunElementClasses
import GHC.Generics
import OrphanedInstances
import Data.Aeson
import Data.Either
import Data.Aeson.Types
import Data.Aeson.TH
import qualified Data.HashMap.Lazy as HML
import qualified Data.Text as T

newtype RunTitle = RunTitle {unRunTitle :: String} deriving (Eq, Show, IsString)
newtype GroupTitle = GroupTitle {unGroupTitle :: String} deriving (Eq, Show, IsString)
newtype TestTitle = TestTitle {unTestTitle :: String} deriving (Eq, Show, IsString)
newtype ApStateDisplay = ApStateDisplay {unApStateDisplay :: String} deriving (Eq, Show, IsString)
newtype DStateDisplay = DStateDisplay {unDStateDisplay :: String} deriving (Eq, Show, IsString)
newtype DTestConfig = DTestConfig {unDTestConfig :: String} deriving (Eq, Show, IsString)
newtype DRunConfig = DRunConfig {unDRunConfig :: String} deriving (Eq, Show, IsString)
newtype WhenClause = WhenClause {unWhenClause :: String} deriving (Eq, Show, IsString)
newtype ThenClause = ThenClause {unThenClause :: String} deriving (Eq, Show, IsString)
data ItemId = ItemId TestModule Int deriving (Eq, Show)
data DocActionInfo = 
    ActionInfo String |
    ActionInfoM String String 
    deriving (Eq, Show)

$(deriveJSON defaultOptions ''RunTitle)
$(deriveJSON defaultOptions ''GroupTitle)
$(deriveJSON defaultOptions ''TestTitle)
$(deriveJSON defaultOptions ''ApStateDisplay)
$(deriveJSON defaultOptions ''DStateDisplay)
$(deriveJSON defaultOptions ''ItemId)
$(deriveJSON defaultOptions ''DocActionInfo)
$(deriveJSON defaultOptions ''WhenClause)
$(deriveJSON defaultOptions ''ThenClause)

data LogProtocol =
  Message String |
  Message' DetailedInfo |

  Warning String |
  Warning' DetailedInfo |

  IOAction String |
  DocIOAction String |
  DocAction DocActionInfo |
  DocCheck ItemId String ResultExpectation GateStatus | 
  DocStartInteraction | 
  DocStartChecks | 

  InteractorSuccess ItemId ApStateDisplay |
  InteractorFailure ItemId AppError |

  PrepStateSuccess ItemId DStateDisplay |
  PrepStateFailure ItemId AppError |

  Error AppError |
  FilterLog [FilterResult] |

  StartRun RunTitle Value | 
  EndRun |

  StartGroup GroupTitle |
  EndGroup GroupTitle |

  StartTest TestDisplayInfo |
  EndTest TestModule |

  CheckOutcome ItemId CheckReport |

  StartIteration ItemId WhenClause ThenClause Value | 
  EndIteration ItemId 

  deriving (Eq, Show)

$(deriveJSON defaultOptions ''LogProtocol)