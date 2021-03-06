{-|
Module      : Network.Nakadi.Internal.Types.Problem
Description : Nakadi Client Problem Type (Internal)
Copyright   : (c) Moritz Clasmeier 2017, 2019
License     : BSD3
Maintainer  : mtesseract@silverratio.net
Stability   : experimental
Portability : POSIX

Implementation of the error object described in RFC7807.
-}

{-# LANGUAGE ApplicativeDo   #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData      #-}
{-# LANGUAGE TupleSections   #-}
{-# LANGUAGE LambdaCase      #-}

module Network.Nakadi.Internal.Types.Problem where

import           Data.Aeson
import           Data.Aeson.Types
import           Data.HashMap.Lazy              ( HashMap )
import           Data.Text                      ( Text )
import           Prelude
import           Network.HTTP.Types.Status     as HTTP
                                                ( Status )

import qualified Data.HashMap.Lazy             as HashMap
import           Data.Maybe
import qualified Text.URI                      as URI
import           Text.URI                       ( URI )
import           GHC.Generics

-- | Type for RFC7807 @Problem@ objects.
data Problem = Problem
  { problemType     :: Maybe URI         -- ^ (string) - A URI reference [RFC3986] that identifies the
                                         --  problem type.  This specification encourages that, when
                                         --  dereferenced, it provide human-readable documentation for the
                                         --  problem type (e.g., using HTML [W3C.REC-html5-20141028]).  When
                                         --  this member is not present, its value is assumed to be
                                         --  "about:blank".
  , problemTitle    :: Text              -- ^ (string) - A short, human-readable summary of the problem
                                         --  type.  It SHOULD NOT change from occurrence to occurrence of the
                                         --  problem, except for purposes of localization (e.g., using
                                         --  proactive content negotiation; see [RFC7231], Section 3.4).
  , problemStatus   :: Maybe HTTP.Status -- ^ "status" (number) - The HTTP status code ([RFC7231], Section 6)
                                         -- generated by the origin server for this occurrence of the problem.
  , problemDetail   :: Maybe Text        -- ^ (string) - A human-readable explanation specific to this
                                         -- occurrence of the problem.
  , problemInstance :: Maybe URI         -- ^ (string) - A URI reference that identifies the specific
                                         -- occurrence of the problem.  It may or may not yield further
                                         -- information if dereferenced.
  , problemCustom   :: HashMap Text Value
  } deriving (Show, Eq, Generic)

instance ToJSON Problem where
  toJSON Problem {..} =
    let hm = HashMap.fromList
          (("title", String problemTitle) : catMaybes
            [ ("type", ) . String . URI.render <$> problemType
            , ("status", ) . Number . fromIntegral . fromEnum <$> problemStatus
            , ("detail", ) . String <$> problemDetail
            , ("instance", ) . String . URI.render <$> problemInstance
            ]
          )
    in  Object (HashMap.union hm problemCustom)

instance FromJSON Problem where
  parseJSON val = withObject "Problem" parser val

   where
    parser obj = do
      let custom = HashMap.filterWithKey
            (\k _ -> k `notElem` ["type", "title", "status", "detail", "instance"])
            obj
      typeURI <- obj .:? "type" >>= \case
        Nothing      -> pure Nothing
        Just uriText -> Just <$> parseURI uriText
      title       <- obj .: "title"
      status      <- obj .:? "status"
      detail      <- obj .:? "detail"
      instanceURI <- obj .:? "instance" >>= \case
        Nothing      -> pure Nothing
        Just uriText -> Just <$> parseURI uriText
      pure Problem { problemType     = typeURI
                   , problemTitle    = title
                   , problemStatus   = toEnum <$> status
                   , problemDetail   = detail
                   , problemInstance = instanceURI
                   , problemCustom   = custom
                   }

    parseURI uriText = case URI.mkURI uriText of
      Right uri  -> pure uri
      Left  _exn -> typeMismatch "Failed to parse type URI" val
