module nui_finance::bucket_adapter{
    
    use flask::sbuck::{Self, Flask, SBUCK};
    use bucket_fountain::fountain_core::{Self, Fountain, StakeProof};
    use nui_finance::pool::{Self, BUCKET_PROTOCOL, GlobalConfig, Pool};
    use nui_finance::staked_share::{Self, StakedPoolShare, NumberPool, ShareSupply};

    use nui_finance::random_lib::{Self,};    
    use sui::{
        coin::{Self, Coin,},
        clock::{Self, Clock,},
        balance::{Self, Balance},
        dynamic_field as df,
    };

    const VERSION: u64 = 1;

    const EVersionNotMatched: u64 = 0;
    const EEmptyStakeProof: u64 = 1;
    const ELuckyNumberAlreadyGen: u64 = 2;

    public entry fun stake<NativeType, RewardType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<BUCKET_PROTOCOL, NativeType, RewardType>,
        number_pool: &mut NumberPool<BUCKET_PROTOCOL, NativeType, RewardType>,
        pool: &mut Pool<BUCKET_PROTOCOL, NativeType, RewardType>,
        self: &mut Flask<NativeType>,
        deposit: Coin<NativeType>,
        fountain: &mut Fountain<SBUCK, RewardType>,
        lock_time: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);

        let act_amount = coin::value(&deposit);
        let sbuck_balance = sbuck::deposit<NativeType>(self, deposit);
        let staked_proof = fountain_core::stake<SBUCK, RewardType>(clock, fountain, sbuck_balance, lock_time, ctx);
        let stake_proof_amount = staked_proof.get_proof_stake_amount();
        
        let is_contain_proof = pool.contains_proof<BUCKET_PROTOCOL, NativeType, RewardType, StakeProof<SBUCK, RewardType>>();

        // update balance record
        if (is_contain_proof){
            let proof_list = pool.borrow_mut_vec_proof<BUCKET_PROTOCOL, NativeType, RewardType, StakeProof<SBUCK, RewardType>>();
            proof_list.push_back(staked_proof);
        }else{
            pool.create_proof_container(true, staked_proof);
        };

        // transfer share to user
        let mut shares: vector<StakedPoolShare<BUCKET_PROTOCOL, NativeType, RewardType>> = staked_share::new_share<BUCKET_PROTOCOL, NativeType, RewardType>(config, share_supply, number_pool, stake_proof_amount, act_amount ,ctx);
        
        while(!shares.is_empty()){
            let share = shares.pop_back();
            transfer::public_transfer(share, ctx.sender());
        };
        shares.destroy_empty();

        // update statistics
        pool.update_statistic_for_stake(ctx.sender(), act_amount);
    }

    public entry fun withdraw<NativeType, RewardType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<BUCKET_PROTOCOL, NativeType, RewardType>,
        number_pool: &mut NumberPool<BUCKET_PROTOCOL, NativeType, RewardType>,
        pool: &mut Pool<BUCKET_PROTOCOL, NativeType, RewardType>,
        clock: &Clock,
        self: &mut Flask<NativeType>,
        fountain: &mut Fountain<SBUCK, RewardType>,
        mut share: StakedPoolShare<BUCKET_PROTOCOL, NativeType, RewardType>,
        lock_time: u64,
        ctx:&mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);

        let amount = share.amount();
        let mut require_amount = amount;
        let share_id = share.uid().uid_to_inner();
        let act_amount = *(df::borrow<ID, u64>(share.uid(),share_id ));

        let is_contain_proof = pool.contains_proof<BUCKET_PROTOCOL, NativeType, RewardType, StakeProof<SBUCK, RewardType>>();
        if (is_contain_proof){
            let mut proof_list = pool.extract_vec_proof<BUCKET_PROTOCOL, NativeType, RewardType, StakeProof<SBUCK, RewardType>>();
            let mut total_reward_balance = balance::zero<RewardType>();

            while(proof_list.length() > 0){
                let proof = proof_list.pop_back();
                let proof_amount = proof.get_proof_stake_amount();

                if (proof_amount > require_amount){
                    let (mut sbuck_balance, reward_balance) = fountain_core::force_unstake<SBUCK, RewardType>(clock, fountain, proof);
                    let to_user_sbuck_balance = sbuck_balance.split(require_amount);
                    
                    total_reward_balance.join(reward_balance);
                    
                    let to_user_buck_balance = sbuck::withdraw<NativeType>(self, coin::from_balance<SBUCK>(to_user_sbuck_balance, ctx));
                    let to_user_buck_coin = coin::from_balance<NativeType>(to_user_buck_balance, ctx);
                    transfer::public_transfer(to_user_buck_coin, ctx.sender());
 
                    // restake
                    let restake_proof = fountain_core::stake<SBUCK, RewardType>(clock, fountain, sbuck_balance, lock_time, ctx);
                    proof_list.push_back(restake_proof);

                    break
                }else if (proof_amount == require_amount){
                    let (sbuck_balance, reward_balance) = fountain_core::force_unstake<SBUCK, RewardType>(clock, fountain, proof);
                    let sbuck_coin = coin::from_balance<SBUCK>(sbuck_balance, ctx);
                    total_reward_balance.join(reward_balance);
                    let buck_balance = sbuck::withdraw<NativeType>(self, sbuck_coin);
                    let buck_coin = coin::from_balance<NativeType>(buck_balance, ctx);
                    
                    transfer::public_transfer(buck_coin, ctx.sender());

                    break
                }else{
                    let (sbuck_balance, reward_balance) = fountain_core::force_unstake<SBUCK, RewardType>(clock, fountain, proof);
                    require_amount = require_amount - sbuck_balance.value();
                    let sbuck_coin = coin::from_balance<SBUCK>(sbuck_balance, ctx);
                    
                    total_reward_balance.join(reward_balance);
                    let buck_balance = sbuck::withdraw<NativeType>(self, sbuck_coin);
                    let buck_coin = coin::from_balance<NativeType>(buck_balance, ctx);  
                    
                    transfer::public_transfer(buck_coin, ctx.sender());
                    
                };
            };

            // reward to pool
            let rewards = pool.borrow_mut_rewards();
            rewards.join(total_reward_balance);

            // update statistics
            pool.update_statistic_for_withdraw(ctx.sender(), act_amount);

            // put share to number pool
            number_pool.to_number_pool(share_supply, share);
            pool.reput_vec_proof(proof_list);

        }else{
            abort (EEmptyStakeProof)
        };
    }

    public entry fun allocate_reward<NativeType, RewardType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<BUCKET_PROTOCOL, NativeType, RewardType>,
        pool: &mut Pool<BUCKET_PROTOCOL, NativeType, RewardType>,
        fountain: &mut Fountain<SBUCK, RewardType>,
        bls_sig: vector<u8>,
        public_key: vector<u8>,
        message: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        assert!(!df::exists_(pool.uid(), pool.current_round()), ELuckyNumberAlreadyGen);
        
        // check time
        pool.check_arrived_reward_time<BUCKET_PROTOCOL, NativeType, RewardType>(clock);

        let mut proof_list = pool.extract_vec_proof<BUCKET_PROTOCOL, NativeType, RewardType, StakeProof<SBUCK, RewardType>>();
        
        let mut total_withdraw_reward_balance = balance::zero<RewardType>();
        let withdraw_balance = extract_all_rewards_from_proofs<RewardType>(&mut proof_list, fountain, clock);
        total_withdraw_reward_balance.join<RewardType>(withdraw_balance);
        
        let reward_mut = pool.borrow_mut_rewards();
        reward_mut.join(total_withdraw_reward_balance);
        let reward_amount = reward_mut.value();
        let mut rewards = reward_mut.split(reward_amount);
        
        
        // allocate rewards 
        let platform_income_amount = (reward_amount * pool.platform_ratio()) / 10_000;
        let platform_income = rewards.split(platform_income_amount);
        transfer::public_transfer(coin::from_balance(platform_income, ctx), pool::platform_address(config));
        
        let payer_reward_amount = (reward_amount * pool.allocate_gas_payer_ratio()) / 10_000;
        let payer_income = rewards.split(payer_reward_amount);
        transfer::public_transfer(coin::from_balance(payer_income, ctx), ctx.sender());

        // random select function 
        let lucky_num = random_lib::verify_and_random(config, pool, bls_sig, public_key, message, share_supply.total_supply<BUCKET_PROTOCOL, NativeType, RewardType>(), clock);
        // add round info
        let current_round = pool.current_round<BUCKET_PROTOCOL, NativeType, RewardType>();
        
        df::add<u64, u64>(pool.uid(), current_round, lucky_num);

        
        // combine prevoius rewards
        let mut round = current_round - 1;
        loop{
            let mut previous_reward_opt = pool.extract_previous_rewards<BUCKET_PROTOCOL, NativeType, RewardType>(round);
            if (previous_reward_opt.is_none()){
                previous_reward_opt.destroy_none();
                break
            }else{
                rewards.join(previous_reward_opt.extract());
                previous_reward_opt.destroy_none();
                round = round - 1;
            };
        };
        pool.reput_vec_proof(proof_list);
        pool.put_current_round_reward_to_claimable<BUCKET_PROTOCOL, NativeType, RewardType>(rewards);

        pool.next_round();
        pool.update_time(clock);
        pool.add_expired_data();
    }

    #[allow(lint(self_transfer))]
    public entry fun claim_reward<NativeType, RewardType>(
        config: &GlobalConfig,
        pool: &mut Pool<BUCKET_PROTOCOL, NativeType, RewardType>,
        round: u64,
        mut shares: vector<StakedPoolShare<BUCKET_PROTOCOL, NativeType, RewardType>>,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        pool.check_claim_expired(round, clock);
        pool.check_is_claimed(round);
        pool.check_round_could_claim_reward<BUCKET_PROTOCOL, NativeType, RewardType>(round);

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

    fun extract_all_rewards_from_proofs<RewardType>(
        proof_list: &mut vector<StakeProof<SBUCK, RewardType>>,
        fountain: &mut Fountain<SBUCK, RewardType>,
        clock: &Clock,
    ): Balance<RewardType>{
        let mut accumulate_balance = balance::zero<RewardType>();
        let mut cnt: u64 = 0;
        while(cnt < proof_list.length()){
            let proof = proof_list.borrow_mut(cnt);
            let reward_balance = fountain_core::claim<SBUCK, RewardType>(clock, fountain, proof);
            accumulate_balance.join(reward_balance);
            cnt = cnt + 1;
        };
        accumulate_balance
    }

    public entry fun get_current_reward<NativeType, RewardType>(
        pool: &mut Pool<BUCKET_PROTOCOL, NativeType, RewardType>,
        fountain: &Fountain<SBUCK, RewardType>,
        clock: &Clock,
    ): u64{
        let proof_list = pool.borrow_mut_vec_proof<BUCKET_PROTOCOL, NativeType, RewardType, StakeProof<SBUCK, RewardType>>();
        let mut amount = 0u64;
        let mut cnt = 0u64;
        while(cnt < proof_list.length()){
            let proof = proof_list.borrow(cnt);
            let reward = fountain_core::get_reward_amount(fountain, proof, clock::timestamp_ms(clock));
            amount = amount +reward;
            cnt = cnt + 1;
        };
        amount
    }


}