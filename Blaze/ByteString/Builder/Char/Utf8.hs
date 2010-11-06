{-# OPTIONS_GHC -fno-warn-unused-imports #-} 
-- ignore warning from 'import Data.Text.Encoding'

-- |
-- Module      : Blaze.ByteString.Builder.Char.Utf8
-- Copyright   : (c) 2010 Jasper Van der Jeugt & Simon Meier
-- License     : BSD3-style (see LICENSE)
-- 
-- Maintainer  : Simon Meier <iridcode@gmail.com>
-- Stability   : experimental
-- Portability : tested on GHC only
--
-- 'Write's and 'Builder's for serializing Unicode characters using the UTF-8
-- encoding. 
--
module Blaze.ByteString.Builder.Char.Utf8
    ( 
      -- * Writing UTF-8 encoded characters to a buffer
      writeChar

      -- * Creating Builders from UTF-8 encoded characters
    , fromChar
    , fromString
    , fromShow
    , fromText
    , fromLazyText
    ) where

import Foreign
import Data.Char (ord)

import qualified Data.Text               as TS
import qualified Data.Text.Encoding      as TS -- imported for documentation links
import qualified Data.Text.Lazy          as TL
import qualified Data.Text.Lazy.Encoding as TS -- imported for documentation links

import Blaze.ByteString.Builder.Internal
import Blaze.ByteString.Builder.Write

-- | Write a UTF-8 encoded Unicode character to a buffer.
--
-- Note that the control flow of 'writeChar' is more complicated than the one
-- of 'writeWord8', as the size of the write depends on the 'Char' written.
-- Therefore,
--
-- > fromWrite $ writeChar a `mappend` writeChar b
--
-- must not always be faster than
--
-- > fromChar a `mappend` fromChar b
--
-- Use benchmarking to make informed decisions.
--

-- FIXME: Use a Write that always checks if 4 bytes are available and only take
-- care of the precise pointer advance once the data has been written. Either
-- formulate it using continuation passing or returning the increment using the
-- IO action. The latter is probably simpler and better understandable.
--
writeChar :: Char -> Write
writeChar = encodeCharUtf8 f1 f2 f3 f4
  where
    f1 x = Write 1 $ \ptr -> poke ptr x

    f2 x1 x2 = Write 2 $ \ptr -> do poke ptr x1
                                    poke (ptr `plusPtr` 1) x2

    f3 x1 x2 x3 = Write 3 $ \ptr -> do poke ptr x1
                                       poke (ptr `plusPtr` 1) x2
                                       poke (ptr `plusPtr` 2) x3

    f4 x1 x2 x3 x4 = Write 4 $ \ptr -> do poke ptr x1
                                          poke (ptr `plusPtr` 1) x2
                                          poke (ptr `plusPtr` 2) x3
                                          poke (ptr `plusPtr` 3) x4
{-# INLINE writeChar #-}

-- | Encode a Unicode character to another datatype, using UTF-8. This function
-- acts as an abstract way of encoding characters, as it is unaware of what
-- needs to happen with the resulting bytes: you have to specify functions to
-- deal with those.
--
encodeCharUtf8 :: (Word8 -> a)                             -- ^ 1-byte UTF-8
               -> (Word8 -> Word8 -> a)                    -- ^ 2-byte UTF-8
               -> (Word8 -> Word8 -> Word8 -> a)           -- ^ 3-byte UTF-8
               -> (Word8 -> Word8 -> Word8 -> Word8 -> a)  -- ^ 4-byte UTF-8
               -> Char                                     -- ^ Input 'Char'
               -> a                                        -- ^ Result
encodeCharUtf8 f1 f2 f3 f4 c = case ord c of
    x | x <= 0x7F -> f1 $ fromIntegral x
      | x <= 0x07FF ->
           let x1 = fromIntegral $ (x `shiftR` 6) + 0xC0
               x2 = fromIntegral $ (x .&. 0x3F)   + 0x80
           in f2 x1 x2
      | x <= 0xFFFF ->
           let x1 = fromIntegral $ (x `shiftR` 12) + 0xE0
               x2 = fromIntegral $ ((x `shiftR` 6) .&. 0x3F) + 0x80
               x3 = fromIntegral $ (x .&. 0x3F) + 0x80
           in f3 x1 x2 x3
      | otherwise ->
           let x1 = fromIntegral $ (x `shiftR` 18) + 0xF0
               x2 = fromIntegral $ ((x `shiftR` 12) .&. 0x3F) + 0x80
               x3 = fromIntegral $ ((x `shiftR` 6) .&. 0x3F) + 0x80
               x4 = fromIntegral $ (x .&. 0x3F) + 0x80
           in f4 x1 x2 x3 x4
{-# INLINE encodeCharUtf8 #-}

-- | /O(1)/. Serialize a Unicode character using the UTF-8 encoding.
--
fromChar :: Char -> Builder
fromChar = fromWriteSingleton writeChar

-- | /O(n)/. Serialize a Unicode 'String' using the UTF-8 encoding.
--
fromString :: String -> Builder
fromString = fromWrite1List writeChar
-- Performance note: ^^^
--
--   fromWrite2List made things slightly worse for the blaze-html benchmarks
--   despite being better when serializing only a list.  Probably, the cache is
--   already occupied enough with dealing with the data from Html rendering.
--


-- | /O(n)/. Serialize a value by 'Show'ing it and UTF-8 encoding the resulting
-- 'String'.
--
fromShow :: Show a => a -> Builder
fromShow = fromString . show

-- | /O(n)/. Serialize a strict Unicode 'TS.Text' value using the UTF-8 encoding.
--
-- Note that this function is currently faster than 'TS.encodeUtf8' provided by
-- "Data.Text.Encoding". Moreover, 'fromText' is also lazy, while 'TL.encodeUtf8'
-- is strict.
--
fromText :: TS.Text -> Builder
fromText = fromString . TS.unpack
{-# INLINE fromText #-}


-- | /O(n)/. Serialize a lazy Unicode 'TL.Text' value using the UTF-8 encoding.
--
-- Note that this function is currently faster than 'TL.encodeUtf8' provided by
-- "Data.Text.Lazy.Encoding".
--
fromLazyText :: TL.Text -> Builder
fromLazyText = fromString . TL.unpack
{-# INLINE fromLazyText #-}