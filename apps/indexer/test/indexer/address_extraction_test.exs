defmodule Indexer.AddressExtractionTest do
  use Explorer.DataCase, async: true

  alias Indexer.AddressExtraction

  doctest AddressExtraction

  describe "extract_addresses/1" do
    test "blocks without a `miner_hash` aren't extracted" do
      assert Indexer.AddressExtraction.extract_addresses(%{
               blocks: [
                 %{
                   number: 34
                 }
               ]
             }) == []
    end

    test "blocks without a `number` aren't extracted" do
      assert Indexer.AddressExtraction.extract_addresses(%{
               blocks: [
                 %{
                   miner_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca"
                 }
               ]
             }) == []
    end

    test "internal_transactions with a `from_address_hash` without a `block_number` aren't extracted" do
      assert Indexer.AddressExtraction.extract_addresses(%{
               internal_transactions: [
                 %{
                   from_address_hash: "0x0000000000000000000000000000000000000001"
                 }
               ]
             }) == []
    end

    test "internal_transactions with a `to_address_hash` without a `block_number` aren't extracted" do
      assert Indexer.AddressExtraction.extract_addresses(%{
               internal_transactions: [
                 %{
                   to_address_hash: "0x0000000000000000000000000000000000000002"
                 }
               ]
             }) == []
    end

    test "internal_transactions with a `created_contract_address_hash` and `created_contract_code` " <>
           "without a `block_number` aren't extracted" do
      assert Indexer.AddressExtraction.extract_addresses(%{
               internal_transactions: [
                 %{
                   created_contract_address_hash: "0x0000000000000000000000000000000000000003",
                   created_contract_code: "0x"
                 }
               ]
             }) == []
    end

    test "differing contract code is ignored" do
      assert Indexer.AddressExtraction.extract_addresses(%{
               internal_transactions: [
                 %{
                   block_number: 1,
                   created_contract_code: "0x1",
                   created_contract_address_hash: "0x0000000000000000000000000000000000000001"
                 },
                 %{
                   block_number: 2,
                   created_contract_code: "0x2",
                   created_contract_address_hash: "0x0000000000000000000000000000000000000001"
                 }
               ]
             }) == [
               %{
                 fetched_balance_block_number: 2,
                 contract_code: "0x2",
                 hash: "0x0000000000000000000000000000000000000001"
               }
             ]
    end

    test "returns all hashes entities data in a list" do
      block = %{number: 1, miner_hash: gen_hash()}

      internal_transaction = %{
        block_number: 2,
        from_address_hash: gen_hash(),
        to_address_hash: gen_hash(),
        created_contract_address_hash: gen_hash(),
        created_contract_code: "code"
      }

      transaction = %{
        block_number: 3,
        from_address_hash: gen_hash(),
        to_address_hash: gen_hash()
      }

      log = %{address_hash: gen_hash(), block_number: 4}

      blockchain_data = %{
        blocks: [block],
        internal_transactions: [internal_transaction],
        transactions: [transaction],
        logs: [log]
      }

      assert AddressExtraction.extract_addresses(blockchain_data) == [
               %{hash: block.miner_hash, fetched_balance_block_number: block.number},
               %{
                 hash: internal_transaction.from_address_hash,
                 fetched_balance_block_number: internal_transaction.block_number
               },
               %{
                 hash: internal_transaction.to_address_hash,
                 fetched_balance_block_number: internal_transaction.block_number
               },
               %{
                 hash: internal_transaction.created_contract_address_hash,
                 contract_code: internal_transaction.created_contract_code,
                 fetched_balance_block_number: internal_transaction.block_number
               },
               %{hash: transaction.from_address_hash, fetched_balance_block_number: transaction.block_number},
               %{hash: transaction.to_address_hash, fetched_balance_block_number: transaction.block_number},
               %{hash: log.address_hash, fetched_balance_block_number: log.block_number}
             ]
    end

    test "returns empty list with empty data" do
      empty_blockchain_data = %{
        blocks: [],
        transactions: [],
        internal_transactions: [],
        logs: []
      }

      addresses = AddressExtraction.extract_addresses(empty_blockchain_data)

      assert Enum.empty?(addresses)
    end

    test "addresses get merged when they're duplicated by their hash" do
      hash = "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca"

      blockchain_data = %{
        blocks: [%{miner_hash: hash, number: 34}],
        transactions: [%{block_number: 34, from_address_hash: hash}],
        internal_transactions: [
          %{
            block_number: 34,
            created_contract_address_hash: hash,
            created_contract_code: "code"
          }
        ]
      }

      assert AddressExtraction.extract_addresses(blockchain_data) ==
               [
                 %{hash: hash, fetched_balance_block_number: 34, contract_code: "code"}
               ]
    end

    test "only entities data defined in @entity_to_address_map are collected" do
      blockchain_data = %{
        blocks: [%{miner_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca", number: 34}],
        unkown_entity: [%{hash: "0x8bf38d4764929064f2d4d3a56520a76ab3df415b"}]
      }

      assert AddressExtraction.extract_addresses(blockchain_data) == [
               %{fetched_balance_block_number: 34, hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca"}
             ]
    end

    test "returns an empty list when there isn't a recognized entity" do
      addresses = AddressExtraction.extract_addresses(%{})

      assert Enum.empty?(addresses)
    end
  end

  describe "extract_addresses_from_collection/2" do
    test "returns all matched addresses" do
      fields_map = [
        [%{from: :field_1, to: :hash}],
        [%{from: :field_2, to: :hash}]
      ]

      items = [
        %{field_1: "hash1", field_2: "hash2"},
        %{field_1: "hash1", field_2: "hash3"}
      ]

      assert AddressExtraction.extract_addresses_from_collection(items, fields_map, %AddressExtraction{pending: false}) ==
               [
                 %{hash: "hash1"},
                 %{hash: "hash2"},
                 %{hash: "hash1"},
                 %{hash: "hash3"}
               ]
    end
  end

  describe "extract_addresses_from_item/2" do
    test "only fields specified in the fields map are fetched" do
      fields_map = [
        [%{from: :field_1, to: :hash}]
      ]

      item = %{field_1: "hash1", field_2: "hash2"}

      response = AddressExtraction.extract_addresses_from_item(item, fields_map, %AddressExtraction{pending: false})

      assert response == [%{hash: "hash1"}]
    end

    test "attributes of the same item defined separately in the fields map fetches different addresses" do
      fields_map = [
        [%{from: :field_1, to: :hash}],
        [%{from: :field_2, to: :hash}]
      ]

      item = %{field_1: "hash1", field_2: "hash2"}

      response = AddressExtraction.extract_addresses_from_item(item, fields_map, %AddressExtraction{pending: false})

      assert response == [%{hash: "hash1"}, %{hash: "hash2"}]
    end

    test "a list of attributes in the fields map references the same address" do
      fields_map = [
        [%{from: :field_1, to: :hash}],
        [
          %{from: :field_2, to: :hash},
          %{from: :field_2_code, to: :code}
        ]
      ]

      data = %{field_1: "hash1", field_2: "hash2", field_2_code: "code"}

      response =
        AddressExtraction.extract_addresses_from_item(
          data,
          fields_map,
          %AddressExtraction{pending: false}
        )

      assert response == [
               %{hash: "hash1"},
               %{code: "code", hash: "hash2"}
             ]
    end
  end

  defp gen_hash() do
    Explorer.Chain.Hash.to_string(Explorer.Factory.address_hash())
  end
end