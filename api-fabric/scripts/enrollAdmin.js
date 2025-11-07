/*
 * Este script importa uma identidade de administrador existente 
 * do file system (criada pelo test-network) para a carteira da API.
 */
'use strict';

const { Wallets } = require('fabric-network'); // Apenas 'fabric-network' é necessário
const fs = require('fs');
const path = require('path');

// --- PONTO DE CONFIGURAÇÃO PRINCIPAL ---

// Caminho para o perfil de conexão
const ccpPath = path.resolve(__dirname, '..', 'config', 'connection-profile.json');

// Caminho para o diretório MSP do admin da Org1
const mspPath = path.resolve(
    __dirname,
    '../../../Jmeter_VS_Caliper/testes_fabric/network_fabric/test-network/organizations/peerOrganizations/org1.example.com'
);

// Caminhos corretos para os arquivos do *Admin*
const certPath = path.join(mspPath, 'users', 'Admin@org1.example.com', 'msp', 'signcerts', 'Admin@org1.example.com-cert.pem');
const keyPathDir = path.join(mspPath, 'users', 'Admin@org1.example.com', 'msp', 'keystore');

// --- FIM DA CONFIGURAÇÃO ---

async function main() {
    try {
        if (!fs.existsSync(ccpPath)) {
            console.error(`Erro: Perfil de conexão não encontrado em ${ccpPath}`);
            console.error('Por favor, copie o seu connection-profile.json para a pasta api-fabric/config/');
            process.exit(1);
        }
        if (!fs.existsSync(certPath)) {
            console.error(`Erro: Certificado do Admin não encontrado em ${certPath}`);
            console.error('Por favor, verifique o caminho para sua pasta fabric-samples.');
            process.exit(1);
        }
        if (!fs.existsSync(keyPathDir)) {
            console.error(`Erro: Diretório keystore do Admin não encontrado em ${keyPathDir}`);
            process.exit(1);
        }

        // Encontra o arquivo de chave privada (que tem um hash no nome)
        const keystoreFiles = fs.readdirSync(keyPathDir);
        const privateKeyFile = keystoreFiles.find(file => file.endsWith('_sk'));
        if (!privateKeyFile) {
            console.error(`Erro: Chave privada do Admin não encontrada em ${keyPathDir}`);
            process.exit(1);
        }
        const privateKeyPath = path.join(keyPathDir, privateKeyFile);

        // Carrega o perfil de conexão
        const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

        // Cria a carteira (wallet)
        const walletPath = path.join(process.cwd(), 'wallet');
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        console.log(`Carteira (wallet) sendo usada em: ${walletPath}`);

        // Verifica se o admin já existe
        const identity = await wallet.get('admin');
        if (identity) {
            console.log('Uma identidade para o usuário "admin" já existe na carteira');
            return;
        }

        // Lê os arquivos de identidade
        const credentials = {
            certificate: fs.readFileSync(certPath, 'utf8'),
            privateKey: fs.readFileSync(privateKeyPath, 'utf8'),
        };

        // Adiciona a identidade à carteira com o nome 'admin'
        const mspId = ccp.organizations['Org1'].mspid; // Assumindo Org1
        const adminIdentity = {
            credentials,
            mspId,
            type: 'X.509',
        };

        await wallet.put('admin', adminIdentity);
        console.log('Identidade "admin" importada para a carteira com sucesso.');

    } catch (error) {
        console.error(`Falha ao registrar o admin: ${error}`);
        process.exit(1);
    }
}

main();