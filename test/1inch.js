// mod.cjs
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args));
// dotenvConfig({ path: resolve(__dirname, "./.env") });

const apiBaseUrl = "https://api.1inch.dev/swap/v5.2/";

function apiRequestUrl(methodName, chainId, queryParams) {
  return apiBaseUrl + chainId + methodName + "?" + new URLSearchParams(queryParams).toString();
}

async function main() {
  let disableEstimate = true;
  const args = process.argv.slice(2);
  const chainId = args[0];
  const fromTokenAddress = args[1];
  const toTokenAddress = args[2];
  const amount = args[3];
  const fromAddress = args[4];
  const slippage = 2;
  const destReceiver = args[5];

  let protocols = chainId == "42161" ? [
    // "ARBITRUM_SUSHISWAP", 
    "ARBITRUM_UNISWAP_V3", 
    // "ARBITRUM_CURVE", 
    // "ARBITRUM_CURVE_V2"
  ] : [
    "SUSHI", 
    "UNISWAP_V2", 
    "UNISWAP_V3", 
    "CURVE", 
    "COMPOUND"
  ];

  return fetch(
    apiRequestUrl("/swap", chainId, { fromTokenAddress, toTokenAddress, amount, fromAddress, slippage, destReceiver, disableEstimate, protocols }),
    {headers: { "Content-Type": "application/json", "Authorization": "Bearer pUsCKhtRswhfKE0XVWvLWGns9VMwW8ha", "accept": "application/json" }},
  )
    .then((res) => res.json())
    .then((res) => { console.log(res.tx.data); return res.tx.data});
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then()
  .catch((error) => {
    console.error(error);
    throw new Error("Exit: 1");
  });
