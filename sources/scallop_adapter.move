module nui_finance::scallop_adapter{
    
    use protocol::{
        mint::{Self,},
        redeem::{Self},
        version:: {Version},
        market:: {Market},
        reserve::MarketCoin,
    };

    use nui_finance::random_lib::{Self,};  

    use sui::{
        coin::{Self, Coin},
        clock::{Clock},
        dynamic_field as df,
        balance::{Self, Balance},
    };

    use nui_finance::pool::{Self, GlobalConfig, Pool};
    use nui_finance::staked_share::{Self, StakedPoolShare, NumberPool, ShareSupply};

    const VERSION: u64 = 1;

    const EVersionNotMatched: u64 = 0;
    const EEmptySCoin:u64 = 1;
    const ELuckyNumberAlreadyGen: u64 = 2;

    public entry fun stake<PoolType, NativeType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<PoolType, NativeType, NativeType>,
        number_pool: &mut NumberPool<PoolType, NativeType, NativeType>,
        pool: &mut Pool<PoolType, NativeType, NativeType>,
        version: &Version,
        market: &mut Market,
        supply: Coin<NativeType>,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        let act_amount = supply.value();
        let scoin_balance = supply_to_scallop<PoolType, NativeType>(version, market, supply.into_balance(), clock, ctx);
        let scoin_amount = scoin_balance.value();
        
        // update pool balance
        let is_contain_proof = pool.contains_proof<PoolType, NativeType, NativeType, Balance<MarketCoin<NativeType>>>();
        
        // update balance record
        if (is_contain_proof){
            let proof = pool.borrow_mut_proof<PoolType, NativeType, NativeType, Balance<MarketCoin<NativeType>>>();            
            proof.join(scoin_balance);
        }else{
            pool.create_proof_container(false, scoin_balance);
        };

        // transfer share to user
        let mut shares: vector<StakedPoolShare<PoolType, NativeType, NativeType>> = staked_share::new_share<PoolType, NativeType, NativeType>(config, share_supply, number_pool, scoin_amount, act_amount, ctx);
        
        while(!shares.is_empty()){
            let share = shares.pop_back();
            transfer::public_transfer(share, ctx.sender());
        };
        shares.destroy_empty();

        // update statistics
        pool.update_statistic_for_stake(ctx.sender(), act_amount);
    }

    public entry fun withdraw<PoolType, NativeType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<PoolType, NativeType, NativeType>,
        number_pool: &mut NumberPool<PoolType, NativeType, NativeType>,
        pool: &mut Pool<PoolType, NativeType, NativeType>,
        mut share: StakedPoolShare<PoolType, NativeType, NativeType>,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        ctx:&mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        let amount = share.amount();
        let share_id = share.uid().uid_to_inner();
        let act_amount = *(df::borrow<ID, u64>(share.uid(),share_id ));

        let is_contain_proof = pool.contains_proof<PoolType, NativeType, NativeType, Balance<MarketCoin<NativeType>>>();
        if (is_contain_proof){
            let mut proof = pool.extract_proof<PoolType, NativeType, NativeType, Balance<MarketCoin<NativeType>>>();
            
            let mut withdraw_scoin_balance = balance::zero<MarketCoin<NativeType>>();
            let proof_val = proof.value();
            if (amount > proof_val){
                withdraw_scoin_balance.join(proof.split(proof_val));
            }else{
                withdraw_scoin_balance.join(proof.split(amount));
            };
            
            
            let mut withdraw_native_balance = withdraw_from_scallop<NativeType>(version, market, withdraw_scoin_balance, clock, ctx);
            
            if (withdraw_native_balance.value() < act_amount){
                let total_amount = withdraw_native_balance.value();
                let to_user_balance = withdraw_native_balance.split(total_amount);
                transfer::public_transfer(coin::from_balance(to_user_balance, ctx), ctx.sender());
            }else{
                let to_user_balance = withdraw_native_balance.split(act_amount);
                transfer::public_transfer(coin::from_balance(to_user_balance, ctx), ctx.sender());
            };
            
            // reward to pool
            let rewards_mut = pool.borrow_mut_rewards();

            rewards_mut.join(withdraw_native_balance);

            // put share to number pool
            number_pool.to_number_pool(share_supply, share);

            // update statistics
            pool.update_statistic_for_withdraw(ctx.sender(), act_amount);

            pool.reput_proof(proof);
        }else{
            abort (EEmptySCoin)
        };

    }

    public entry fun allocate_reward<PoolType, NativeType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<PoolType, NativeType, NativeType>,
        pool: &mut Pool<PoolType, NativeType, NativeType>,
        version: &Version,
        market: &mut Market,
        bls_sig: vector<u8>,
        public_key: vector<u8>,
        message: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        assert!(!df::exists_(pool.uid(), pool.current_round()), ELuckyNumberAlreadyGen);
        
        // check time
        pool.check_arrived_reward_time<PoolType, NativeType, NativeType>(clock);

        let mut proof = pool.extract_proof<PoolType, NativeType, NativeType, Balance<MarketCoin<NativeType>>>();
        let scoin_amount = proof.value();
        let withdraw_scoin_balance = proof.split(scoin_amount);
        
        let mut withdraw_native_balance = withdraw_from_scallop<NativeType>(version, market, withdraw_scoin_balance, clock, ctx);
        let original_staked_amount = share_supply.active_supply<PoolType, NativeType, NativeType>();

        let mut restake_native_balance = balance::zero<NativeType>();
        let withdraw_native_balance_value = withdraw_native_balance.value();
        if (original_staked_amount > withdraw_native_balance_value){
            restake_native_balance.join(withdraw_native_balance.split(withdraw_native_balance_value));
        }else{
            restake_native_balance.join(withdraw_native_balance.split(original_staked_amount));
        };

        let restake_scoin_balance = supply_to_scallop<PoolType, NativeType>(version, market, restake_native_balance, clock, ctx);
        proof.join(restake_scoin_balance);
        
        let rewards_mut = pool.borrow_mut_rewards();
        rewards_mut.join(withdraw_native_balance);

        let reward_amount = rewards_mut.value();
        let mut rewards = rewards_mut.split(reward_amount);
        
        // allocate rewards 
        let platform_income_amount = (reward_amount * pool.platform_ratio()) / 10_000;
        let platform_income = rewards.split(platform_income_amount);
        transfer::public_transfer(coin::from_balance(platform_income, ctx), pool::platform_address(config));
        
        let payer_reward_amount = (reward_amount * pool.allocate_gas_payer_ratio()) / 10_000;
        let payer_income = rewards.split(payer_reward_amount);
        transfer::public_transfer(coin::from_balance(payer_income, ctx), ctx.sender());

        // random select function 
        let lucky_num = random_lib::verify_and_random(config, pool, bls_sig, public_key, message,share_supply.total_supply<PoolType, NativeType, NativeType>(), clock);

        // add round info
        let current_round = pool.current_round<PoolType, NativeType, NativeType>();
        
        df::add<u64, u64>(pool.uid(), current_round, lucky_num);

        
        // combine prevoius rewards
        let mut round = current_round - 1;
        loop{
            let mut previous_reward_opt = pool.extract_previous_rewards<PoolType, NativeType, NativeType>(round);
            if (previous_reward_opt.is_none()){
                previous_reward_opt.destroy_none();
                break
            }else{
                rewards.join(previous_reward_opt.extract());
                previous_reward_opt.destroy_none();
                round = round - 1;
            };
        };
        
        pool.put_current_round_reward_to_claimable<PoolType, NativeType, NativeType>(rewards);
        pool.reput_proof(proof);

        pool.next_round();
        pool.update_time(clock);
        pool.add_expired_data();
    }

    #[allow(lint(self_transfer))]
    public entry fun claim_reward<PoolType, NativeType>(
        config: &GlobalConfig,
        pool: &mut Pool<PoolType, NativeType, NativeType>,
        round: u64,
        mut shares: vector<StakedPoolShare<PoolType, NativeType, NativeType>>,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        pool.check_claim_expired(round, clock);
        pool.check_is_claimed(round);
        pool.check_round_could_claim_reward<PoolType, NativeType, NativeType>(round);

        let lucky_num = *df::borrow<u64, u64>(pool.uid(), round );
        let mut cnt: u64 = 0;
        while(cnt < shares.length()){
            let share = shares.borrow(cnt);
            let start = share.start_num(); 
            let end = share.end_num(); 
            
            if ((lucky_num >= start) && (lucky_num <= end)){
                let reward = pool.extract_round_claimable_reward(round);

                pool.add_claimed_info(round, ctx.sender(), reward.value());

                transfer::public_transfer(coin::from_balance(reward, ctx), ctx.sender()); 
                
                break
                
            }else{
                cnt = cnt + 1u64;
                continue
            }
            
        };
        
        // tmp, need to be remove
        loop{
            let share = shares.pop_back();
            transfer::public_transfer(share, ctx.sender());

            if (vector::is_empty(&shares)){
                shares.destroy_empty();
                break
            };
        }
    }
    
    #[allow(unused_type_parameter)]
    fun supply_to_scallop<PoolType, NativeType>(
        version: &Version,
        market: &mut Market,
        bal: Balance<NativeType>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Balance<MarketCoin<NativeType>>{
        let s_coin = mint::mint<NativeType>(version, market, coin::from_balance(bal, ctx), clock, ctx);
        coin::into_balance(s_coin)
    }

    #[allow(lint(self_transfer))]
    fun withdraw_from_scallop<NativeType>(
        version: &Version,
        market: &mut Market,
        sbalance: Balance<MarketCoin<NativeType>>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Balance<NativeType>{ 
        let staked_coin = redeem::redeem(version, market, coin::from_balance(sbalance, ctx), clock, ctx);
        coin::into_balance(staked_coin)
    }

    
}
