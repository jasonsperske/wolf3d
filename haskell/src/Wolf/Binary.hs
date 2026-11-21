module Wolf.Binary (check, slice, byte, word16, word32) where
import Control.Monad (unless)
import qualified Data.ByteString as B

check :: Bool -> String -> Either String ()
check condition message = unless condition (Left message)

slice :: B.ByteString -> Int -> Int -> Either String B.ByteString
slice bytes offset count = do
  check (offset>=0 && count>=0 && offset<=B.length bytes && count<=B.length bytes-offset)
    ("Truncated data or invalid range at byte "++show offset)
  pure (B.take count (B.drop offset bytes))

byte :: B.ByteString -> Int -> Either String Int
byte bytes i = do
  chunk <- slice bytes i 1
  pure (fromIntegral (B.index chunk 0))

word16 :: B.ByteString -> Int -> Either String Int
word16 bytes i = (+) <$> byte bytes i <*> ((256*) <$> byte bytes (i+1))

-- Use Integer while decoding file offsets, before converting to machine Int.
word32 :: B.ByteString -> Int -> Either String Integer
word32 bytes i = do
  lo <- word16 bytes i
  hi <- word16 bytes (i+2)
  pure (toInteger lo + 65536*toInteger hi)

