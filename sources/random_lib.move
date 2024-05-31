module nui_finance::random_lib{
    use sui::bls12381;
    use sui::hash::{Self,};
    use sui::bcs::{Self,};
    use sui::clock::{Self, Clock};
    use nui_finance::pool::{ Self, Pool, GlobalConfig};

    const VERSION: u64 = 1;

    const EVersionNotMatched: u64 = 0;
    const EInvalidSig: u64 = 1;

    public(package) fun verify_and_random<PoolType, NativeType, RewardType>(
        config: &GlobalConfig,
        pool: &Pool<PoolType, NativeType, RewardType>,
        mut bls_sig: vector<u8>,
        public_key: vector<u8>,
        message: vector<u8>,
        range: u64,
        clock: &Clock,
    ):u64{
        assert!(pool::config_veriosn(config) == VERSION, EVersionNotMatched);
        let round = pool.current_round();
        let encode_round = bcs::to_bytes<u64>(&round);
        let encode_timestamp = bcs::to_bytes<u64>(&clock::timestamp_ms(clock));
        let verified = bls12381::bls12381_min_pk_verify(&bls_sig, &public_key, &message);
        assert!(verified, EInvalidSig);
        bls_sig.append(encode_round);
        bls_sig.append(encode_timestamp);
        bls_sig.append(message);
        let hashed_beacon = hash::blake2b256(&bls_sig);
        let mut bsc_res = bcs::new(hashed_beacon);
        let random = bsc_res.peel_u64();
        let res = random % (range + 1);
        res
    }
}