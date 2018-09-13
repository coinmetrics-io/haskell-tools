{-# LANGUAGE DeriveGeneric, OverloadedLists, OverloadedStrings, TemplateHaskell, TypeFamilies #-}

module CoinMetrics.Bitcoin
	( Bitcoin(..)
	, BitcoinBlock(..)
	, BitcoinTransaction(..)
	, BitcoinVin(..)
	, BitcoinVout(..)
	) where

import qualified Data.Aeson as J
import qualified Data.Avro as A
import qualified Data.ByteString as B
import Data.Int
import Data.Maybe
import Data.Proxy
import qualified Data.Text as T
import qualified Data.Vector as V
import GHC.Generics(Generic)

import CoinMetrics.BlockChain
import CoinMetrics.JsonRpc
import CoinMetrics.Schema.Flatten
import CoinMetrics.Unified
import CoinMetrics.Util
import Hanalytics.Schema
import Hanalytics.Schema.Avro
import Hanalytics.Schema.Postgres

newtype Bitcoin = Bitcoin JsonRpc

data BitcoinBlock = BitcoinBlock
	{ bb_hash :: !B.ByteString
	, bb_size :: {-# UNPACK #-} !Int64
	, bb_strippedsize :: {-# UNPACK #-} !Int64
	, bb_weight :: {-# UNPACK #-} !Int64
	, bb_height :: {-# UNPACK #-} !Int64
	, bb_version :: {-# UNPACK #-} !Int64
	, bb_tx :: !(V.Vector BitcoinTransaction)
	, bb_time :: {-# UNPACK #-} !Int64
	, bb_nonce :: {-# UNPACK #-} !Int64
	, bb_difficulty :: {-# UNPACK #-} !Double
	} deriving Generic

instance Schemable BitcoinBlock

instance J.FromJSON BitcoinBlock where
	parseJSON = J.withObject "bitcoin block" $ \fields -> BitcoinBlock
		<$> (decodeHexBytes =<< fields J..: "hash")
		<*> (fields J..: "size")
		<*> (fields J..: "strippedsize")
		<*> (fields J..: "weight")
		<*> (fields J..: "height")
		<*> (fields J..: "version")
		<*> (fields J..: "tx")
		<*> (fields J..: "time")
		<*> (fields J..: "nonce")
		<*> (fields J..: "difficulty")

instance A.HasAvroSchema BitcoinBlock where
	schema = genericAvroSchema
instance A.ToAvro BitcoinBlock where
	toAvro = genericToAvro
instance ToPostgresText BitcoinBlock

instance IsUnifiedBlock BitcoinBlock

data BitcoinTransaction = BitcoinTransaction
	{ bt_hash :: !B.ByteString
	, bt_size :: {-# UNPACK #-} !Int64
	, bt_vsize :: {-# UNPACK #-} !Int64
	, bt_version :: {-# UNPACK #-} !Int64
	, bt_locktime :: {-# UNPACK #-} !Int64
	, bt_vin :: !(V.Vector BitcoinVin)
	, bt_vout :: !(V.Vector BitcoinVout)
	} deriving Generic

instance Schemable BitcoinTransaction
instance SchemableField BitcoinTransaction

instance J.FromJSON BitcoinTransaction where
	parseJSON = J.withObject "bitcoin transaction" $ \fields -> BitcoinTransaction
		<$> (decodeHexBytes =<< fields J..: "hash")
		<*> (fields J..: "size")
		<*> (fields J..: "vsize")
		<*> (fields J..: "version")
		<*> (fields J..: "locktime")
		<*> (fields J..: "vin")
		<*> (fields J..: "vout")

instance A.HasAvroSchema BitcoinTransaction where
	schema = genericAvroSchema
instance A.ToAvro BitcoinTransaction where
	toAvro = genericToAvro
instance ToPostgresText BitcoinTransaction

data BitcoinVin = BitcoinVin
	{ bvi_txid :: !(Maybe B.ByteString)
	, bvi_vout :: !(Maybe Int64)
	, bvi_coinbase :: !(Maybe B.ByteString)
	} deriving Generic

instance Schemable BitcoinVin
instance SchemableField BitcoinVin

instance J.FromJSON BitcoinVin where
	parseJSON = J.withObject "bitcoin vin" $ \fields -> BitcoinVin
		<$> (traverse decodeHexBytes =<< fields J..:? "txid")
		<*> (fields J..:? "vout")
		<*> (traverse decodeHexBytes =<< fields J..:? "coinbase")

instance A.HasAvroSchema BitcoinVin where
	schema = genericAvroSchema
instance A.ToAvro BitcoinVin where
	toAvro = genericToAvro
instance ToPostgresText BitcoinVin

data BitcoinVout = BitcoinVout
	{ bvo_value :: {-# UNPACK #-} !Double
	, bvo_addresses :: !(V.Vector T.Text)
	} deriving Generic

instance Schemable BitcoinVout
instance SchemableField BitcoinVout

instance J.FromJSON BitcoinVout where
	parseJSON = J.withObject "bitcoin vout" $ \fields -> BitcoinVout
		<$> (fields J..: "value")
		<*> (fmap (fromMaybe V.empty) $ (J..:? "addresses") =<< fields J..: "scriptPubKey")

instance A.HasAvroSchema BitcoinVout where
	schema = genericAvroSchema
instance A.ToAvro BitcoinVout where
	toAvro = genericToAvro
instance ToPostgresText BitcoinVout

genFlattenedTypes "height" [| bb_height |] [("block", ''BitcoinBlock), ("transaction", ''BitcoinTransaction), ("vin", ''BitcoinVin), ("vout", ''BitcoinVout)]

instance BlockChain Bitcoin where
	type Block Bitcoin = BitcoinBlock

	getBlockChainInfo _ = BlockChainInfo
		{ bci_init = \BlockChainParams
			{ bcp_httpManager = httpManager
			, bcp_httpRequest = httpRequest
			} -> return $ Bitcoin $ newJsonRpc httpManager httpRequest Nothing
		, bci_defaultApiUrl = "http://127.0.0.1:8332/"
		, bci_defaultBeginBlock = 0
		, bci_defaultEndBlock = -1000 -- very conservative rewrite limit
		, bci_schemas = standardBlockChainSchemas
			(schemaOf (Proxy :: Proxy BitcoinBlock))
			[ schemaOf (Proxy :: Proxy BitcoinVin)
			, schemaOf (Proxy :: Proxy BitcoinVout)
			, schemaOf (Proxy :: Proxy BitcoinTransaction)
			]
			"CREATE TABLE \"bitcoin\" OF \"BitcoinBlock\" (PRIMARY KEY (\"height\"));"
		, bci_flattenSuffixes = ["blocks", "transactions", "vins", "vouts"]
		, bci_flattenPack = let
			f (blocks, (transactions, vins, vouts)) =
				[ SomeBlocks (blocks :: [BitcoinBlock_flattened])
				, SomeBlocks (transactions :: [BitcoinTransaction_flattened])
				, SomeBlocks (vins :: [BitcoinVin_flattened])
				, SomeBlocks (vouts :: [BitcoinVout_flattened])
				]
			in f . mconcat . map flatten
		}

	getCurrentBlockHeight (Bitcoin jsonRpc) = (+ (-1)) <$> jsonRpcRequest jsonRpc "getblockcount" ([] :: V.Vector J.Value)

	getBlockByHeight (Bitcoin jsonRpc) blockHeight = do
		blockHash <- jsonRpcRequest jsonRpc "getblockhash" ([J.Number $ fromIntegral blockHeight] :: V.Vector J.Value)
		jsonRpcRequest jsonRpc "getblock" ([blockHash, J.Number 2] :: V.Vector J.Value)

	blockHeightFieldName _ = "height"
