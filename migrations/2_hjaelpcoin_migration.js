var fs = require('fs');
var configs = require("../config.json");
var HjaelpCoin = artifacts.require("HjaelpCoin");
var uniswapRouterABI = require('../build/contracts/IUniswapV2Router02.json');
var hjaelpABI = require('../build/contracts/HjaelpCoin.json');

function getUtcTimestamp() {
  var d1 = new Date();
  var d2 = new Date(d1.getUTCFullYear(), d1.getUTCMonth(), d1.getUTCDate(), d1.getUTCHours(), d1.getUTCMinutes(), d1.getUTCSeconds());
  var utc_timestamp = d2.getTime();
  return Math.floor(utc_timestamp / 1000);
}

module.exports = async function (deployer) {
  try {
    let dataParse = {};

    // Deploy HjaelpCoin
    await deployer.deploy(HjaelpCoin);
    let hjaelpInstance = await HjaelpCoin.deployed();
    // Save the deployed address
    dataParse['HjaelpCoin'] = hjaelpInstance.address;
    // Mint coins to owner wallet
    await hjaelpInstance.mint(configs.owner, web3.utils.toBN(configs.initial_mint));

    const uniswap_address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const hjaelp = new web3.eth.Contract(hjaelpABI.abi, hjaelpInstance.address);
    const tx1 = await hjaelp.methods.approve(
      uniswap_address,
      web3.utils.toWei(configs.initial_liquidity.token)
    ).send({
      from: configs.owner
    })
    console.log("approved", tx1);

    const router = new web3.eth.Contract(uniswapRouterABI.abi, uniswap_address);
    const tx2 = await router.methods.addLiquidityETH(
      hjaelpInstance.address,
      web3.utils.toWei(configs.initial_liquidity.token),
      0,
      0,
      configs.owner,
      getUtcTimestamp() + 1000000
    ).send({
      value: web3.utils.toWei(configs.initial_liquidity.eth),
      from: configs.owner,
      gas: 10000000,
    });
    console.log("liquidity added");

    // Write result file
    const dataText = JSON.stringify(dataParse);
    await fs.promises.writeFile('contracts.json', dataText);
  } catch (e) {
    console.log(e);
  }
};
