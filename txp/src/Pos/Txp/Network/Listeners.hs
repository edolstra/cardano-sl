{-# LANGUAGE CPP        #-}
{-# LANGUAGE DataKinds  #-}
{-# LANGUAGE RankNTypes #-}

-- | Server which handles transactions.
--
-- TODO rename this module. It doesn't define any listeners and doesn't deal
-- with a network.

module Pos.Txp.Network.Listeners
       ( handleTxDo
       , TxpMode
       ) where

import           Data.Tagged (Tagged (..))
import           Formatting (sformat, (%))
import qualified Formatting as F
import           Node.Message.Class (Message)
import           System.Wlog (WithLogger, logInfo)
import           Universum

import           Pos.Binary.Txp ()
import           Pos.Core.Txp (TxAux (..), TxId)
import           Pos.Crypto (ProtocolMagic, hash)
import qualified Pos.Infra.Communication.Relay as Relay
import           Pos.Infra.Util.JsonLog.Events (JLEvent (..), JLTxR (..))
import           Pos.Txp.MemState (MempoolExt, MonadTxpLocal, MonadTxpMem,
                     txpProcessTx)
import           Pos.Txp.Network.Types (TxMsgContents (..))

-- Real tx processing
-- CHECK: @handleTxDo
-- #txProcessTransaction
handleTxDo
    :: TxpMode ctx m
    => ProtocolMagic
    -> (JLEvent -> m ())  -- ^ How to log transactions
    -> TxAux              -- ^ Incoming transaction to be processed
    -> m Bool
handleTxDo pm logTx txAux = do
    let txId = hash (taTx txAux)
    res <- txpProcessTx pm (txId, txAux)
    let json me = logTx $ JLTxReceived $ JLTxR
            { jlrTxId     = sformat F.build txId
            , jlrError    = me
            }
    case res of
        Right _ -> do
            logInfo $
                sformat ("Transaction has been added to storage: "%F.build) txId
            json Nothing
            pure True
        Left er -> do
            logInfo $
                sformat ("Transaction hasn't been added to storage: "%F.build%" , reason: "%F.build) txId er
            json $ Just $ sformat F.build er
            pure False

----------------------------------------------------------------------------
-- Mode
----------------------------------------------------------------------------

type TxpMode ctx m =
    ( MonadIO m
    , WithLogger m
    , MonadTxpLocal m
    , MonadTxpMem (MempoolExt m) ctx m
    , Each '[Message]
        '[ Relay.InvOrData (Tagged TxMsgContents TxId) TxMsgContents
         , Relay.InvMsg    (Tagged TxMsgContents TxId)
         , Relay.ReqOrRes  (Tagged TxMsgContents TxId)
         , Relay.ReqMsg    (Tagged TxMsgContents TxId)
         , Relay.MempoolMsg TxMsgContents
         ]
    )
