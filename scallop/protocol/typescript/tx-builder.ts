import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui.js";
import { SuiTxBlock, SuiTxArg } from "@scallop-io/sui-kit";

export type RiskModel = {
  collateralFactor: number,
  liquidationFactor: number,
  liquidationPanelty: number,
  liquidationDiscount: number,
  scale: number,
  maxCollateralAmount: number,
}

export type InterestModel = {
  baseBorrowRatePerSec: number,
  interestRateScale: number,
  borrowRateOnMidKink: number,
  midKink: number,
  borrowRateOnHighKink: number,
  highKink: number,
  maxBorrowRate: number,
  revenueFactor: number,
  borrowWeight: number,
  scale: number,
  minBorrowAmount: number,
}

export type OutflowLimiterModel = {
  outflowLimit: number,
  outflowCycleDuration: number,
  outflowSegmentDuration: number,
}

export type IncentiveRewardFactor = {
  rewardFactor: number,
  scale: number,
}

export type BorrowFee = {
  numerator: number,
  denominator: number,
}

export class ProtocolTxBuilder {
  constructor(
    public packageId: string,
    public adminCapId: string,
    public marketId: string,
    public versionId: string,
    public versionCapId: string,
    public obligationAccessStoreId: string,
  ) { }

  addRiskModel(
    suiTxBlock: SuiTxBlock,
    riskModel: RiskModel,
    coinType: string,
  ) {
    const createRiskModelChangeTarget = `${this.packageId}::app::create_risk_model_change`;
    let riskModelChange= suiTxBlock.moveCall(
      createRiskModelChangeTarget,
      [
        this.adminCapId,
        riskModel.collateralFactor,
        riskModel.liquidationFactor,
        riskModel.liquidationPanelty,
        riskModel.liquidationDiscount,
        riskModel.scale,
        riskModel.maxCollateralAmount,
      ],
      [coinType],
    );
    const addRiskModelTarget = `${this.packageId}::app::add_risk_model`;
    suiTxBlock.moveCall(
      addRiskModelTarget,
      [this.marketId, this.adminCapId, riskModelChange],
      [coinType],
    );
  }

  updateRiskModel(
    suiTxBlock: SuiTxBlock,
    riskModel: RiskModel,
    coinType: string,
  ) {
    const createRiskModelChangeTarget = `${this.packageId}::app::create_risk_model_change`;
    let riskModelChange= suiTxBlock.moveCall(
      createRiskModelChangeTarget,
      [
        this.adminCapId,
        riskModel.collateralFactor,
        riskModel.liquidationFactor,
        riskModel.liquidationPanelty,
        riskModel.liquidationDiscount,
        riskModel.scale,
        riskModel.maxCollateralAmount,
      ],
      [coinType],
    );
    const updateRiskModelTarget = `${this.packageId}::app::update_risk_model`;
    suiTxBlock.moveCall(
      updateRiskModelTarget,
      [this.marketId, this.adminCapId, riskModelChange],
      [coinType],
    );
  }

  addInterestModel(
    suiTxBlock: SuiTxBlock,
    interestModel: InterestModel,
    coinType: string,
  ) {
    const createInterestModelChangeTarget = `${this.packageId}::app::create_interest_model_change`;
    let interestModelChange= suiTxBlock.moveCall(
      createInterestModelChangeTarget,
      [
        this.adminCapId,
        interestModel.baseBorrowRatePerSec,
        interestModel.interestRateScale,
        interestModel.borrowRateOnMidKink,
        interestModel.midKink,
        interestModel.borrowRateOnHighKink,
        interestModel.highKink,
        interestModel.maxBorrowRate,
        interestModel.revenueFactor,
        interestModel.borrowWeight,
        interestModel.scale,
        interestModel.minBorrowAmount,
      ],
      [coinType],
    );
    const addInterestModelTarget = `${this.packageId}::app::add_interest_model`;
    suiTxBlock.moveCall(
      addInterestModelTarget,
      [this.marketId, this.adminCapId, interestModelChange, SUI_CLOCK_OBJECT_ID],
      [coinType],
    );
  }
  
  updateInterestModel(
    suiTxBlock: SuiTxBlock,
    interestModel: InterestModel,
    coinType: string,
  ) {
    const createInterestModelChangeTarget = `${this.packageId}::app::create_interest_model_change`;
    let interestModelChange= suiTxBlock.moveCall(
      createInterestModelChangeTarget,
      [
        this.adminCapId,
        interestModel.baseBorrowRatePerSec,
        interestModel.interestRateScale,
        interestModel.borrowRateOnMidKink,
        interestModel.midKink,
        interestModel.borrowRateOnHighKink,
        interestModel.highKink,
        interestModel.maxBorrowRate,
        interestModel.revenueFactor,
        interestModel.borrowWeight,
        interestModel.scale,
        interestModel.minBorrowAmount,
      ],
      [coinType],
    );
    const addInterestModelTarget = `${this.packageId}::app::update_interest_model`;
    suiTxBlock.moveCall(
      addInterestModelTarget,
      [this.marketId, this.adminCapId, interestModelChange],
      [coinType],
    );
  }

