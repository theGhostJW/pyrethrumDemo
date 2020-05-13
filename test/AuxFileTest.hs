module AuxFileTest where

import AuxFiles
import Pyrelude as P
import Pyrelude.Test as T
import Data.Aeson


success' :: Result a -> a 
success' = \case
            Success a -> a
            _ -> error "Failed"

unit_a_file_prefix_generated_at_a_later_date_will_be_smaller = 
  let 
    timeEarly = TimeOfDay {timeOfDayHour = 0, timeOfDayMinute = 0, timeOfDayNanoseconds = 0}
    timeLate = TimeOfDay {timeOfDayHour = 0, timeOfDayMinute = 0, timeOfDayNanoseconds = 1000000}
    date = debug' "Date" $ Date (Year 2000) january $ DayOfMonth 1
    pfxLate = debug' "Late" . logFilePrefix . datetimeToTime $ Datetime date timeLate
    pfxEarly = debug' "Early" . logFilePrefix . datetimeToTime $ Datetime date timeEarly
  in
   chk $ pfxLate < pfxEarly



   
