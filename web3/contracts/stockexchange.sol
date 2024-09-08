// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Interface for Kaia Token (ERC-20 standard)
interface IKaiaToken {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract CLOBStockExchange {
    
    struct Company {
        string name;
        string symbol;
        address owner;
        uint256 totalShares;
        uint256 sharePrice; // in Kaia tokens
    }

    enum OrderType { LIMIT, MARKET }

    struct Order {
        address user;
        string symbol;
        uint256 amount;
        uint256 pricePerShare;
        bool isBuy; // Buy (true) or Sell (false)
        OrderType orderType;
    }

    // Reference to the Kaia token contract
    IKaiaToken public kaiaToken;

    // Store companies by symbol
    mapping(string => Company) public companies;

    // Orders book
    Order[] public orderBook;

    // Ownership mapping (symbol -> owner -> number of shares)
    mapping(string => mapping(address => uint256)) public ownership;

    // Events
    event CompanyListed(string symbol, string name, uint256 totalShares, uint256 sharePrice);
    event OrderPlaced(address user, string symbol, uint256 amount, uint256 pricePerShare, bool isBuy, OrderType orderType);
    event TradeExecuted(address buyer, address seller, string symbol, uint256 amount, uint256 pricePerShare);

    constructor(address _kaiaToken) {
        kaiaToken = IKaiaToken(_kaiaToken);
    }

    modifier onlyOwner(string memory symbol) {
        require(companies[symbol].owner == msg.sender, "Only owner can perform this action.");
        _;
    }

    // Function to list a company
    function listCompany(string memory name, string memory symbol, uint256 totalShares, uint256 sharePrice) public {
        require(companies[symbol].owner == address(0), "Company already listed.");
        require(totalShares > 0, "Total shares must be greater than zero.");
        require(sharePrice > 0, "Share price must be greater than zero.");

        companies[symbol] = Company({
            name: name,
            symbol: symbol,
            owner: msg.sender,
            totalShares: totalShares,
            sharePrice: sharePrice
        });

        ownership[symbol][msg.sender] = totalShares;

        emit CompanyListed(symbol, name, totalShares, sharePrice);
    }

    // Function to place an order (buy or sell) with limit or market type
    function placeOrder(
        string memory symbol, 
        uint256 amount, 
        uint256 pricePerShare, 
        bool isBuy, 
        OrderType orderType
    ) public {
        require(companies[symbol].owner != address(0), "Company does not exist.");
        require(amount > 0, "Amount must be greater than zero.");
        require(pricePerShare > 0 || orderType == OrderType.MARKET, "Price per share must be greater than zero.");

        if (isBuy) {
            uint256 totalCost = (orderType == OrderType.LIMIT) ? amount * pricePerShare : 0;
            require(kaiaToken.balanceOf(msg.sender) >= totalCost, "Insufficient Kaia tokens for purchase.");
        } else {
            require(ownership[symbol][msg.sender] >= amount, "Insufficient shares to sell.");
        }

        orderBook.push(Order({
            user: msg.sender,
            symbol: symbol,
            amount: amount,
            pricePerShare: pricePerShare,
            isBuy: isBuy,
            orderType: orderType
        }));

        emit OrderPlaced(msg.sender, symbol, amount, pricePerShare, isBuy, orderType);

        // Attempt to match orders
        matchOrders(symbol);
    }

    // Function to match buy/sell orders (market and limit orders)
    function matchOrders(string memory symbol) internal {
        for (uint i = 0; i < orderBook.length; i++) {
            for (uint j = i + 1; j < orderBook.length; j++) {
                Order storage buyOrder = orderBook[i];
                Order storage sellOrder = orderBook[j];

                if (buyOrder.isBuy && !sellOrder.isBuy && keccak256(abi.encodePacked(buyOrder.symbol)) == keccak256(abi.encodePacked(sellOrder.symbol))) {
                    uint256 tradePrice = sellOrder.pricePerShare;

                    if (buyOrder.orderType == OrderType.MARKET) {
                        tradePrice = sellOrder.pricePerShare;
                    } else if (buyOrder.pricePerShare >= sellOrder.pricePerShare) {
                        tradePrice = buyOrder.pricePerShare;
                    }

                    uint256 tradeAmount = (buyOrder.amount < sellOrder.amount) ? buyOrder.amount : sellOrder.amount;

                    ownership[symbol][buyOrder.user] += tradeAmount;
                    ownership[symbol][sellOrder.user] -= tradeAmount;

                    uint256 totalPrice = tradeAmount * tradePrice;
                    kaiaToken.transferFrom(buyOrder.user, sellOrder.user, totalPrice);

                    emit TradeExecuted(buyOrder.user, sellOrder.user, symbol, tradeAmount, tradePrice);

                    buyOrder.amount -= tradeAmount;
                    sellOrder.amount -= tradeAmount;

                    if (buyOrder.amount == 0) {
                        removeOrder(i);
                    }
                    if (sellOrder.amount == 0) {
                        removeOrder(j);
                    }

                    return;
                }
            }
        }
    }

    // Function to remove an order from the order book
    function removeOrder(uint index) internal {
        if (index >= orderBook.length) return;

        for (uint i = index; i < orderBook.length - 1; i++) {
            orderBook[i] = orderBook[i + 1];
        }
        orderBook.pop();
    }
}