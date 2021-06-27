import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import { HardhatUserConfig, task } from 'hardhat/config'

task('accounts', 'Prints the list of accounts', async (args, hre) => {
    const accounts = await hre.ethers.getSigners()

    for (const account of accounts) {
        console.log(account.address)
    }
})

const config: HardhatUserConfig = {
    solidity: '0.6.6',
    networks: {
        hardhat: {
            mining: {
                auto: process.env.AUTOMINE?.toLowerCase() === 'true',
            },
            forking: {
                url: 'https://eth-mainnet.alchemyapi.io/v2/PVyuKzTstUnizfSwYzQ2FDhzkIWSuXrt',
                // blockNumber: 12490866,
            },
            accounts: {
                accountsBalance: '1000000000000000000000000', // 1M ETH
            },
        },
    },
}
module.exports = config
