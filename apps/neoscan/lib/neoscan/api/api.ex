defmodule Neoscan.Api do
  import Ecto.Query, warn: true
  alias Neoscan.Repo
  alias Neoscan.Addresses.Address
  alias Neoscan.Transactions
  alias Neoscan.Transactions.Transaction
  alias Neoscan.Transactions.Asset
  alias Neoscan.Blocks.Block
  alias Neoscan.Transactions.Vout

  @moduledoc """
    Main API for accessing data from the explorer.
    All data is provided through GET requests in `/api/main_net/v1`.
    Testnet isn't currently available.
  """

  #sanitize struct
  defimpl Poison.Encoder, for: Any do
    def encode(%{__struct__: _} = struct, options) do
      struct
        |> Map.from_struct
        |> sanitize_map
        |> Poison.Encoder.Map.encode(options)
    end

    defp sanitize_map(map) do
      Map.drop(map, [:__meta__, :__struct__])
    end
  end


  @doc """
  Returns the balance for an address from its `hash_string`

  ## Examples

      /api/main_net/v1/get_balance/{hash_string}
      "{
        \"balance\": [
          {
            \"asset\": \"name_string\",
            \"amount\": float
          }
          ...
        ],
        \"address\": \"hash_string\"
      }"

  """
  def get_balance(hash) do
    query = from e in Address,
    where: e.address == ^hash,
    select: %{:address => e.address, :balance => e.balance}

    result = case Repo.one(query) do
        nil -> %{:address => "not found", :balance => nil}

        %{} = address ->
          new_balance =Enum.map(address.balance, fn %{"asset" => asset, "amount" => amount} ->
            %{"asset" => Transactions.get_asset_name_by_hash(asset), "amount" => amount} end)
          Map.put(address, :balance, new_balance)
      end

    Poison.encode!(result)
  end

  @doc """
  Returns the claimed transactions for an address, from its `hash_string`.

  ## Examples

      /api/main_net/v1/get_claimed/{hash_string}
      "{
        \"claimed\": [
          \"tx_id_string\",
          \"tx_id_string\",
          \"tx_id_string\",
          ...
        ],
        \"address\": \"hash_string\"
      }"

  """
  def get_claimed(hash) do
    query = from e in Address,
    where: e.address == ^hash,
    select: %{:address => e.address, :claimed => e.claimed}

    result = case Repo.one(query) do
        nil -> %{:address => "not found", :claimed => nil}

        %{} = address ->
          address
      end

    Poison.encode!(result)
  end

  @doc """
  Returns the address model from its `hash_string`

  ## Examples

      /api/main_net/v1/get_address/{hash_string}
      "{
        \"txids\": [
          \"tx_id_string\",
          \"tx_id_string\",
          \"tx_id_string\",
          ...
        ],
        \"claimed\": [
          \"tx_id_string\",
          \"tx_id_string\",
          \"tx_id_string\",
          ...
        ],
        \"balance\": [
          {
            \"asset\": \"name_string\",
            \"amount\": float
          }
          ...
        ],
        \"address\": \"hash_string\"
      }"

  """
  def get_address(hash) do
    query = from e in Address,
    where: e.address == ^hash,
    select: %{:address => e.address, :balance => e.balance, :txids => e.tx_ids, :claimed => e.claimed}

    result = case Repo.one(query) do
        nil -> %{:address => "not found", :balance => nil, :txids => nil, :claimed => nil}

        %{} = address ->
          new_balance =Enum.map(address.balance, fn %{"asset" => asset, "amount" => amount} ->
            %{"asset" => Transactions.get_asset_name_by_hash(asset), "amount" => amount} end)
          Map.put(address, :balance, new_balance)
      end

    Poison.encode!(result)
  end

  @doc """
  Returns registered assets in the chain

  ## Examples

      /api/main_net/v1/get_assets
      "[
        {
          \"type\": \"type_string\",
          \"txid\": \"tx_id_string\",
          \"precision\": integer,
          \"owner\": \"hash_string\",
          \"name\": [
            {
              \"name\": \"name_string\",
              \"lang\": \"language_code_string\"
            },
            ...
          ],
          \"amount\": float,
          \"admin\": \"hash_string\"
        },
        ...
      ]"

  """
  def get_assets() do
    Repo.all(Asset)
    |> Enum.map(fn x ->
        Map.delete(x, :inserted_at)
        |> Map.delete(:updated_at)
        |> Map.delete(:id)
    end)
    |> Poison.encode!
  end

  @doc """
  Returns asset model from its `hash_string`

  ## Examples

      /api/main_net/v1/get_asset/{hash_string}
      "{
        \"type\": \"type_string\",
        \"txid\": \"tx_id_string\",
        \"precision\": integer,
        \"owner\": \"hash_string\",
        \"name\": [
          {
            \"name\": \"name_string\",
            \"lang\": \"language_code_string\"
          },
          ...
        ],
        \"amount\": float,
        \"admin\": \"hash_string\"
      }"

  """
  def get_asset(hash) do
    query = from e in Asset,
    where: e.txid == ^hash

    result = case Repo.one(query) do
        nil -> %{:txid => "not found",
         :admin => nil,
         :amount => nil,
         :name => nil,
         :owner => nil,
         :precision => nil,
         :type => nil,
       }
        %{} = asset ->
          asset
      end

    Map.delete(result, :inserted_at)
    |> Map.delete(:updated_at)
    |> Map.delete(:id)
    |> Poison.encode!
  end

  @doc """
  Returns the block model from its `hash_string` or `height`

  ## Examples

      /api/main_net/v1/get_block/{hash_string}
      /api/main_net/v1/get_block/{height}
      "{
        \"version\": integer,
        \"tx_count\": integer,
        \"transactions\": [
          \"tx_id_string\",
          ...
        ],
        \"time\": unix_time,
        \"size\": integer,
        \"script\": {
          \"verification\": \"hash_string\",
          \"invocation\": \"hash_string\"
        },
        \"previousblockhash\": \"hash_string\",
        \"nonce\": \"hash_string\",
        \"nextconsensus\": \"hash_string\",
        \"nextblockhash\": \"hash_string\",
        \"merkleroot\": \"hash_string\",
        \"index\": integer,
        \"hash\": \"hash_string\",
        \"confirmations\": integer
      }"

  """
  def get_block(hash_or_integer) do
    tran_query = from t in Transaction,
    select: t.txid

    query = try  do
      String.to_integer(hash_or_integer)
    rescue
      ArgumentError ->
        from e in Block,
         where: e.hash == ^hash_or_integer,
         preload: [transactions: ^tran_query]
    else
      hash_or_integer ->
        from e in Block,
         where: e.index == ^hash_or_integer,
         preload: [transactions: ^tran_query]
    end

    result = case Repo.one(query) do
        nil -> %{:hash => "not found",
         :confirmations => nil,
         :index => nil,
         :merkleroot => nil,
         :nextblockhash => nil,
         :nextconcensus => nil,
         :nonce => nil,
         :previousblockhash => nil,
         :scrip => nil,
         :size => nil,
         :time => nil,
         :version => nil,
         :tx_count => nil,
         :transactions => nil,
       }
        %{} = block ->
          block
      end
      Map.delete(result, :inserted_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:id)
      |> Poison.encode!
  end

  @doc """
  Returns the last 20 block models

  ## Examples

      /api/main_net/v1/get_last_blocks
     "[
        {
          \"version\": integer,
          \"tx_count\": integer,
          \"transactions\": [
            \"tx_id_string\",
            ...
          ],
          \"time\": unix_time,
          \"size\": integer,
          \"script\": {
            \"verification\": \"hash_string\",
            \"invocation\": \"hash_string\"
          },
          \"previousblockhash\": \"hash_string\",
          \"nonce\": \"hash_string\",
          \"nextconsensus\": \"hash_string\",
          \"nextblockhash\": \"hash_string\",
          \"merkleroot\": \"hash_string\",
          \"index\": integer,
          \"hash\": \"hash_string\",
          \"confirmations\": integer
        },
        ...
      ]"

  """
  def get_last_blocks() do
    tran_query = from t in Transaction,
    select: t.txid

    query = from e in Block,
      order_by: [desc: e.index],
      preload: [transactions: ^tran_query],
      limit: 20

      Repo.all(query)
      |> Enum.map(fn x ->
          Map.delete(x, :inserted_at)
          |> Map.delete(:updated_at)
          |> Map.delete(:id)
      end)
      |> Poison.encode!
  end

  @doc """
  Returns the highest block model in the chain

  ## Examples

      /api/main_net/v1/get_highest_block
      "{
        \"version\": integer,
        \"tx_count\": integer,
        \"transactions\": [
          \"tx_id_string\",
          ...
        ],
        \"time\": unix_time,
        \"size\": integer,
        \"script\": {
          \"verification\": \"hash_string\",
          \"invocation\": \"hash_string\"
        },
        \"previousblockhash\": \"hash_string\",
        \"nonce\": \"hash_string\",
        \"nextconsensus\": \"hash_string\",
        \"nextblockhash\": \"hash_string\",
        \"merkleroot\": \"hash_string\",
        \"index\": integer,
        \"hash\": \"hash_string\",
        \"confirmations\": integer
      }"

  """
  def get_highest_block() do
    tran_query = from t in Transaction,
    select: t.txid

    query = from e in Block,
      order_by: [desc: e.index],
      preload: [transactions: ^tran_query],
      limit: 1

      Repo.one(query)
      |> Map.delete(:inserted_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:id)
      |> Poison.encode!
  end

  @doc """
  Returns the transaction model through its `hash_string`

  ## Examples

      /api/main_net/v1/get_transaction/{hash_string}
      "{
        \"vouts\": [
          {
            \"value\": float,
            \"n\": integer,
            \"asset\": \"name_string\",
            \"address\": \"hash_string\"
          },
          ...
        ],
        \"vin\": [
          {
            \"value\": float,
            \"txid\": \"tx_id_string\",
            \"n\": integer,
            \"asset\": \"name_string\",
            \"address_hash\": \"hash_string\"
          },
          ...
        ],
        \"version\": integer,
        \"type\": \"type_string\",
        \"txid\": \"tx_id_string\",
        \"time\": unix_time,
        \"sys_fee\": \"string\",
        \"size\": integer,
        \"scripts\": [
          {
            \"verification\": \"hash_string\",
            \"invocation\": \"hash_string\"
          }
        ],
        \"pubkey\": hash_string,
        \"nonce\": integer,
        \"net_fee\": \"string\",
        \"description\": string,
        \"contract\": array,
        \"claims\": array,
        \"block_height\": integer,
        \"block_hash\": \"hash_string\",
        \"attributes\": array,
        \"asset\": array
      }"

  """
  def get_transaction(hash) do
    vout_query = from v in Vout,
    select: %{:asset => v.asset,
              :address => v.address_hash,
              :n => v.n,
              :value => v.value,
            }

    query = from t in Transaction,
         where: t.txid == ^hash,
         preload: [vouts: ^vout_query]

    result = case Repo.one(query) do
        nil -> %{:txid => "not found",
         :attributes => nil,
         :net_fee => nil,
         :scripts => nil,
         :size => nil,
         :sys_fee => nil,
         :type => nil,
         :version => nil,
         :vin => nil,
         :vouts => nil,
         :time => nil,
         :block_hash=> nil,
         :block_height => nil,
         :nonce => nil,
         :claims => nil,
         :pubkey => nil,
         :asset => nil,
         :description => nil,
         :contract => nil,
       }
        %{} = transaction ->
          new_vouts = Enum.map(transaction.vouts, fn %{:asset => asset} = x -> Map.put(x, :asset, Transactions.get_asset_name_by_hash(asset)) end)
          new_vins = Enum.map(transaction.vin, fn %{"asset" => asset} = x -> Map.put(x, "asset", Transactions.get_asset_name_by_hash(asset)) end)
          Map.delete(transaction, :block)
          |> Map.delete(:inserted_at)
          |> Map.delete(:updated_at)
          |> Map.delete(:block_id)
          |> Map.delete(:id)
          |> Map.put(:vouts, new_vouts)
          |> Map.put(:vin, new_vins)
      end

      Poison.encode!(result)
  end

  @doc """
  Returns the last 20 transaction models in the chain for the selected `type`.
  If no `type` is provided, returns all types

  ## Examples

      /api/main_net/v1/get_last_transactions/{type}
      /api/main_net/v1/get_last_transactions
      "[{
          \"vouts\": [
            {
              \"value\": float,
              \"n\": integer,
              \"asset\": \"name_string\",
              \"address\": \"hash_string\"
            },
            ...
          ],
          \"vin\": [
            {
              \"value\": float,
              \"txid\": \"tx_id_string\",
              \"n\": integer,
              \"asset\": \"name_string\",
              \"address_hash\": \"hash_string\"
            },
            ...
          ],
          \"version\": integer,
          \"type\": \"type_string\",
          \"txid\": \"tx_id_string\",
          \"time\": unix_time,
          \"sys_fee\": \"string\",
          \"size\": integer,
          \"scripts\": [
            {
              \"verification\": \"hash_string\",
              \"invocation\": \"hash_string\"
            }
          ],
          \"pubkey\": hash_string,
          \"nonce\": integer,
          \"net_fee\": \"string\",
          \"description\": string,
          \"contract\": array,
          \"claims\": array,
          \"block_height\": integer,
          \"block_hash\": \"hash_string\",
          \"attributes\": array,
          \"asset\": array
        },
        ...
      ]"

  """
  def get_last_transactions(type) do
    vout_query = from v in Vout,
    select: %{:asset => v.asset,
              :address => v.address_hash,
              :n => v.n,
              :value => v.value,
            }

    query = cond do
      type == nil -> from t in Transaction,
        order_by: [desc: t.inserted_at],
        preload: [vouts: ^vout_query],
        limit: 20

      true -> from t in Transaction,
          order_by: [desc: t.inserted_at],
          where: t.type == ^type,
          preload: [vouts: ^vout_query],
          limit: 20
    end


    Repo.all(query)
    |> Enum.map(fn %{:vouts => vouts, :vin => vin} = x ->
        new_vouts = Enum.map(vouts, fn %{:asset => asset} = x -> Map.put(x, :asset, Transactions.get_asset_name_by_hash(asset)) end)
        new_vins = Enum.map(vin, fn %{"asset" => asset} = x -> Map.put(x, "asset", Transactions.get_asset_name_by_hash(asset)) end)
        Map.delete(x, :block)
        |> Map.delete(:inserted_at)
        |> Map.delete(:updated_at)
        |> Map.delete(:block_id)
        |> Map.delete(:id)
        |> Map.put(:vouts, new_vouts)
        |> Map.put(:vin, new_vins)
    end)
    |> Poison.encode!
  end


end
