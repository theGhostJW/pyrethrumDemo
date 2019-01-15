
module DSL.Common where

import           Control.Monad.Freer.Writer
import           Foundation.Extended
import           Foundation.List.DList

data PreTestStage = Rollover |
                    GoHome
                    deriving (Show, Eq)

data DetailedInfo = Info {
            message :: String,
            info    :: String
          }
          deriving (Eq, Show)

newtype EnsureError = EnsureError String deriving (Show, Eq)

data FilterError = InvalidItemFilter String |
                   DuplicateItemId Int String deriving (Eq, Show)

data FilterRejection tc = FilterRejection {
                 reason :: String,
                 cfg    :: tc
                 } deriving (Eq, Show)


data FileSystemError =
    ReadFileError IOException |
    WriteFileError IOException
    deriving (Show, Eq)

data AppError =
            AppFileSystemError FileSystemError |
            AppEnsureError EnsureError |
            AppFilterError FilterError |

            AppNotImplementedError String |

            AppGenericError String |

            AppUserError String |
            AppUserError' DetailedInfo |

            AppPreTestError PreTestStage String AppError |
            AppPreTestCheckExecutionError PreTestStage String AppError|
            AppPreTestCheckError PreTestStage String |

            AppIOError IOException |
            AppIOError' String IOException

            deriving (Show, Eq)


type WriterDList = Writer (DList String)

dList :: Show s => s -> DList String
dList s = fromList [show s]
