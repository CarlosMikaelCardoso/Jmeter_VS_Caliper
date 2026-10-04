const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function main() {
    const rpcUrl = process.env.BESU_RPC_URL || 'http://127.0.0.1:8545';
    // Chave padrão usada no script de setup do Besu (EXTERNAL_DEPLOY_ACCOUNT)
    const privateKey = process.env.BESU_DEPLOYER_PRIVATE_KEY || '8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63';
    
    const buildPath = '/home/mikael/Documentos/Codes/facicoin/contratos/build';
    
    // Ler artefatos do FaciCoin (MeuToken)
    const tokenAbi = JSON.parse(fs.readFileSync(path.join(buildPath, 'MeuToken.abi'), 'utf8'));
    const tokenBytecode = fs.readFileSync(path.join(buildPath, 'MeuToken.bin'), 'utf8');

    // Ler artefatos do MarketplaceFacicoin
    const marketAbi = JSON.parse(fs.readFileSync(path.join(buildPath, 'MarketplaceFacicoin.abi'), 'utf8'));
    const marketBytecode = fs.readFileSync(path.join(buildPath, 'MarketplaceFacicoin.bin'), 'utf8');
    
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    
    console.log("-----------------------------------------");
    console.log("Fazendo deploy do FaciCoin (MeuToken)...");
    const tokenFactory = new ethers.ContractFactory(tokenAbi, tokenBytecode, wallet);
    
    // Inicializar com 1 Milhão de moedas (18 decimais)
    const initialSupply = ethers.parseUnits("1000000", 18);
    const tokenContract = await tokenFactory.deploy(initialSupply);
    await tokenContract.waitForDeployment();
    
    const tokenAddress = await tokenContract.getAddress();
    console.log("FaciCoin deployado em:", tokenAddress);

    console.log("-----------------------------------------");
    console.log("Fazendo deploy do MarketplaceFacicoin...");
    const marketFactory = new ethers.ContractFactory(marketAbi, marketBytecode, wallet);
    const marketContract = await marketFactory.deploy(tokenAddress);
    await marketContract.waitForDeployment();

    const marketAddress = await marketContract.getAddress();
    console.log("MarketplaceFacicoin deployado em:", marketAddress);
    
    console.log("-----------------------------------------");
    console.log("Deploy finalizado com sucesso!");
    console.log("Agora você pode configurar o Caliper ou o JMeter usando esses endereços.");
}

main().catch(console.error);
