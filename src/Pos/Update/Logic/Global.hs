{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE Rank2Types          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Logic of local data processing in Update System.

module Pos.Update.Logic.Global
       ( usApplyBlocks
       , usRollbackBlocks
       , usVerifyBlocks
       ) where

import           Control.Lens         ((^.))
import           Control.Monad.Except (MonadError, runExceptT)
import           Data.Default         (Default (def))
import           Data.List.NonEmpty   (NonEmpty)
import           System.Wlog          (WithLogger, logError)
import           Universum

import qualified Pos.DB               as DB
import           Pos.Types            (Block, NEBlocks, difficultyL, gbBody,
                                       mbUpdatePayload)
import           Pos.Update.Error     (USError (USInternalError))
import           Pos.Update.Poll      (DBPoll, MonadPoll, PollModifier, PollT,
                                       PollVerFailure, USUndo, execPollT,
                                       rollbackUSPayload, runDBPoll, runPollT,
                                       verifyAndApplyUSPayload)
import           Pos.Util             (Color (Red), colorize, inAssertMode)

type USGlobalApplyMode endless_useless m = (WithLogger m, DB.MonadDB endless_useless m)
type USGlobalVerifyMode ы m = (DB.MonadDB ы m, MonadError PollVerFailure m)

-- TODO: I suppose blocks are needed here only for sanity check, but who knows.
-- Anyway, it's ok.
-- TODO: but actually I suppose that such sanity checks should be done at higher
-- level.
-- | Apply chain of /definitely/ valid blocks to US part of GState DB
-- and to US local data. Head must be the __oldest__ block.  This
-- function assumes that no other thread applies block in parallel. It
-- also assumes that parent of oldest block is current tip.
usApplyBlocks
    :: (MonadThrow m, USGlobalApplyMode ssc m)
    => NEBlocks ssc -> PollModifier -> m [DB.SomeBatchOp]
usApplyBlocks blocks _ = do
    inAssertMode $ do
        verdict <- runExceptT $ usVerifyBlocks blocks
        either onFailure (const pass) verdict
    return []
  where
    onFailure failure = do
        let msg = "usVerifyBlocks failed in 'apply': " <> pretty failure
        logError $ colorize Red msg
        throwM $ USInternalError msg

-- | Revert application of given blocks to US part of GState DB
-- and US local data. Head must be the __youngest__ block. Caller must
-- ensure that tip stored in DB is 'headerHash' of head.
usRollbackBlocks
    :: forall ssc m.
       (USGlobalApplyMode ssc m)
    => NonEmpty (Block ssc, USUndo) -> m [DB.SomeBatchOp]
usRollbackBlocks blunds =
    modifierToBatch <$> (runDBPoll . execPollT def $ mapM_ rollbackDo blunds)
  where
    rollbackDo :: (Block ssc, USUndo) -> PollT (DBPoll m) ()
    rollbackDo (Left _, _) = pass
    rollbackDo (Right blk, undo) =
        rollbackUSPayload
            (blk ^. difficultyL)
            (blk ^. gbBody . mbUpdatePayload)
            undo

-- | Verify whether sequence of blocks can be applied to US part of
-- current GState DB.  This function doesn't make pure checks, they
-- are assumed to be done earlier, most likely during objects
-- construction.
usVerifyBlocks
    :: (USGlobalVerifyMode ssc m)
    => NEBlocks ssc -> m (PollModifier, NonEmpty USUndo)
usVerifyBlocks blocks = convertRes <$> run (mapM verifyBlock blocks)
  where
    run = runDBPoll . runPollT def
    convertRes (undos, modifier) = (modifier, undos)

verifyBlock
    :: (USGlobalVerifyMode ssc m, MonadPoll m)
    => Block ssc -> m USUndo
verifyBlock (Left _)    = pure def
verifyBlock (Right blk) =
    verifyAndApplyUSPayload True (blk ^. gbBody . mbUpdatePayload)

modifierToBatch :: PollModifier -> [DB.SomeBatchOp]
modifierToBatch = notImplemented
