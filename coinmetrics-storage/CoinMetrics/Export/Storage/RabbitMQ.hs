{-# LANGUAGE OverloadedStrings, RecordWildCards #-}

module CoinMetrics.Export.Storage.RabbitMQ
  ( RabbitMQExportStorage()
  ) where

import qualified Data.Aeson as J
import qualified Network.AMQP as AMQP
import qualified Data.Text as T
import Control.Monad
import Control.Exception
import Data.Maybe

import CoinMetrics.Export.Storage
import CoinMetrics.BlockChain

newtype RabbitMQExportStorage a = RabbitMQExportStorage (ExportStorageOptions a)


instance ExportStorage RabbitMQExportStorage where
  initExportStorage = return . RabbitMQExportStorage
  writeExportStorageSomeBlocks (RabbitMQExportStorage ExportStorageOptions{..}) ExportStorageParams
    { esp_destination = destination
    , esp_wrapOperation = wrapOperation
    } blocks = do
    when (length queueExchange < 2) cantGetNames
    let queueName = queueExchange !! 0
        exchangeName = queueExchange !! 1
    mapM_ (handleBlock queueName exchangeName) blocks
    where
      handleBlock queueName exchangeName someBlocks = wrapOperation $ do
        let encoded = (\(SomeBlocks b) -> J.encode b) <$> someBlocks
            connect = connectToBroker connOpts
            mkMessage block = AMQP.newMsg { AMQP.msgBody = block,  AMQP.msgDeliveryMode = Just AMQP.Persistent}
            close conn chan = AMQP.closeChannel chan >> AMQP.closeConnection conn
            send _ chan = do
              let queue = AMQP.newQueue {AMQP.queueName = queueName}
                  exchange = AMQP.newExchange {AMQP.exchangeName = exchangeName, AMQP.exchangeType = "direct"}
              _ <- AMQP.declareQueue chan queue
              AMQP.bindQueue chan queueName exchangeName "export-block"
              AMQP.declareExchange chan exchange
              mapM_ (AMQP.publishMsg chan exchangeName "export-block" . mkMessage) encoded
        bracket connect (uncurry close) (uncurry send)
      cantGetNames = error "Can't get queue and exchange name"
      connOpts =  parseConnectionOpts $ T.pack destination
      queueExchange = maybe cantGetNames (T.splitOn ":") (listToMaybe eso_tables)

-- format is: amqp://user:pass@host:10000/vhost
parseConnectionOpts :: T.Text -> AMQP.ConnectionOpts
parseConnectionOpts connStr = AMQP.fromURI (T.unpack connStr)


connectToBroker :: AMQP.ConnectionOpts -> IO (AMQP.Connection, AMQP.Channel)
connectToBroker opts = do
  let openChannel conn = AMQP.openChannel conn >>= (\chan -> pure (conn, chan))
  bracketOnError (AMQP.openConnection'' opts) AMQP.closeConnection openChannel
