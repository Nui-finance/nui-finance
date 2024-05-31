module nui_finance::staked_share{

    use nui_finance::pool::{Self,AdminCap};

    use sui::{
        dynamic_field as df,
    };

    use nui_finance::pool::{GlobalConfig};

    const VERSION: u64 = 1;

    const EVersionNotMatched: u64 = 0;
    const ENumberCannotCombine: u64 = 1;

    public struct NumberPool<phantom PoolType,phantom NativeType,phantom RewardType> has key{
        id: UID,
        available_shares: vector<StakedPoolShare<PoolType, NativeType, RewardType>>,
    }
    
    public struct StakedPoolShare<phantom PoolType, phantom NativeType, phantom RewardType> has key, store{
        id: UID, 
        start_num: u64,
        end_num: u64,
    }

    public struct ShareSupply<phantom PoolType, phantom NativeType, phantom RewardType> has key{
        id: UID,
        active_supply: u64,
        total_supply: u64,
    }

    public entry fun new_and_share_number_pool_and_share_supply<PoolType, NativeType, RewardType>(
        config: &GlobalConfig,
        _: &AdminCap,
        ctx: &mut TxContext,
    ){
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        let number_pool = NumberPool<PoolType, NativeType, RewardType>{
            id: object::new(ctx),
            available_shares: vector<StakedPoolShare<PoolType, NativeType, RewardType>>[],
        };

        transfer::share_object(number_pool);

        let share_supply = ShareSupply<PoolType, NativeType, RewardType>{
            id: object::new(ctx),
            active_supply: 0u64,
            total_supply: 0u64,
            
        };
        transfer::share_object(share_supply);
    }

    public(package) fun new_share<PoolType, NativeType, RewardType>(
        config: &GlobalConfig,
        share_supply: &mut ShareSupply<PoolType, NativeType, RewardType>,
        number_pool: &mut NumberPool<PoolType, NativeType, RewardType>,
        share_amount: u64, 
        actual_amount: u64,
        ctx: &mut TxContext,
    ): vector<StakedPoolShare<PoolType, NativeType, RewardType>>{
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        let mut require_amount = share_amount;
        let mut act_amount = actual_amount;
        if (number_pool.available_shares.length() == 0){
            
            let mut to_user_share = StakedPoolShare<PoolType, NativeType, RewardType>{
                    id: object::new(ctx), 
                    start_num: (share_supply.total_supply + 1),
                    end_num: (share_supply.total_supply + require_amount), 
            };

            share_supply.total_supply = share_supply.total_supply + require_amount;
            share_supply.active_supply = share_supply.active_supply + require_amount;

            let share_id = to_user_share.id.uid_to_inner();
            df::add<ID, u64>(&mut to_user_share.id, share_id, act_amount);

            vector<StakedPoolShare<PoolType, NativeType, RewardType>>[
                to_user_share,
            ]
        }else{
            let mut shares = vector<StakedPoolShare<PoolType, NativeType, RewardType>>[];
            while(number_pool.available_shares.length() != 0){
                let mut available_share = number_pool.available_shares.pop_back();
                let share_amount = (available_share.end_num - available_share.start_num) + 1;
                if (share_amount > require_amount){
                    let mut share_to_user = available_share.split(require_amount, ctx);                   
                    let share_to_user_id = share_to_user.id.uid_to_inner();
                    
                    df::remove<ID, u64>(&mut share_to_user.id, share_to_user_id);
                    df::add<ID, u64>(&mut share_to_user.id, share_to_user_id, act_amount);
                    shares.push_back(share_to_user);
                    
                    number_pool.available_shares.push_back(available_share);

                    share_supply.active_supply = share_supply.active_supply + require_amount;
                    require_amount = 0;  
                    break
                }else if (share_amount == require_amount){
                    let available_share_id = available_share.id.uid_to_inner();
                    df::remove<ID, u64>(&mut available_share.id, available_share_id);
                    df::add<ID, u64>(&mut available_share.id, available_share_id, act_amount);
                    shares.push_back(available_share);
                    share_supply.active_supply = share_supply.active_supply + require_amount;
                    require_amount = 0;
                    break
                }else{
                    let part_rate = ((share_amount as u128) * 1_000_000_000) / (require_amount as u128);
                    let current_act_amount = (((part_rate as u128) * (act_amount as u128)) / 1_000_000_000) as u64;
                    act_amount = act_amount - current_act_amount;
                    let available_share_id = available_share.id.uid_to_inner();
                    df::remove<ID, u64>(&mut available_share.id, available_share_id);
                    df::add<ID, u64>(&mut available_share.id, available_share_id, current_act_amount);
                    shares.push_back(available_share); 
                    require_amount = require_amount - share_amount;
                    share_supply.active_supply = share_supply.active_supply + share_amount;
                };
            };

            if (require_amount != 0){

                let mut last_user_share = StakedPoolShare<PoolType, NativeType, RewardType>{
                        id: object::new(ctx), 
                        start_num: (share_supply.total_supply + 1),
                        end_num: (share_supply.total_supply + require_amount), 
                };
                
                let last_user_share_id = last_user_share.id.uid_to_inner();
                df::add<ID, u64>(&mut last_user_share.id, last_user_share_id, act_amount);
                 

                shares.push_back(
                    last_user_share,
                );

                share_supply.total_supply = share_supply.total_supply + require_amount;
                share_supply.active_supply = share_supply.active_supply + require_amount;
            };
            shares
        }
    }

    public fun split<PoolType, NativeType, RewardType>(
        base_share: &mut StakedPoolShare<PoolType, NativeType, RewardType>,
        amount: u64,
        ctx: &mut TxContext,
    ): StakedPoolShare<PoolType, NativeType, RewardType>{
        let base_share_id =  base_share.id.uid_to_inner();
        let mut act_amount = df::remove<ID, u64>(&mut base_share.id, base_share_id);
        let act_per_share = (act_amount * 1_000_000_000) / base_share.amount();

        let act_to_new_share = (amount * act_per_share) / 1_000_000_000;
        
        let mut new_share = StakedPoolShare<PoolType, NativeType, RewardType>{
            id: object::new(ctx),
            start_num: (base_share.start_num),
            end_num: base_share.start_num + amount -1 ,
        };
        let new_share_id =  new_share.id.uid_to_inner();
        df::add<ID, u64>(&mut new_share.id, new_share_id, act_to_new_share);

        base_share.start_num =  base_share.start_num + amount;

        act_amount = act_amount - act_to_new_share;
        df::add<ID, u64>(&mut base_share.id, base_share_id, act_amount);
        
        new_share
    }

    public fun merge<PoolType, NativeType, RewardType>(
        base_share: &mut StakedPoolShare<PoolType, NativeType, RewardType>,
       mut  merging_share: StakedPoolShare<PoolType, NativeType, RewardType>,
    ){
        assert!(
            (base_share.start_num  == merging_share.end_num + 1) ||
            (base_share.end_num + 1 == merging_share.start_num),
            ENumberCannotCombine
        );

         let base_share_id =  base_share.id.uid_to_inner();
          let merge_share_id = merging_share.id.uid_to_inner();

        let base_act = df::remove<ID, u64>(&mut base_share.id,base_share_id);
        let merge_act = df::remove<ID, u64>(&mut merging_share.id, merge_share_id);
        let total_act = base_act + merge_act;

        let StakedPoolShare<PoolType, NativeType, RewardType>{
            id,
            start_num,
            end_num,
        } =  merging_share;


        if (base_share.start_num  == end_num + 1){
            base_share.start_num = start_num;
        }else{
            base_share.end_num = end_num;
        };

        
        df::add(&mut base_share.id, base_share_id, total_act);

        object::delete(id);

    }

    public(package) fun amount<PoolType, NativeType, RewardType>(
        share: &StakedPoolShare<PoolType, NativeType, RewardType>,
    ): u64{
          share.end_num - share.start_num + 1u64
    }

    public(package) fun to_number_pool<PoolType, NativeType, RewardType>(
        number_pool: &mut NumberPool<PoolType, NativeType, RewardType>,
        share_supply: &mut ShareSupply<PoolType, NativeType, RewardType>,
        share: StakedPoolShare<PoolType, NativeType, RewardType>,
    ){
        share_supply.active_supply = share_supply.active_supply - (share.end_num - share.start_num + 1);
        number_pool.available_shares.push_back(share);
    }

    public fun start_num<PoolType, NativeType, RewardType>(
        share: &StakedPoolShare<PoolType, NativeType, RewardType>,
    ): u64{
        share.start_num
    }

    public fun end_num<PoolType, NativeType, RewardType>(
        share: &StakedPoolShare<PoolType, NativeType, RewardType>,
    ): u64{
        share.end_num
    }

    public fun total_supply<PoolType, NativeType, RewardType>(
        share_supply: &ShareSupply<PoolType, NativeType, RewardType>,
    ): u64{
        share_supply.total_supply
    }

    public fun active_supply<PoolType, NativeType
    , RewardType>(
        share_supply: &ShareSupply<PoolType, NativeType, RewardType>,
    ):u64{
         share_supply.active_supply
    }

    public(package) fun uid<PoolType, NativeType, RewardType>(
        share: &mut StakedPoolShare<PoolType, NativeType, RewardType>,
    ): &mut UID{
         &mut share.id
    }



}