
module DSL.CurrentTimeDocLogger where

import qualified Data.Aeson as A
import           Pyrelude as P
import           Pyrelude.IO as PIO
import Polysemy
import Control.Lens
import DSL.CurrentTime as CT
import DSL.Logger

currentTimeDocInterpreter :: forall a e effs. (Show e, A.ToJSON e, Members [Logger e, Embed IO] effs) => Sem (CurrentTime ': effs) a -> Sem effs a
currentTimeDocInterpreter = 
  interpret $ \ct ->
                  let 
                    showTup :: forall v. Show v => Text -> IO v -> IO (Text, v)
                    showTup lbl v = (\v' -> (lbl <> txt v', v')) <$> v
                  in
                    do
                      (lbl, v) <- embed $ case ct of
                              GetCurrentTime -> showTup "getCurrentTime: " PIO.getCurrentTime
                              GetCurrentTimeZone -> showTup "getCurrentTimeZone: " PIO.getCurrentTimeZone
                              GetTimeZone utcTime' -> showTup "getTimeZone: " $ PIO.getTimeZone utcTime'
                              UtcToLocalZonedTime utcTime' -> showTup "utcToLocalZonedTime: " $ PIO.utcToLocalZonedTime utcTime'
                      logDocAction lbl
                      pure v