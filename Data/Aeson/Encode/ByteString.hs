{-# LANGUAGE BangPatterns, OverloadedStrings #-}

-- |
-- Module:      Data.Aeson.EncodeUtf8
-- Copyright:   (c) 2011 MailRank, Inc.
--              (c) 2013 Simon Meier <iridcode@gmail.com>
-- License:     Apache
-- Maintainer:  Bryan O'Sullivan <bos@serpentine.com>
-- Stability:   experimental
-- Portability: portable
--
-- Efficiently serialize a JSON value using the UTF-8 encoding.

module Data.Aeson.Encode.ByteString
    ( encode
    , encodeToBuilder
    , encodeToByteStringBuilder
    , null_
    , bool
    , array
    , emptyArray_
    , emptyObject_
    , object
    , text
    , unquoted
    , number
    , foldable
    , series
    , ascii2
    , ascii4
    , ascii5
    , ascii6
    , ascii7
    ) where

import Data.Aeson.Types.Class (ToJSON(..))
import Data.Aeson.Types.Internal (Value(..), Series(..))
import Data.ByteString.Builder as B
import Data.ByteString.Builder.Prim as BP
import Data.ByteString.Builder.Scientific (scientificBuilder)
import Data.Char (ord)
import Data.Foldable (Foldable, foldMap)
import Data.Monoid ((<>))
import Data.Scientific (Scientific, base10Exponent, coefficient)
import Data.Word (Word8)
import qualified Data.ByteString.Lazy as L
import qualified Data.HashMap.Strict as HMS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V

-- | Efficiently serialize a JSON value as a lazy 'L.ByteString'.
encode :: ToJSON a => a -> L.ByteString
encode = B.toLazyByteString . encodeToBuilder . toJSON

-- | Encode a JSON value to a ByteString 'B.Builder'. Use this function if you
-- must prepend or append further bytes to the encoded JSON value.
encodeToBuilder :: Value -> Builder
encodeToBuilder Null       = null_
encodeToBuilder (Bool b)   = bool b
encodeToBuilder (Number n) = number n
encodeToBuilder (String s) = text s
encodeToBuilder (Array v)  = array v
encodeToBuilder (Object m) = object m

-- | This function is an alias for 'encodeToBuilder'.
encodeToByteStringBuilder :: Value -> Builder
encodeToByteStringBuilder = encodeToBuilder
{-# DEPRECATED encodeToByteStringBuilder "Use encodeToBuilder instead." #-}

-- | Encode a JSON null.
null_ :: Builder
null_ = BP.primBounded (ascii4 ('n',('u',('l','l')))) ()

-- | Encode a JSON boolean.
bool :: Bool -> Builder
bool = BP.primBounded (BP.condB id (ascii4 ('t',('r',('u','e'))))
                                   (ascii5 ('f',('a',('l',('s','e'))))))

-- | Encode a JSON array.
array :: V.Vector Value -> Builder
array v
  | V.null v  = B.char8 '[' <> B.char8 ']'
  | otherwise = B.char8 '[' <>
                encodeToBuilder (V.unsafeHead v) <>
                V.foldr withComma (B.char8 ']') (V.unsafeTail v)
  where
    withComma a z = B.char8 ',' <> encodeToBuilder a <> z

-- Encode a JSON object.
object :: HMS.HashMap T.Text Value -> Builder
object m = case HMS.toList m of
    (x:xs) -> B.char8 '{' <> one x <> foldr withComma (B.char8 '}') xs
    _      -> B.char8 '{' <> B.char8 '}'
  where
    withComma a z = B.char8 ',' <> one a <> z
    one (k,v)     = text k <> B.char8 ':' <> encodeToBuilder v

-- | Encode a JSON string.
text :: T.Text -> Builder
text t = B.char8 '"' <> unquoted t <> B.char8 '"'

-- | Encode a JSON string, without enclosing quotes.
unquoted :: T.Text -> Builder
unquoted t = TE.encodeUtf8BuilderEscaped escapeAscii t
  where
    escapeAscii :: BP.BoundedPrim Word8
    escapeAscii =
        BP.condB (== c2w '\\'  ) (ascii2 ('\\','\\')) $
        BP.condB (== c2w '\"'  ) (ascii2 ('\\','"' )) $
        BP.condB (>= c2w '\x20') (BP.liftFixedToBounded BP.word8) $
        BP.condB (== c2w '\n'  ) (ascii2 ('\\','n' )) $
        BP.condB (== c2w '\r'  ) (ascii2 ('\\','r' )) $
        BP.condB (== c2w '\t'  ) (ascii2 ('\\','t' )) $
        (BP.liftFixedToBounded hexEscape) -- fallback for chars < 0x20

    c2w = fromIntegral . ord

    hexEscape :: BP.FixedPrim Word8
    hexEscape = (\c -> ('\\', ('u', fromIntegral c))) BP.>$<
        BP.char8 >*< BP.char8 >*< BP.word16HexFixed

-- | Encode a JSON number.
number :: Scientific -> Builder
number s
    | e < 0     = scientificBuilder s
    | otherwise = B.integerDec (coefficient s * 10 ^ e)
  where
    e = base10Exponent s

foldable :: (Foldable t, ToJSON a) => t a -> Builder
foldable = series '[' ']' . foldMap (Value . toEncoding)

series :: Char -> Char -> Series -> Builder
series begin end (Value v) = B.char7 begin <> v <> B.char7 end
series begin end Empty     = BP.primBounded (ascii2 (begin,end)) ()

emptyArray_ :: Builder
emptyArray_ = BP.primBounded (ascii2 ('[',']')) ()

emptyObject_ :: Builder
emptyObject_ = BP.primBounded (ascii2 ('{','}')) ()

ascii2 :: (Char, Char) -> BP.BoundedPrim a
ascii2 cs = BP.liftFixedToBounded $ (const cs) BP.>$< BP.char7 >*< BP.char7
{-# INLINE ascii2 #-}

ascii4 :: (Char, (Char, (Char, Char))) -> BP.BoundedPrim a
ascii4 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii4 #-}

ascii5 :: (Char, (Char, (Char, (Char, Char)))) -> BP.BoundedPrim a
ascii5 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii5 #-}

ascii6 :: (Char, (Char, (Char, (Char, (Char, Char))))) -> BP.BoundedPrim a
ascii6 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii6 #-}

ascii7 :: (Char, (Char, (Char, (Char, (Char, (Char, Char)))))) -> BP.BoundedPrim a
ascii7 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*<
    BP.char7 >*< BP.char7
{-# INLINE ascii7 #-}
