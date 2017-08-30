module Nakadi.Types.Config where

import           Nakadi.Internal.Prelude

import           Network.HTTP.Client

import           Nakadi.Types.Logger

-- | Config

type StreamConnectCallback = Maybe LogFunc -> Response () -> IO ()

data Config = Config
  { _requestTemplate                :: Request
  , _requestModifier                :: Request -> IO Request
  , _manager                        :: Manager
  , _consumeParameters              :: ConsumeParameters
  , _deserializationFailureCallback :: Maybe (ByteString -> IO ())
  , _streamConnectCallback          :: Maybe StreamConnectCallback
  , _logFunc                        :: Maybe LogFunc
  }

-- | ConsumeParameters

data ConsumeParameters = ConsumeParameters
  { _maxUncommittedEvents :: Maybe Int32
  , _batchLimit           :: Maybe Int32
  , _streamLimit          :: Maybe Int32
  , _batchFlushTimeout    :: Maybe Int32
  , _streamTimeout        :: Maybe Int32
  , _streamKeepAliveLimit :: Maybe Int32
  , _flowId               :: Maybe Text
  } deriving (Show, Eq, Ord)
