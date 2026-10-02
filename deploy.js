const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
    const rpcUrl = process.env.BESU_RPC_URL || 'http://127.0.0.1:8545';
    const privateKey = process.env.BESU_DEPLOYER_PRIVATE_KEY || '8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63';
    
    // Ler artefato
    const artifact = JSON.parse(fs.readFileSync('./src/ethereum/simple/simple.json', 'utf8'));
    
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    
    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
    
    console.log("Fazendo deploy do contrato...");
    const contract = await factory.deploy();
    await contract.waitForDeployment();
    
    const address = await contract.getAddress();
    console.log("Contrato deployado com sucesso!");
    console.log("ADDRESS=" + address);
}

main().catch(console.error);
