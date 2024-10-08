## AutoVeBribe

AutoVeBribe is a contract that hold token to incentivize voting reward (bribe) for Velodrome/Aerodrome.
Each week it can distribute the token only once between the voting period.

### Role

- Owner - Set amount to distribute per epoch and recover the token (if gague is blacklisted or not whitelisted token)
- Keeper - Someone who trigger the contract to send token to `BribeVotingReward`, optionally can be Chainlink Automation/Gelato Automate.

### Metrics

- nSLOC: 184
- Complexity score: 191

### Setup

```bash
forge install
```

To test, setup Base RPC URL with env `BASE_RPC_URL`
