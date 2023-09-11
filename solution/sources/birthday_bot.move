module overmind::birthday_bot {
    use aptos_std::table::Table;
    use std::signer;
    use std::error;
    use aptos_framework::account;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::table;
    use aptos_framework::timestamp;

    //
    // Errors
    //
    const ERROR_DISTRIBUTION_STORE_EXIST: u64 = 0;
    const ERROR_DISTRIBUTION_STORE_DOES_NOT_EXIST: u64 = 1;
    const ERROR_LENGTHS_NOT_EQUAL: u64 = 2;
    const ERROR_BIRTHDAY_GIFT_DOES_NOT_EXIST: u64 = 3;
    const ERROR_BIRTHDAY_TIMESTAMP_SECONDS_HAS_NOT_PASSED: u64 = 4;

    //
    // Data structures
    //
    struct BirthdayGift has drop, store {
        amount: u64,
        birthday_timestamp_seconds: u64,
    }

    struct DistributionStore has key {
        owner: address,
        birthday_gifts: Table<address, BirthdayGift>,
        signer_capability: account::SignerCapability,
    }

    //
    // Entry functions
    //
    public entry fun initialize_distribution(
        account: &signer,
        addresses: vector<address>,
        amounts: vector<u64>,
        birthday_timestamps: vector<u64>
    ) {
        let account_address = signer::address_of(account);

        assert_distribution_store_does_not_exist(account_address);
        assert_lengths_are_equal(addresses, amounts, birthday_timestamps);

        let (account_signer, signer_capability) = account::create_resource_account(account, vector::empty());

        // Register the automated_birthday_gifts contract account to receive APT
        coin::register<AptosCoin>(&account_signer);

        let birthday_gifts: Table<address, BirthdayGift> = table::new();
        let total_amount = 0;

        let i = 0;
        while (i < vector::length(&addresses)) {
            let address = vector::borrow(&addresses, i);
            let amount = vector::borrow(&amounts, i);
            let birthday_timestamp_seconds = vector::borrow(&birthday_timestamps, i);
            total_amount = total_amount + *amount;

            table::upsert(
                &mut birthday_gifts,
                *address,
                BirthdayGift { amount: *amount, birthday_timestamp_seconds: *birthday_timestamp_seconds }
            );

            i = i + 1;
        };

        coin::transfer<AptosCoin>(
            account,
            account::get_signer_capability_address(&signer_capability),
            total_amount
        );

        move_to(account, DistributionStore {
            owner: account_address,
            birthday_gifts,
            signer_capability
        });
    }

    public entry fun add_birthday_gift(
        account: &signer,
        address: address,
        amount: u64,
        birthday_timestamp_seconds: u64
    ) acquires DistributionStore {
        let account_address = signer::address_of(account);

        assert_distribution_store_exists(account_address);

        let distribution_store = borrow_global_mut<DistributionStore>(account_address);

        let new_amount = amount;

        if (table::contains(&mut distribution_store.birthday_gifts, address)) {
            let birthday_gift = table::borrow(&mut distribution_store.birthday_gifts, address);
            new_amount = birthday_gift.amount + amount;
        };

        table::upsert(
            &mut distribution_store.birthday_gifts,
            address,
            BirthdayGift { amount: new_amount, birthday_timestamp_seconds }
        );

        coin::transfer<AptosCoin>(
            account,
            account::get_signer_capability_address(&distribution_store.signer_capability),
            amount
        );
    }

    public entry fun remove_birthday_gift(
        account: &signer,
        address: address,
    ) acquires DistributionStore {
        let account_address = signer::address_of(account);

        assert_distribution_store_exists(account_address);

        let distribution_store = borrow_global_mut<DistributionStore>(account_address);

        if (table::contains(&mut distribution_store.birthday_gifts, address)) {
            let birthday_gift = table::remove(&mut distribution_store.birthday_gifts, address);
            coin::transfer<AptosCoin>(
                &account::create_signer_with_capability(&distribution_store.signer_capability),
                account_address,
                birthday_gift.amount
            );
        };
    }

    public entry fun claim_birthday_gift(
        account: &signer,
        distribution_address: address,
    ) acquires DistributionStore {
        let account_address = signer::address_of(account);

        assert_distribution_store_exists(distribution_address);
        assert_birthday_gift_exists(distribution_address, account_address);
        assert_birthday_timestamp_seconds_has_passed(distribution_address, account_address);

        let distribution_store = borrow_global_mut<DistributionStore>(distribution_address);
        let birthday_gift = table::remove(&mut distribution_store.birthday_gifts, account_address);
        coin::transfer<AptosCoin>(
            &account::create_signer_with_capability(&distribution_store.signer_capability),
            account_address,
            birthday_gift.amount
        );
    }

    //
    // Assert functions
    //
    public fun assert_distribution_store_exists(
        account_address: address,
    ) {
        assert!(
            exists<DistributionStore>(account_address),
            error::invalid_state(ERROR_DISTRIBUTION_STORE_DOES_NOT_EXIST)
        );
    }

    public fun assert_distribution_store_does_not_exist(
        account_address: address,
    ) {
        assert!(
            !exists<DistributionStore>(account_address),
            error::invalid_state(ERROR_DISTRIBUTION_STORE_EXIST)
        );
    }

    public fun assert_lengths_are_equal(
        addresses: vector<address>,
        amounts: vector<u64>,
        timestamps: vector<u64>
    ) {
        assert!(
            vector::length(&addresses) == vector::length(&amounts),
            error::invalid_state(ERROR_LENGTHS_NOT_EQUAL)
        );

        assert!(
            vector::length(&amounts) == vector::length(&timestamps),
            error::invalid_state(ERROR_LENGTHS_NOT_EQUAL)
        );
    }

    public fun assert_birthday_gift_exists(
        distribution_address: address,
        address: address,
    ) acquires DistributionStore {
        let distribution_store = borrow_global_mut<DistributionStore>(distribution_address);

        assert!(
            table::contains(&mut distribution_store.birthday_gifts, address),
            error::invalid_argument(ERROR_BIRTHDAY_GIFT_DOES_NOT_EXIST)
        );
    }

    public fun assert_birthday_timestamp_seconds_has_passed(
        distribution_address: address,
        address: address,
    ) acquires DistributionStore {
        let distribution_store = borrow_global_mut<DistributionStore>(distribution_address);
        let birthday_gift = table::borrow(&distribution_store.birthday_gifts, address);

        assert!(
            timestamp::now_seconds() > birthday_gift.birthday_timestamp_seconds,
            error::invalid_state(ERROR_BIRTHDAY_TIMESTAMP_SECONDS_HAS_NOT_PASSED)
        );
    }
}