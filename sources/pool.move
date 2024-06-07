module nui_finance::pool{  
    use sui::{
        table::{Self, Table},
        clock::{Self, Clock},
        dynamic_object_field as dof,
        dynamic_field as df,
        balance::{Self, Balance}, 
        vec_set::{Self, VecSet},
    };

    use std::{
        type_name::{Self, TypeName},
        string::{Self, String},
    };

    const VERSION: u64 = 1;

    const EVersionNotMatched: u64 = 0;
    const EOverAllocateMax: u64 = 1;
    const ENotExpiredYet: u64 = 2;
    const EPoolDuplicated: u64 = 3;
    const ERewardsNotFound: u64 = 4;
    const EAlreadyClaimed: u64 = 5;
    const ERoundError: u64 = 6;
    const ESettlingNow: u64 = 7;
    const EClaimPhaseExpired: u64 = 8;
    const EWrongRound: u64 = 9;
    const EWrongTimeSetting: u64 = 10;
    const EUserNotExisted: u64 = 11;
    const EBalanceNotEnough: u64 = 12;
    const ERoundExisted: u64 = 13;

    
    public struct BUCKET_PROTOCOL has store, copy, drop{}
    public struct SCALLOP_PROTOCOL_SUI has store, copy, drop{}
    public struct SCALLOP_PROTOCOL has store, copy, drop{}


    public struct GlobalConfig has key {
        id : UID,
        version: u64, 
        platform: address,
    }

    public struct TimeInfo has store{
        start_time: u64,
        lock_stake_duration: u64,
        reward_duration: u64,
        expire_duration: u64,
    }

    public struct RewardAllocate has store{
        allocate_user_amount: u64,
        platform_ratio: u64,
        reward_ratio: u64,
        allocate_gas_payer_ratio: u64,
    }

    public struct Statistics has store{
        user_set: VecSet<address>,
        user_amount_table: Table<address, u64>,
        total_amount: u64,
    }
    public struct ClaimedInfo has store{
        winner: address, 
        reward_amount: u64,
    }

    public struct Pool< phantom PoolType, phantom NativeType, phantom RewardType> has key {
        id: UID,
        current_round: u64,
        time_info: TimeInfo,
        reward_allocate: RewardAllocate,
        rewards: Balance<RewardType>,
        claimable: Table<u64, Balance<RewardType>>,
        claimed: Table<u64, ClaimedInfo>,
        statistics: Statistics, 
    }

    public struct AdminCap has key{
        id: UID,
    }

    public struct RestakeReceipt {}

    public struct ClaimExpiredTime has store, copy, drop{}

    fun init (ctx: &mut TxContext){
        let adminCap = AdminCap{
            id: object::new(ctx),
        };

        let config = GlobalConfig{
            id: object::new(ctx),
            version: VERSION,
            platform: ctx.sender(), 
            // dynamic object field TypeName -> Table<TypeName, ID> 1. pooltype 2. coinType
        };

        transfer::transfer(adminCap, ctx.sender());
        transfer::share_object(config);
    }

    // @dev create pool by admin
    #[allow(lint(share_owned))]
    public entry fun new_pool<PoolType, NativeType, RewardType> (
        config: &mut GlobalConfig,
        _: &AdminCap,
        clock: &Clock,
        prepare_duration: u64,
        lock_stake_duration: u64,
        reward_duration: u64,
        expire_duration: u64,
        platform_ratio: u64,
        reward_ratio: u64,
        allocate_gas_payer_ratio: u64,
        ctx: &mut TxContext,
    ){
        assert!(config.version == VERSION, EVersionNotMatched);
        
        // check_duplicated<PoolType, NativeType, RewardType>(config);

        // create new pool
        let mut pool = create_pool<PoolType, NativeType, RewardType>(clock, prepare_duration,lock_stake_duration, reward_duration, expire_duration, platform_ratio, reward_ratio, allocate_gas_payer_ratio, ctx);

        // update type table
        if (dof::exists_(&config.id, type_name::get<PoolType>()) ){
            let type_table = dof::borrow_mut<TypeName, Table<TypeName, ID>>(&mut config.id, type_name::get<PoolType>());
            type_table.add<TypeName, ID>(type_name::get<NativeType>(), pool.id.uid_to_inner());
        }else{
            let mut type_table = table::new<TypeName, ID>(ctx);
            type_table.add<TypeName, ID>(type_name::get<NativeType>(), pool.id.uid_to_inner());
            dof::add<TypeName, Table<TypeName, ID>>(&mut pool.id, type_name::get<PoolType>(), type_table);
        };

        // record the pool type 
        record_pool<PoolType, NativeType, RewardType>(config, pool.id.uid_to_inner(), ctx);

        let mut expire_table = table::new<u64, u64>(ctx);
        expire_table.add(pool.current_round, (pool.time_info.start_time + expire_duration));
        dof::add(&mut pool.id, ClaimExpiredTime{}, expire_table);

        // pool to shared object
        transfer::share_object(pool)
    }

    public fun create_pool<PoolType, NativeType, RewardType>(
        clock: &Clock,
        prepare_duration: u64,
        lock_stake_duration: u64,
        reward_duration: u64,
        expire_duration: u64,
        platform_ratio: u64,
        reward_ratio: u64,
        allocate_gas_payer_ratio: u64,
        ctx: &mut TxContext,
    ): Pool<PoolType, NativeType, RewardType>{

        assert!((platform_ratio+ reward_ratio+ allocate_gas_payer_ratio) == 10_000, EOverAllocateMax);
        assert!(lock_stake_duration <=reward_duration, EWrongTimeSetting);
            
        Pool<PoolType, NativeType, RewardType>{
            id: object::new(ctx),
            current_round: 1,
            time_info: TimeInfo{ start_time: (clock::timestamp_ms(clock) + prepare_duration), reward_duration, lock_stake_duration, expire_duration,},
            reward_allocate: RewardAllocate{allocate_user_amount: 1, platform_ratio, reward_ratio, allocate_gas_payer_ratio,},
            rewards: balance::zero<RewardType>(),
            claimable: table::new(ctx),
            claimed: table::new(ctx),
            statistics: Statistics{ user_set: vec_set::empty<address>(), total_amount: 0u64, user_amount_table: table::new(ctx)},
        }
    }

    public entry fun set_expire_time(

    ){

    }

    public(package) fun borrow_mut_rewards<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): &mut Balance<RewardType>{
        &mut pool.rewards
    }


    public(package) fun put_current_round_reward_to_claimable<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        reward: Balance<RewardType>,
    ){
        pool.claimable.add(pool.current_round, reward);
    }

    public(package) fun extract_round_claimable_reward<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        round: u64,
    ): Balance<RewardType>{
        let reward = pool.claimable.remove(round);
        reward
    }

    public(package) fun check_round_reward_exist<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        round: u64,
    ) {
        assert!(pool.claimable.contains(round), ERewardsNotFound)
    }

    public(package) fun borrow_mut_claimed<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>
    ): &mut Table<u64, ClaimedInfo>{
        &mut pool.claimed
    }

    public(package) fun check_is_claimed<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        round: u64,
    ){
        assert!(!pool.claimed.contains(round), EAlreadyClaimed);
    }


    public(package) fun uid <PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): &mut UID{
        &mut pool.id
    }

    public(package) fun next_round <PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>
    ){
        pool.current_round = pool.current_round + 1;
    }

    public(package) fun check_arrived_reward_time<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        clock: &Clock,
    ){
        assert!((pool.time_info.start_time + pool.time_info.reward_duration) <= clock::timestamp_ms(clock), ENotExpiredYet);
    }

    public(package) fun check_arrived_lock_time<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        clock: &Clock,
    ){
        assert!((pool.time_info.start_time + pool.time_info.lock_stake_duration) <= clock::timestamp_ms(clock), ESettlingNow);
    }

    public(package) fun check_round_could_claim_reward<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        round: u64,
    ){
        assert!(pool.current_round > round, ERoundError);
    }

    public(package) fun check_claim_expired <PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        round: u64,
        clock: &Clock,
    ){
        let expire_table = dof::borrow<ClaimExpiredTime, Table<u64, u64>>(&pool.id, ClaimExpiredTime{});
        let expire_time  = *expire_table.borrow(round);
        assert!(expire_time >= clock::timestamp_ms(clock), EClaimPhaseExpired);
    }

    public(package) fun add_expired_data<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ){
        let expire_table = dof::borrow_mut<ClaimExpiredTime, Table<u64, u64>>(&mut pool.id, ClaimExpiredTime{});
        assert!(!expire_table.contains(pool.current_round), ERoundExisted);
        expire_table.add(pool.current_round, pool.time_info.start_time + pool.time_info.expire_duration);
    }

    public(package) fun is_claimed<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
        round: u64,
    ): bool{
        pool.claimed.contains(round)
    }


    public fun platform_ratio<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
    ): u64{
        pool.reward_allocate.platform_ratio
    }

    public fun allocate_gas_payer_ratio<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
    ): u64{
       pool.reward_allocate.allocate_gas_payer_ratio
    }

    public fun reward_ratio<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
    ): u64{
        pool.reward_allocate.reward_ratio
    }

    public fun platform_address(
        config: &GlobalConfig,
    ): address{
        config.platform
    }

    public fun current_round<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
    ): u64{
        pool.current_round
    }

    public(package) fun borrow_mut_proof<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): &mut ProofAsset{
        df::borrow_mut<TypeName, ProofAsset>(&mut pool.id, type_name::get<ProofAsset>())
    }

    public(package) fun borrow_mut_vec_proof<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): &mut vector<ProofAsset>{
        df::borrow_mut<TypeName, vector<ProofAsset>>(&mut pool.id, type_name::get<ProofAsset>())
    }

    public(package) fun extract_vec_proof<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): vector<ProofAsset>{
        df::remove<TypeName, vector<ProofAsset>>(&mut pool.id, type_name::get<ProofAsset>())
    }

    public(package) fun reput_vec_proof<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        vec: vector<ProofAsset>,
    ){
        df::add<TypeName, vector<ProofAsset>>(&mut pool.id, type_name::get<ProofAsset>(), vec);
    }

    public(package) fun reput_proof<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        bal: ProofAsset,
    ){
        df::add<TypeName, ProofAsset>(&mut pool.id, type_name::get<ProofAsset>(), bal);
    }

    public(package) fun extract_proof<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): ProofAsset{
        df::remove<TypeName, ProofAsset>(&mut pool.id, type_name::get<ProofAsset>())
    }

    public(package) fun borrow_vec_length<PoolType, NativeType, RewardType, ProofAsset: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
    ): u64{
        let proof_list = df::borrow_mut<TypeName, vector<ProofAsset>>(&mut pool.id, type_name::get<ProofAsset>());
        proof_list.length()
    }

    public(package) fun contains_proof<PoolType, NativeType, RewardType, ProofAsset>(
        pool: &Pool<PoolType, NativeType, RewardType>,
    ): bool{
        if(df::exists_(&pool.id, type_name::get<ProofAsset>())){
            true
        }else{
            false
        }
    }

    public(package) fun add_claimed_info<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        round: u64,
        winner: address,
        reward_amount: u64,
    ){
        pool.check_is_claimed(round);
        let claimed_info = ClaimedInfo{
            winner,
            reward_amount,
        };
        pool.claimed.add<u64, ClaimedInfo>(round, claimed_info);
    }

    public(package) fun update_time<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        clock: &Clock,
    ){
        pool.time_info.start_time = clock::timestamp_ms(clock);
    }

    #[allow(unused_function)]
    fun check_duplicated<PoolType, NativeType, RewardType>(
        config: &GlobalConfig,
    ){
        let native_type_vec8 = type_name::get<NativeType>().into_string();
        let reward_type_vec8 = type_name::get<RewardType>().into_string();
        let mut pool_detail_type = string::from_ascii(native_type_vec8);
        pool_detail_type.append(string::from_ascii(reward_type_vec8));
        
        if (dof::exists_(&config.id, type_name::get<PoolType>()) ){
            let type_table = dof::borrow<TypeName, Table<String, ID>>(&config.id, type_name::get<PoolType>());
            if (type_table.contains(pool_detail_type)){
                abort (EPoolDuplicated)
            }
        }
    }

    fun record_pool<PoolType, NativeType, RewardType>(
        config: &mut GlobalConfig,
        pool_id: ID,
        ctx: &mut TxContext,
    ){
        let native_type_vec8 = type_name::get<NativeType>().into_string();
        let reward_type_vec8 = type_name::get<RewardType>().into_string();
        let mut pool_detail_type = string::from_ascii(native_type_vec8);
        pool_detail_type.append(string::from_ascii(reward_type_vec8));


        if (dof::exists_(&config.id, type_name::get<PoolType>()) ){
            let type_table = df::borrow_mut<TypeName, Table<String, ID>>(&mut config.id, type_name::get<PoolType>());
            type_table.add(pool_detail_type, pool_id);
        }else{
            let mut type_table = table::new<String, ID>(ctx);
            type_table.add(pool_detail_type, pool_id);
            dof::add(&mut config.id, type_name::get<PoolType>(), type_table);
        }
    }

    public(package) fun extract_previous_rewards<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        round: u64,
    ): Option<Balance<RewardType>>{
        assert!(round < pool.current_round, EWrongRound);
        
        if (pool.claimable.contains(round)){
            option::some<Balance<RewardType>>(extract_round_claimable_reward<PoolType, NativeType, RewardType>(pool, round))
        }else{
            option::none<Balance<RewardType>>()
        }
        
    }

    public(package) fun update_statistic_for_stake<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        stake_user: address,
        amount: u64,
    ){
        pool.statistics.total_amount = pool.statistics.total_amount + amount;
        if (!pool.statistics.user_set.contains(&stake_user)){
            pool.statistics.user_set.insert(stake_user);
            pool.statistics.user_amount_table.add(stake_user, amount);
        }else{
            let mut original_amount = pool.statistics.user_amount_table.remove(stake_user);
            original_amount = original_amount + amount;
             pool.statistics.user_amount_table.add(stake_user, original_amount);
        }
    }

    public(package) fun update_statistic_for_withdraw<PoolType, NativeType, RewardType>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        withdraw_user: address,
        amount: u64,
    ){
        assert!(pool.statistics.user_amount_table.contains(withdraw_user), EUserNotExisted);
        let original_amount = pool.statistics.user_amount_table.remove(withdraw_user);
        assert!(original_amount >= amount, EBalanceNotEnough);
        pool.statistics.total_amount = pool.statistics.total_amount - amount;
        
        let remain_amount = original_amount - amount;

        if (remain_amount == 0){
            pool.statistics.user_set.remove(&withdraw_user);
        }else{
            pool.statistics.user_amount_table.add(withdraw_user, remain_amount);
        }; 
    }

    public(package) fun create_proof_container<PoolType, NativeType, RewardType, AssetProof: store>(
        pool: &mut Pool<PoolType, NativeType, RewardType>,
        is_vec: bool,
        init_obj: AssetProof,
    ){
        if (is_vec){
            let mut proof_list = vector::empty<AssetProof>();
            proof_list.push_back(init_obj);
            df::add(&mut pool.id, type_name::get<AssetProof>(), proof_list);
        }else{
            df::add(&mut pool.id, type_name::get<AssetProof>(),init_obj);
        };
    }

    public(package) fun current_total_amount<PoolType, NativeType, RewardType>(
        pool: &Pool<PoolType, NativeType, RewardType>,
    ): u64{
        pool.statistics.total_amount
    }
    public(package) fun config_veriosn(
        config: &GlobalConfig,
    ): u64{
        config.version
    }

    public entry fun upgrade_version(
        _: &AdminCap,
        config: &mut GlobalConfig,
    ){
        config.version = config.version + 1;
    }

    public fun update_platform(
        _: &AdminCap,
        config: &mut GlobalConfig,
        _new_platform: address,
    ){
        config.platform = _new_platform;
    }
}