{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}

module Network.Nakadi.EventTypes.Test where

import           ClassyPrelude

import           Conduit
import           Control.Concurrent.Async     (link)
import           Control.Exception.Safe
import           Control.Monad.Trans.Resource
import           Data.Aeson
import           Data.Function                ((&))
import           Data.UUID                    (UUID)
import qualified Data.UUID                    as UUID
import           Network.Nakadi
import           System.Random
import           Test.Tasty
import           Test.Tasty.HUnit

testEventTypes :: Config -> TestTree
testEventTypes conf = testGroup "EventTypes"
  [ testCase "EventTypesGet" (testEventTypesGet conf)
  , testCase "EventTypesDeleteCreateAndGet" (testEventTypesDeleteCreateGet conf)
  , testCase "EventTypePartitionsGet" (testEventTypePartitionsGet conf)
  , testCase "EventTypeCursorDistances" (testEventTypeCursorDistances conf)
  , testCase "EventTypePublishData" (testEventTypePublishData conf)
  ]

testEventTypesGet :: Config -> Assertion
testEventTypesGet conf =
  void $ eventTypesGet conf

data Foo = Foo { fortune :: Text } deriving (Show, Eq, Generic)

deriving instance FromJSON Foo
deriving instance ToJSON Foo

myEventTypeName :: EventTypeName
myEventTypeName = "test.FOO"

myEventTypeSchema :: EventTypeSchema
myEventTypeSchema = EventTypeSchema
  { _version = Just "0.1"
  , _createdAt = Nothing
  , _schemaType = SchemaTypeJson
  , _schema = "{ \"properties\": {\"fortune\": {\"type\": \"string\"} }, \"required\": [\"fortune\"] }"
  }

myEventType :: EventType
myEventType = EventType
  { _name = myEventTypeName
  , _owningApplication = Just "test-suite"
  , _category = Just EventTypeCategoryData
  , _enrichmentStrategies = Just [EnrichmentStrategyMetadata]
  , _partitionStrategy = Just "hash"
  , _compatibilityMode = Just CompatibilityModeForward
  , _partitionKeyFields = Just ["fortune"]
  , _schema = myEventTypeSchema
  }

ignoreExnNotFound :: MonadThrow m => a -> NakadiException -> m a
ignoreExnNotFound a (EventTypeNotFound _) = return a
ignoreExnNotFound _ exn                   = throw exn

testEventTypesDeleteCreateGet :: Config -> Assertion
testEventTypesDeleteCreateGet conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  myEventTypes <- filterMyEvent <$> eventTypesGet conf
  length myEventTypes @=? 1
  eventTypeDelete conf myEventTypeName
  myEventTypes' <- filterMyEvent <$> eventTypesGet conf
  length myEventTypes' @=? 0

  where filterMyEvent = filter ((myEventTypeName ==) . (_name :: EventType -> EventTypeName))

testEventTypePartitionsGet :: Config -> Assertion
testEventTypePartitionsGet conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  void $ eventTypePartitions conf myEventTypeName

testEventTypeCursorDistances :: Config -> Assertion
testEventTypeCursorDistances conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  partitions <- eventTypePartitions conf myEventTypeName
  let cursors = map extractCursors partitions
  forM_ cursors $ \cursor -> do
    distance <- eventTypeCursorDistance conf myEventTypeName cursor cursor
    distance @=? 0

  where extractCursors Partition { ..} =
          Cursor { _partition = _partition
                 , _offset    = _newestAvailableOffset }

genRandomUUID :: IO UUID
genRandomUUID = randomIO

consumeParametersSingle :: ConsumeParameters
consumeParametersSingle = defaultConsumeParameters
                          & setBatchLimit 1
                          & setBatchFlushTimeout 1

testEventTypePublishData :: Config -> Assertion
testEventTypePublishData conf = do
  now <- getCurrentTime
  eid <- tshow <$> genRandomUUID
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  let event = DataChangeEvent { _payload = Foo "Hello!"
                              , _metadata = Metadata eid (Timestamp now) [] Nothing
                              , _dataType = "test.FOO"
                              , _dataOp = DataOpUpdate
                              }
  withAsync (delayedPublish [event]) $ \asyncHandle -> do
    link asyncHandle
    eventConsumed :: Maybe (EventStreamBatch Foo) <- runResourceT $ do
      source <- eventTypeSource conf (Just consumeParametersSingle) myEventTypeName Nothing
      runConduit $ source .| headC
    isJust eventConsumed @=? True

  where delayedPublish events = do
          threadDelay (10^6)
          eventTypePublish conf myEventTypeName Nothing events