  addLimiter(
    suiTxBlock: SuiTxBlock,
    outflowLimiterModel: OutflowLimiterModel,
    coinType: string,
  ) {
    const addLimiterTarget = `${this.packageId}::app::add_limiter`;
    suiTxBlock.moveCall(
      addLimiterTarget,
      [
        this.adminCapId,
        this.marketId,
        outflowLimiterModel.outflowLimit,
        outflowLimiterModel.outflowCycleDuration,
        outflowLimiterModel.outflowSegmentDuration,
      ],
      [coinType],
    );
  }

  addWhitelistAddress(
    suiTxBlock: SuiTxBlock,
    address: string,
  ) {
    const marketUidMutTarget = `${this.packageId}::app::add_whitelist_address`;
    return suiTxBlock.moveCall(
      marketUidMutTarget,
      [
        this.adminCapId,
        this.marketId,
        suiTxBlock.pure(address),
      ],
    );
  }

  setIncentiveRewardFactor(
    suiTxBlock: SuiTxBlock,
    incentiveRewardFactor: IncentiveRewardFactor,
    coinType: string,
  ) {
    const setIncentiveRewardFactorTarget = `${this.packageId}::app::set_incentive_reward_factor`;
    suiTxBlock.moveCall(
      setIncentiveRewardFactorTarget,
      [
        this.adminCapId,
        this.marketId,
        incentiveRewardFactor.rewardFactor,
        incentiveRewardFactor.scale
      ],
      [coinType],
    );
  }

  supplyBaseAsset(
    suiTxBlock: SuiTxBlock,
    coinId: SuiTxArg,
    coinType: string,
  ) {
    suiTxBlock.moveCall(
      `${this.packageId}::mint::mint_entry`,
      [this.versionId, this.marketId, coinId, SUI_CLOCK_OBJECT_ID],
      [coinType]
    );
  }

  openObligation(suiTxBlock: SuiTxBlock) {
    return suiTxBlock.moveCall(
      `${this.packageId}::open_obligation::open_obligation`,
      [this.versionId],
    );
  }

  returnObligation(
    suiTxBlock: SuiTxBlock,
    obligation: SuiTxArg,
    obligationHotPotato: SuiTxArg,
  ) {
    suiTxBlock.moveCall(
      `${this.packageId}::open_obligation::return_obligation`,
      [this.versionId, obligation, obligationHotPotato],
    );
  }

  addCollateral(
    suiTxBlock: SuiTxBlock,
    obligation: SuiTxArg,
    coin: SuiTxArg,
    coinType: string,
  ) {
    suiTxBlock.moveCall(
      `${this.packageId}::deposit_collateral::deposit_collateral`,
      [this.versionId, obligation, this.marketId, coin],
      [coinType]
    );
  }

  removeCollateral(
    suiTxBlock: SuiTxBlock,
    obligation: SuiTxArg,
    obligationKey: SuiTxArg,
    decimalsRegistry: SuiTxArg,
    withdrawAmount: number,
    xOracle: SuiTxArg,
    coinType: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::withdraw_collateral::withdraw_collateral`,
      [
        this.versionId,
        obligation,
        obligationKey,
        this.marketId,
        decimalsRegistry,
        withdrawAmount,
        xOracle,
        SUI_CLOCK_OBJECT_ID
      ],
      [coinType]
    );
  }


  borrowBaseAsset(
    suiTxBlock: SuiTxBlock,
    obligation: SuiTxArg,
    obligationKey: SuiTxArg,
    decimalsRegistry: SuiTxArg,
    brrowAmount: number,
    xOracle: SuiTxArg,
    coinType: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::borrow::borrow`,
      [
        this.versionId,
        obligation,
        obligationKey,
        this.marketId,
        decimalsRegistry,
        brrowAmount,
        xOracle,
        SUI_CLOCK_OBJECT_ID
      ],
      [coinType]
    );
  }

  setBaseAssetActiveState(
    suiTxBlock: SuiTxBlock,
    isActive: boolean,
    coinType: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::app::set_base_asset_active_state`,
      [
        this.adminCapId,
        this.marketId,
        suiTxBlock.pure(isActive),
      ],
      [coinType]
    );
  }

  setCollateralActiveState(
    suiTxBlock: SuiTxBlock,
    isActive: boolean,
    coinType: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::app::set_collateral_active_state`,
      [
        this.adminCapId,
        this.marketId,
        suiTxBlock.pure(isActive),
      ],
      [coinType]
    );
  }

  addLockKey(
    suiTxBlock: SuiTxBlock,
    keyType: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::app::add_lock_key`,
      [
        this.adminCapId,
        this.obligationAccessStoreId,
      ],
      [keyType]
    );
  }

  updateBorrowFee(
    suiTxBlock: SuiTxBlock,
    borrowFee: BorrowFee,
    coinType: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::app::update_borrow_fee`,
      [
        this.adminCapId,
        this.marketId,
        borrowFee.numerator,
        borrowFee.denominator,
      ],
      [coinType]
    );
  }

  updateBorrowFeeRecipient(
    suiTxBlock: SuiTxBlock,
    recipient: string,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::app::update_borrow_fee_recipient`,
      [
        this.adminCapId,
        this.marketId,
        suiTxBlock.pure(recipient, 'address'),
      ],
    );
  }

  incrementVersion(
    suiTxBlock: SuiTxBlock,
  ) {
    return suiTxBlock.moveCall(
      `${this.packageId}::version::upgrade`,
      [
        this.versionId,
        this.versionCapId,
      ],
    );
  }
}
